import type { RNInstance } from '@rnoh/react-native-openharmony';
import { common } from '@kit.AbilityKit';
import { DrawableDescriptor, UIContext, window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';

import { SplashScreenStateMachine } from './SplashScreenStateMachine';

const DEFAULT_BACKGROUND: number = 0xffffffff;
const DEFAULT_IMAGE_WIDTH: number = 100;

export class ExpoSplashScreenError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'ExpoSplashScreenError';
    this.code = code;
  }
}

export class SplashScreenRenderState {
  readonly visible: boolean;
  readonly backgroundColor: number;
  readonly image: DrawableDescriptor | undefined;
  readonly resizeMode: string;
  readonly imageWidth: number;
  readonly opacity: number;

  constructor(
    visible: boolean,
    backgroundColor: number,
    image: DrawableDescriptor | undefined,
    resizeMode: string,
    imageWidth: number,
    opacity: number,
  ) {
    this.visible = visible;
    this.backgroundColor = backgroundColor;
    this.image = image;
    this.resizeMode = resizeMode;
    this.imageWidth = imageWidth;
    this.opacity = opacity;
  }

  static hidden(): SplashScreenRenderState {
    return new SplashScreenRenderState(false, DEFAULT_BACKGROUND, undefined, 'contain', DEFAULT_IMAGE_WIDTH, 1);
  }
}

type SplashScreenRenderListener = (state: SplashScreenRenderState) => void;

export interface SplashScreenRuntimeOwner {
  setOptions(duration: number, fade: boolean): void;
  prevent(userControlled: boolean): boolean;
  contentAppeared(): void;
  internalMaybeHide(): void;
  hide(): void;
  isDestroyed(): boolean;
}

class SplashScreenResources {
  readonly backgroundColor: number;
  readonly image: DrawableDescriptor | undefined;
  readonly resizeMode: string;
  readonly imageWidth: number;

  constructor(backgroundColor: number, image: DrawableDescriptor | undefined, resizeMode: string, imageWidth: number) {
    this.backgroundColor = backgroundColor;
    this.image = image;
    this.resizeMode = resizeMode;
    this.imageWidth = imageWidth;
  }
}

class SplashScreenWindowOwner {
  readonly ability: common.UIAbilityContext;
  readonly windowId: number;
  private readonly resources: SplashScreenResources;
  private readonly state: SplashScreenStateMachine = new SplashScreenStateMachine();
  private runtimeId: number | undefined = undefined;
  private listener: SplashScreenRenderListener | undefined = undefined;
  private ui: UIContext | undefined = undefined;
  private duration: number = 400;
  private fade: boolean = true;
  private opacity: number = 1;
  private generation: number = 0;

  constructor(ability: common.UIAbilityContext, id: number, resources: SplashScreenResources) {
    this.ability = ability;
    this.windowId = id;
    this.resources = resources;
  }

  attachView(ui: UIContext, listener: SplashScreenRenderListener): () => void {
    if (this.state.snapshot().destroyed) {
      throw new ExpoSplashScreenError(
        'ERR_SPLASH_SCREEN_ABILITY_DESTROYED',
        'Cannot attach the Expo splash screen after its UIAbility was destroyed.',
      );
    }
    if (this.listener !== undefined) {
      throw new ExpoSplashScreenError(
        'ERR_SPLASH_SCREEN_DUPLICATE_VIEW',
        'The UIAbility mounted more than one ExpoSplashScreenView for the same window.',
      );
    }

    this.ui = ui;
    this.listener = listener;
    this.state.markNativeVisible();
    this.publish();

    return (): void => {
      if (this.listener !== listener) return;

      this.generation += 1;
      this.opacity = 1;
      this.listener = undefined;
      this.ui = undefined;
      this.state.markNativeRemoved();
    };
  }

  beginRuntime(id: number): void {
    this.requireAlive();

    if (this.runtimeId === id) return;

    this.runtimeId = id;
    this.generation += 1;
    this.opacity = 1;
    this.state.prepareForRuntime(this.listener !== undefined);

    this.publish();
  }

  endRuntime(id: number): void {
    if (this.runtimeId !== id) return;
    this.runtimeId = undefined;
    this.generation += 1;
  }

  containsRuntime(id: number): boolean {
    return this.runtimeId === id;
  }

  isDestroyed(): boolean {
    return this.state.snapshot().destroyed;
  }

  setOptions(duration: number, fade: boolean): void {
    if (!Number.isFinite(duration) || duration < 0) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', 'Splash screen duration must be a non-negative finite number.');
    }
    if (this.state.snapshot().destroyed) return;

    this.duration = duration;
    this.fade = fade;
  }

  prevent(userControlled: boolean): boolean {
    if (this.state.snapshot().destroyed) return false;
    return this.state.prevent(userControlled);
  }

  contentAppeared(): void {
    if (this.state.snapshot().destroyed) return;
    if (this.state.contentAppeared()) this.remove(true);
  }

  internalMaybeHide(): void {
    if (this.state.snapshot().destroyed) return;
    if (this.state.internalMaybeHide()) this.remove(true);
  }

  hide(): void {
    if (this.state.snapshot().destroyed) return;
    if (this.state.hide()) this.remove(true);
  }

  prepareForReload(id: number): void {
    if (this.state.snapshot().destroyed || this.runtimeId !== id) return;

    this.generation += 1;
    this.opacity = 1;
    this.state.prepareForRuntime(true);

    this.publish();
  }

  destroy(): void {
    if (!this.state.destroy()) return;

    this.runtimeId = undefined;
    this.generation += 1;
    this.opacity = 1;

    this.publish();

    this.listener = undefined;
    this.ui = undefined;
  }

  private remove(allowFade: boolean): void {
    if (!this.state.snapshot().nativeVisible) return;

    const generation = this.generation;

    if (!allowFade || !this.fade || this.duration <= 0) {
      this.finishRemoval(generation);
      return;
    }

    const ui = this.ui;
    if (ui === undefined || this.listener === undefined) {
      this.finishRemoval(generation);
      return;
    }

    try {
      ui.animateTo(
        {
          duration: this.duration,
          curve: Curve.EaseOut,
          onFinish: (): void => this.finishRemoval(generation),
        },
        (): void => {
          if (generation !== this.generation) return;
          this.opacity = 0;
          this.publish();
        },
      );
      setTimeout((): void => this.finishRemoval(generation), Math.ceil(this.duration) + 100);
    } catch (_) {
      this.finishRemoval(generation);
    }
  }

  private finishRemoval(generation: number): void {
    if (generation !== this.generation) return;

    this.state.markNativeRemoved();
    this.opacity = 1;

    this.publish();
  }

  private publish(): void {
    const listener = this.listener;
    if (listener === undefined) return;

    const state = this.state.snapshot();

    listener(
      new SplashScreenRenderState(
        state.nativeVisible && !state.destroyed,
        this.resources.backgroundColor,
        this.resources.image,
        this.resources.resizeMode,
        this.resources.imageWidth,
        this.opacity,
      ),
    );
  }

  private requireAlive(): void {
    if (this.state.snapshot().destroyed) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_ABILITY_DESTROYED', 'The Expo splash screen owner no longer has a live UIAbility/window.');
    }
  }
}

class SplashScreenCoordinator {
  private static readonly ownersByAbility: Map<common.UIAbilityContext, SplashScreenWindowOwner> = new Map();
  private static readonly ownersByWindow: Map<number, SplashScreenWindowOwner> = new Map();
  private static readonly ownersByRuntime: Map<number, SplashScreenWindowOwner> = new Map();

  static async prepareWindow(ability: common.UIAbilityContext, stage: window.WindowStage): Promise<void> {
    let mainWindow: window.Window;

    try {
      mainWindow = await stage.getMainWindow();
    } catch (error) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_WINDOW', `Unable to locate the UIAbility main window: ${String(error)}`);
    }

    let id: number;

    try {
      id = mainWindow.getWindowProperties().id;
    } catch (error) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_WINDOW', `Unable to inspect the UIAbility main window: ${String(error)}`);
    }

    const abilityOwner = SplashScreenCoordinator.ownersByAbility.get(ability);
    if (abilityOwner !== undefined && abilityOwner.windowId === id) return;
    if (abilityOwner !== undefined) SplashScreenCoordinator.removeOwner(abilityOwner);

    const windowOwner = SplashScreenCoordinator.ownersByWindow.get(id);
    if (windowOwner !== undefined) SplashScreenCoordinator.removeOwner(windowOwner);

    const resources = resolveResources(ability.resourceManager);
    const owner = new SplashScreenWindowOwner(ability, id, resources);

    SplashScreenCoordinator.ownersByAbility.set(ability, owner);
    SplashScreenCoordinator.ownersByWindow.set(id, owner);
  }

  static attachView(ability: common.UIAbilityContext, ui: UIContext, listener: SplashScreenRenderListener): () => void {
    const owner = SplashScreenCoordinator.ownersByAbility.get(ability);
    if (owner === undefined) {
      return (): void => {};
    }

    return owner.attachView(ui, listener);
  }

  static async bindRNInstance(instance: RNInstance): Promise<void> {
    if (SplashScreenCoordinator.ownersByWindow.size === 0) return;

    let mainWindow: window.Window;

    try {
      mainWindow = await instance.getRNWindow();
    } catch (_) {
      return;
    }

    let id: number;

    try {
      id = mainWindow.getWindowProperties().id;
    } catch (_) {
      return;
    }

    const owner = SplashScreenCoordinator.ownersByWindow.get(id);
    if (owner === undefined) return;

    const runtime: number = instance.getId();

    SplashScreenCoordinator.bindRuntime(owner, runtime);
  }

  static bindServiceRuntime(ability: common.UIAbilityContext, id: number): SplashScreenWindowOwner | undefined {
    const owner = SplashScreenCoordinator.ownersByAbility.get(ability);
    if (owner === undefined) return undefined;

    SplashScreenCoordinator.bindRuntime(owner, id);

    return owner;
  }

  static requireRuntime(id: number): SplashScreenWindowOwner {
    const owner = SplashScreenCoordinator.ownersByRuntime.get(id);
    if (owner === undefined || !owner.containsRuntime(id)) {
      throw new ExpoSplashScreenError(
        'ERR_SPLASH_SCREEN_RUNTIME_UNBOUND',
        `RNInstance ${id} was not bound through ExpoSplashScreenLifecycle.onRNInstanceSetUp.`,
      );
    }

    return owner;
  }

  static findRuntime(id: number): SplashScreenWindowOwner | undefined {
    const owner = SplashScreenCoordinator.ownersByRuntime.get(id);
    return owner !== undefined && owner.containsRuntime(id) ? owner : undefined;
  }

  static endRuntime(id: number): void {
    const owner = SplashScreenCoordinator.ownersByRuntime.get(id);
    if (owner === undefined) return;

    SplashScreenCoordinator.ownersByRuntime.delete(id);
    owner.endRuntime(id);
  }

  static prepareRuntimeReload(id: number): void {
    SplashScreenCoordinator.findRuntime(id)?.prepareForReload(id);
  }

  static destroyRuntimeAbility(id: number): void {
    const owner = SplashScreenCoordinator.ownersByRuntime.get(id);
    if (owner === undefined) return;

    SplashScreenCoordinator.removeOwner(owner);
  }

  static destroyAbility(ability: common.UIAbilityContext): void {
    const owner = SplashScreenCoordinator.ownersByAbility.get(ability);
    if (owner !== undefined) SplashScreenCoordinator.removeOwner(owner);
  }

  private static bindRuntime(owner: SplashScreenWindowOwner, id: number): void {
    const previous = SplashScreenCoordinator.ownersByRuntime.get(id);
    if (previous !== undefined && previous !== owner) previous.endRuntime(id);

    Array.from(SplashScreenCoordinator.ownersByRuntime.entries()).forEach((entry) => {
      if (entry[1] === owner && entry[0] !== id) {
        SplashScreenCoordinator.ownersByRuntime.delete(entry[0]);
      }
    });

    owner.beginRuntime(id);
    SplashScreenCoordinator.ownersByRuntime.set(id, owner);
  }

  private static removeOwner(owner: SplashScreenWindowOwner): void {
    owner.destroy();

    if (SplashScreenCoordinator.ownersByAbility.get(owner.ability) === owner) {
      SplashScreenCoordinator.ownersByAbility.delete(owner.ability);
    }

    if (SplashScreenCoordinator.ownersByWindow.get(owner.windowId) === owner) {
      SplashScreenCoordinator.ownersByWindow.delete(owner.windowId);
    }

    Array.from(SplashScreenCoordinator.ownersByRuntime.entries()).forEach((entry) => {
      if (entry[1] === owner) SplashScreenCoordinator.ownersByRuntime.delete(entry[0]);
    });
  }
}

export class ExpoSplashScreenLifecycle {
  static async onWindowStageSetup(ability: common.UIAbilityContext, stage: window.WindowStage): Promise<void> {
    await SplashScreenCoordinator.prepareWindow(ability, stage);
  }

  static onWindowStageWillDestroy(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.destroyAbility(ability);
  }

  static async onRNInstanceSetUp(instance: RNInstance): Promise<void> {
    await SplashScreenCoordinator.bindRNInstance(instance);
  }
}

export function attachSplashScreenView(ability: common.UIAbilityContext, ui: UIContext, listener: SplashScreenRenderListener): () => void {
  return SplashScreenCoordinator.attachView(ability, ui, listener);
}

export function requireSplashScreenRuntime(id: number): SplashScreenRuntimeOwner {
  return SplashScreenCoordinator.requireRuntime(id);
}

export function bindSplashScreenServiceRuntime(ability: common.UIAbilityContext, id: number): SplashScreenRuntimeOwner | undefined {
  return SplashScreenCoordinator.bindServiceRuntime(ability, id);
}

export function findSplashScreenRuntime(id: number): SplashScreenRuntimeOwner | undefined {
  return SplashScreenCoordinator.findRuntime(id);
}

export function endSplashScreenRuntime(id: number): void {
  SplashScreenCoordinator.endRuntime(id);
}

export function prepareSplashScreenRuntimeReload(id: number): void {
  SplashScreenCoordinator.prepareRuntimeReload(id);
}

export function destroySplashScreenRuntimeAbility(id: number): void {
  SplashScreenCoordinator.destroyRuntimeAbility(id);
}

export function destroySplashScreenAbility(ability: common.UIAbilityContext): void {
  SplashScreenCoordinator.destroyAbility(ability);
}

function resolveResources(manager: resourceManager.ResourceManager): SplashScreenResources {
  let background: number = DEFAULT_BACKGROUND;
  let resize: string = 'contain';
  let width: number = DEFAULT_IMAGE_WIDTH;
  let image: DrawableDescriptor | undefined = undefined;

  try {
    background = manager.getColorByNameSync('expo_splash_screen_background');
  } catch (_) {}
  try {
    resize = manager.getStringByNameSync('expo_splash_screen_resize_mode');
  } catch (_) {}
  try {
    width = Number(manager.getStringByNameSync('expo_splash_screen_image_width'));
  } catch (_) {}
  try {
    image = manager.getDrawableDescriptorByName('expo_splash_screen');
  } catch (_) {}

  if (!Number.isFinite(width) || width <= 0) width = DEFAULT_IMAGE_WIDTH;
  if (resize !== 'contain' && resize !== 'cover' && resize !== 'native') {
    resize = 'contain';
  }

  return new SplashScreenResources(background, image, resize, width);
}
