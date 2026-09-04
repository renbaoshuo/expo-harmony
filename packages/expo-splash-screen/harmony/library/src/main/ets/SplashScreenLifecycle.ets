import { common } from '@kit.AbilityKit';
import { DrawableDescriptor, UIContext } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

import { SplashScreenStateMachine } from './SplashScreenStateMachine';

const DEFAULT_BACKGROUND: number = 0xffffffff;
const DEFAULT_IMAGE_WIDTH: number = 100;
const FADE_WATCHDOG_GRACE_MS: number = 100;
const MAX_TIMER_DELAY_MS: number = 2147483647;

export type SplashScreenResizeMode = 'contain' | 'cover' | 'native';

export class ExpoSplashScreenError extends ExpoModuleError {
  constructor(code: string, message: string, cause?: Object) {
    super(code, message, cause);
    this.name = 'ExpoSplashScreenError';
  }
}

export class SplashScreenRenderState {
  readonly visible: boolean;
  readonly backgroundColor: number;
  readonly image: DrawableDescriptor | undefined;
  readonly resizeMode: SplashScreenResizeMode;
  readonly imageWidth: number;
  readonly opacity: number;

  constructor(
    visible: boolean,
    backgroundColor: number,
    image: DrawableDescriptor | undefined,
    resizeMode: SplashScreenResizeMode,
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
  prevent(controlled: boolean): boolean;
  contentAppeared(): void;
  internalMaybeHide(): void;
  hide(): void;
  isDestroyed(): boolean;
}

class SplashScreenResources {
  readonly backgroundColor: number;
  readonly image: DrawableDescriptor | undefined;
  readonly resizeMode: SplashScreenResizeMode;
  readonly valid: boolean;
  readonly imageWidth: number;

  constructor(
    backgroundColor: number,
    image: DrawableDescriptor | undefined,
    resizeMode: SplashScreenResizeMode,
    imageWidth: number,
    valid: boolean,
  ) {
    this.backgroundColor = backgroundColor;
    this.image = image;
    this.resizeMode = resizeMode;
    this.imageWidth = imageWidth;
    this.valid = valid;
  }
}

class SplashScreenAbilityOwner {
  readonly ability: common.UIAbilityContext;
  private readonly resources: SplashScreenResources;
  private readonly state: SplashScreenStateMachine = new SplashScreenStateMachine();
  private epoch: string | undefined = undefined;
  private listener: SplashScreenRenderListener | undefined = undefined;
  private ui: UIContext | undefined = undefined;
  private duration: number = 400;
  private fade: boolean = true;
  private opacity: number = 1;
  private generation: number = 0;
  private timer: number | undefined = undefined;

  constructor(ability: common.UIAbilityContext, resources: SplashScreenResources) {
    this.ability = ability;
    this.resources = resources;
  }

  attachView(ui: UIContext, listener: SplashScreenRenderListener): () => void {
    if (this.state.isDestroyed()) {
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
    if (this.resources.valid) this.state.markNativeVisible();

    this.publish();

    return (): void => {
      if (this.listener !== listener) return;

      this.generation += 1;
      this.clearTimer();
      this.opacity = 1;
      this.listener = undefined;
      this.ui = undefined;
      this.state.markNativeRemoved();
    };
  }

  beginRuntime(epoch: string): void {
    if (this.state.isDestroyed()) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_ABILITY_DESTROYED', 'The Expo splash screen owner no longer has a live UIAbility/window.');
    }
    if (this.epoch === epoch) return;

    this.epoch = epoch;
    this.generation += 1;
    this.clearTimer();
    this.opacity = 1;
    this.state.prepareForRuntime(this.listener !== undefined);

    this.publish();
  }

  endRuntime(epoch: string): void {
    if (this.epoch !== epoch) return;

    this.epoch = undefined;
    this.generation += 1;
    this.clearTimer();
  }

  containsRuntime(epoch: string): boolean {
    return this.epoch === epoch;
  }

  isDestroyed(): boolean {
    return this.state.isDestroyed();
  }

  setOptions(duration: number, fade: boolean): void {
    if (!Number.isFinite(duration) || duration < 0 || duration > MAX_TIMER_DELAY_MS - FADE_WATCHDOG_GRACE_MS) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', 'Splash screen duration must be a non-negative finite number.');
    }
    if (this.state.isDestroyed()) return;

    this.duration = duration;
    this.fade = fade;
  }

  prevent(controlled: boolean): boolean {
    return this.state.prevent(controlled);
  }

  contentAppeared(): void {
    if (this.state.contentAppeared()) this.remove();
  }

  internalMaybeHide(): void {
    if (this.state.internalMaybeHide()) this.remove();
  }

  hide(): void {
    if (this.state.hide()) this.remove();
  }

  prepareForReload(epoch: string): void {
    if (this.state.isDestroyed() || this.epoch !== epoch) return;

    this.generation += 1;
    this.clearTimer();
    this.opacity = 1;
    this.state.prepareForRuntime(true);

    this.publish();
  }

  destroy(): void {
    if (!this.state.destroy()) return;

    this.epoch = undefined;
    this.generation += 1;
    this.clearTimer();
    this.opacity = 1;

    this.publish();

    this.listener = undefined;
    this.ui = undefined;
  }

  private remove(): void {
    if (!this.state.isVisible()) return;

    this.clearTimer();
    const generation = this.generation;

    if (!this.fade || this.duration <= 0) {
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

      this.timer = setTimeout((): void => this.finishRemoval(generation), Math.ceil(this.duration) + FADE_WATCHDOG_GRACE_MS);
    } catch (_) {
      this.finishRemoval(generation);
    }
  }

  private finishRemoval(generation: number): void {
    if (generation !== this.generation) return;

    this.clearTimer();
    this.state.markNativeRemoved();
    this.opacity = 1;

    this.publish();
  }

  private publish(): void {
    const listener = this.listener;
    if (listener === undefined) return;

    listener(
      new SplashScreenRenderState(
        this.state.isVisible() && !this.state.isDestroyed(),
        this.resources.backgroundColor,
        this.resources.image,
        this.resources.resizeMode,
        this.resources.imageWidth,
        this.opacity,
      ),
    );
  }

  private clearTimer(): void {
    if (this.timer === undefined) return;
    clearTimeout(this.timer);
    this.timer = undefined;
  }
}

class SplashScreenCoordinator {
  private static readonly abilities: Map<common.UIAbilityContext, SplashScreenAbilityOwner> = new Map();
  private static readonly runtimes: Map<string, SplashScreenAbilityOwner> = new Map();

  static prepareAbility(ability: common.UIAbilityContext): SplashScreenAbilityOwner {
    const current = SplashScreenCoordinator.abilities.get(ability);
    if (current !== undefined && !current.isDestroyed()) return current;

    const owner = new SplashScreenAbilityOwner(ability, resolveResources(ability.resourceManager));
    SplashScreenCoordinator.abilities.set(ability, owner);

    return owner;
  }

  static attachView(ability: common.UIAbilityContext, ui: UIContext, listener: SplashScreenRenderListener): () => void {
    return SplashScreenCoordinator.prepareAbility(ability).attachView(ui, listener);
  }

  static bindRuntimeForAbility(ability: common.UIAbilityContext, epoch: string): SplashScreenAbilityOwner {
    const owner = SplashScreenCoordinator.prepareAbility(ability);
    SplashScreenCoordinator.bindRuntime(owner, epoch);

    return owner;
  }

  static findRuntime(epoch: string): SplashScreenAbilityOwner | undefined {
    const owner = SplashScreenCoordinator.runtimes.get(epoch);
    return owner !== undefined && owner.containsRuntime(epoch) ? owner : undefined;
  }

  static endRuntime(epoch: string): void {
    const owner = SplashScreenCoordinator.runtimes.get(epoch);
    if (owner === undefined) return;

    SplashScreenCoordinator.runtimes.delete(epoch);
    owner.endRuntime(epoch);
  }

  static prepareRuntimeReload(epoch: string): void {
    SplashScreenCoordinator.findRuntime(epoch)?.prepareForReload(epoch);
  }

  static destroyAbility(ability: common.UIAbilityContext): void {
    const owner = SplashScreenCoordinator.abilities.get(ability);
    if (owner !== undefined) SplashScreenCoordinator.removeOwner(owner);
  }

  private static bindRuntime(owner: SplashScreenAbilityOwner, epoch: string): void {
    const previous = SplashScreenCoordinator.runtimes.get(epoch);
    if (previous !== undefined && previous !== owner) previous.endRuntime(epoch);

    Array.from(SplashScreenCoordinator.runtimes.entries()).forEach((entry) => {
      if (entry[1] === owner && entry[0] !== epoch) {
        SplashScreenCoordinator.runtimes.delete(entry[0]);
      }
    });

    owner.beginRuntime(epoch);
    SplashScreenCoordinator.runtimes.set(epoch, owner);
  }

  private static removeOwner(owner: SplashScreenAbilityOwner): void {
    owner.destroy();

    if (SplashScreenCoordinator.abilities.get(owner.ability) === owner) {
      SplashScreenCoordinator.abilities.delete(owner.ability);
    }

    Array.from(SplashScreenCoordinator.runtimes.entries()).forEach((entry) => {
      if (entry[1] === owner) SplashScreenCoordinator.runtimes.delete(entry[0]);
    });
  }
}

export class ExpoSplashScreenLifecycle {
  static onWindowStageSetup(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.prepareAbility(ability);
  }

  static onWindowStageWillDestroy(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.destroyAbility(ability);
  }
}

export function attachSplashScreenView(ability: common.UIAbilityContext, ui: UIContext, listener: SplashScreenRenderListener): () => void {
  return SplashScreenCoordinator.attachView(ability, ui, listener);
}

export function bindSplashScreenRuntime(ability: common.UIAbilityContext, epoch: string): SplashScreenRuntimeOwner {
  return SplashScreenCoordinator.bindRuntimeForAbility(ability, epoch);
}

export function findSplashScreenRuntime(epoch: string): SplashScreenRuntimeOwner | undefined {
  return SplashScreenCoordinator.findRuntime(epoch);
}

export function endSplashScreenRuntime(epoch: string): void {
  SplashScreenCoordinator.endRuntime(epoch);
}

export function prepareSplashScreenRuntimeReload(epoch: string): void {
  SplashScreenCoordinator.prepareRuntimeReload(epoch);
}

export function destroySplashScreenAbility(ability: common.UIAbilityContext): void {
  SplashScreenCoordinator.destroyAbility(ability);
}

function resolveResources(manager: resourceManager.ResourceManager): SplashScreenResources {
  let background: number = DEFAULT_BACKGROUND;
  let resize: SplashScreenResizeMode = 'contain';
  let width: number = DEFAULT_IMAGE_WIDTH;
  let image: DrawableDescriptor | undefined = undefined;
  let valid: boolean = true;

  try {
    background = manager.getColorByNameSync('expo_splash_screen_background');
  } catch (error) {
    valid = false;
    console.warn(`Unable to resolve the required Expo splash background resource: ${String(error)}`);
  }

  try {
    const value: string = manager.getStringByNameSync('expo_splash_screen_resize_mode');
    if (value === 'contain' || value === 'cover' || value === 'native') resize = value;
    else console.warn(`Ignoring invalid Expo splash resize mode '${value}'.`);
  } catch (error) {
    console.warn(`Using the default Expo splash resize mode: ${String(error)}`);
  }

  try {
    width = Number(manager.getStringByNameSync('expo_splash_screen_image_width'));
  } catch (error) {
    console.warn(`Using the default Expo splash image width: ${String(error)}`);
  }

  try {
    image = manager.getDrawableDescriptorByName('expo_splash_screen');
  } catch (error) {
    console.warn(`Expo splash image is unavailable; rendering the configured background only: ${String(error)}`);
  }

  if (!Number.isFinite(width) || width <= 0) width = DEFAULT_IMAGE_WIDTH;

  return new SplashScreenResources(background, image, resize, width, valid);
}
