/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { DrawableDescriptor, UIContext } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { ExpoAbilityLifecycleSubscriber, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import type { ReactActivityHandler, ReactRootViewContext } from '@expo-harmony/expo-modules-core';

import { SplashScreenStateMachine } from './SplashScreenStateMachine';

const DEFAULT_BACKGROUND: number = 0xffffffff;
const DEFAULT_IMAGE_WIDTH: number = 100;
const BACKGROUND_RESOURCE: string = 'expo_splash_screen_background';
const IMAGE_RESOURCE: string = 'expo_splash_screen';
const IMAGE_WIDTH_RESOURCE: string = 'expo_splash_screen_image_width';
const RESIZE_MODE_RESOURCE: string = 'expo_splash_screen_resize_mode';
const RESOURCE_NOT_FOUND: number = 9001004;
const FADE_WATCHDOG_GRACE_MS: number = 100;
const MAX_TIMER_DELAY_MS: number = 2147483647;
export const DEFAULT_FADE_DURATION_MS: number = 400;
export const MAX_FADE_DURATION_MS: number = MAX_TIMER_DELAY_MS - FADE_WATCHDOG_GRACE_MS;

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
    background: number,
    image: DrawableDescriptor | undefined,
    resize: SplashScreenResizeMode,
    width: number,
    opacity: number,
  ) {
    this.visible = visible;
    this.backgroundColor = background;
    this.image = image;
    this.resizeMode = resize;
    this.imageWidth = width;
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
}

class SplashScreenResources {
  readonly backgroundColor: number;
  readonly image: DrawableDescriptor | undefined;
  readonly resizeMode: SplashScreenResizeMode;
  readonly imageWidth: number;

  constructor(background: number, image: DrawableDescriptor | undefined, resize: SplashScreenResizeMode, width: number) {
    this.backgroundColor = background;
    this.image = image;
    this.resizeMode = resize;
    this.imageWidth = width;
  }
}

class SplashScreenAbilityOwner {
  private readonly ability: common.UIAbilityContext;
  private resources: SplashScreenResources | undefined;
  private readonly state: SplashScreenStateMachine = new SplashScreenStateMachine();
  private epoch: string | undefined = undefined;
  private listener: SplashScreenRenderListener | undefined = undefined;
  private ui: UIContext | undefined = undefined;
  private duration: number = DEFAULT_FADE_DURATION_MS;
  private fade: boolean = true;
  private opacity: number = 1;
  private generation: number = 0;
  private timer: number | undefined = undefined;
  private backgrounded: boolean = false;

  constructor(ability: common.UIAbilityContext) {
    this.ability = ability;
  }

  attachView(ui: UIContext, listener: SplashScreenRenderListener): () => void {
    const previous = this.listener;
    if (previous !== undefined) {
      this.detachView();
      previous(SplashScreenRenderState.hidden());
    }

    this.ui = ui;
    this.listener = listener;
    this.resources = resolveResources(this.ability.resourceManager);

    if (this.resources !== undefined) this.state.markNativeVisible();
    this.publish();

    return (): void => {
      if (this.listener === listener) this.detachView();
    };
  }

  detachView(): void {
    if (this.listener === undefined) return;

    this.generation += 1;
    this.clearTimer();
    this.opacity = 1;
    this.listener = undefined;
    this.ui = undefined;
    this.state.markNativeRemoved();
  }

  updateResources(): void {
    if (!this.state.isVisible()) return;

    const resources = resolveResources(this.ability.resourceManager);
    if (resources === undefined) return;

    this.resources = resources;
    this.publish();
  }

  beginRuntime(epoch: string): boolean {
    if (this.state.isDestroyed() || this.epoch !== undefined) return false;

    this.epoch = epoch;
    return true;
  }

  endRuntime(epoch: string): void {
    if (this.epoch !== epoch) return;

    this.epoch = undefined;
    this.state.hide();
    this.finishRemoval(this.generation);
  }

  get runtimeEpoch(): string | undefined {
    return this.epoch;
  }

  setOptions(duration: number, fade: boolean): void {
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

  hideForNativeRoot(): void {
    if (this.epoch === undefined) this.hide();
  }

  foreground(): void {
    this.backgrounded = false;
  }

  background(): void {
    this.backgrounded = true;
    if (!this.state.isHiding()) return;

    // Finish an in-flight exit before the window becomes inactive. Invalidate
    // its animation callback so it cannot remove a later runtime's splash.
    this.finishRemoval(this.generation);
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

    if (this.backgrounded || !this.fade || this.duration <= 0) {
      this.finishRemoval(generation);
      return;
    }

    const ui = this.ui;
    if (ui === undefined || this.listener === undefined) {
      this.finishRemoval(generation);
      return;
    }

    try {
      // Schedule first: animateTo may call onFinish synchronously when animations are disabled.
      this.timer = setTimeout((): void => this.finishRemoval(generation), Math.ceil(this.duration) + FADE_WATCHDOG_GRACE_MS);

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
    } catch (_) {
      this.finishRemoval(generation);
    }
  }

  private finishRemoval(generation: number): void {
    if (generation !== this.generation) return;

    this.generation += 1;
    this.clearTimer();
    this.state.markNativeRemoved();
    this.opacity = 1;

    this.publish();
  }

  private publish(): void {
    const listener = this.listener;
    if (listener === undefined) return;

    const resources = this.resources;
    if (resources === undefined || !this.state.isVisible() || this.state.isDestroyed()) {
      listener(SplashScreenRenderState.hidden());
      return;
    }

    listener(
      new SplashScreenRenderState(
        true,
        resources.backgroundColor,
        resources.image,
        resources.resizeMode,
        resources.imageWidth,
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

  static prepareAbility(ability: common.UIAbilityContext): void {
    if (SplashScreenCoordinator.abilities.has(ability)) return;

    const main = ability.currentHapModuleInfo?.mainElementName;
    if (main && ability.abilityInfo.name !== main) return;

    SplashScreenCoordinator.abilities.set(ability, new SplashScreenAbilityOwner(ability));
  }

  static attachView(ability: common.UIAbilityContext, ui: UIContext, listener: SplashScreenRenderListener): (() => void) | undefined {
    return SplashScreenCoordinator.abilities.get(ability)?.attachView(ui, listener);
  }

  static bindRuntimeForAbility(ability: common.UIAbilityContext, epoch: string): void {
    if (SplashScreenCoordinator.runtimes.has(epoch)) return;

    const owner = SplashScreenCoordinator.abilities.get(ability);
    if (owner?.beginRuntime(epoch)) SplashScreenCoordinator.runtimes.set(epoch, owner);
  }

  static findRuntime(epoch: string): SplashScreenAbilityOwner | undefined {
    return SplashScreenCoordinator.runtimes.get(epoch);
  }

  static endRuntime(epoch: string): void {
    const owner = SplashScreenCoordinator.runtimes.get(epoch);
    if (owner === undefined) return;

    SplashScreenCoordinator.runtimes.delete(epoch);
    owner.endRuntime(epoch);
  }

  static destroyAbility(ability: common.UIAbilityContext): void {
    const owner = SplashScreenCoordinator.abilities.get(ability);
    if (owner === undefined) return;

    const epoch = owner.runtimeEpoch;
    SplashScreenCoordinator.abilities.delete(ability);
    if (epoch !== undefined) SplashScreenCoordinator.runtimes.delete(epoch);
    owner.destroy();
  }

  static foregroundAbility(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.abilities.get(ability)?.foreground();
  }

  static backgroundAbility(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.abilities.get(ability)?.background();
  }

  static detachWindow(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.abilities.get(ability)?.detachView();
  }

  static updateResources(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.abilities.get(ability)?.updateResources();
  }

  static dismissForNativeRoot(ability: common.UIAbilityContext): void {
    SplashScreenCoordinator.abilities.get(ability)?.hideForNativeRoot();
  }
}

export class ExpoSplashScreenLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  override onCreate(): void {
    SplashScreenCoordinator.prepareAbility(this.context);
  }

  override onWindowStageCreate(): void {
    SplashScreenCoordinator.prepareAbility(this.context);
  }

  override onWindowStageRestore(): void {
    SplashScreenCoordinator.prepareAbility(this.context);
  }

  override onForeground(): void {
    SplashScreenCoordinator.foregroundAbility(this.context);
  }

  override onBackground(): void {
    SplashScreenCoordinator.backgroundAbility(this.context);
  }

  override onConfigurationUpdate(): void {
    SplashScreenCoordinator.updateResources(this.context);
  }

  override onWindowStageWillDestroy(): void {
    SplashScreenCoordinator.detachWindow(this.context);
  }

  override onWindowStageDestroy(): void {
    SplashScreenCoordinator.detachWindow(this.context);
  }

  override onDestroy(): void {
    SplashScreenCoordinator.destroyAbility(this.context);
  }
}

export class ExpoSplashScreenReactActivityHandler implements ReactActivityHandler {
  constructor(_context: common.Context) {}

  onRootViewMounted(context: ReactRootViewContext): void {
    // A native replacement root cannot emit React's content-appeared event.
    if (context.isCustomRoot && !context.ready) {
      SplashScreenCoordinator.dismissForNativeRoot(context.core.uiAbilityContext);
    }
  }
}

export function attachSplashScreenView(
  ability: common.UIAbilityContext,
  ui: UIContext,
  listener: SplashScreenRenderListener,
): (() => void) | undefined {
  return SplashScreenCoordinator.attachView(ability, ui, listener);
}

export function bindSplashScreenRuntime(ability: common.UIAbilityContext, epoch: string): void {
  SplashScreenCoordinator.bindRuntimeForAbility(ability, epoch);
}

export function findSplashScreenRuntime(epoch: string): SplashScreenRuntimeOwner | undefined {
  return SplashScreenCoordinator.findRuntime(epoch);
}

export function endSplashScreenRuntime(epoch: string): void {
  SplashScreenCoordinator.endRuntime(epoch);
}

function resolveResources(manager: resourceManager.ResourceManager): SplashScreenResources | undefined {
  let background: number = DEFAULT_BACKGROUND;
  let resize: SplashScreenResizeMode = 'contain';
  let width: number = DEFAULT_IMAGE_WIDTH;
  let image: DrawableDescriptor | undefined = undefined;

  try {
    background = manager.getColorByNameSync(BACKGROUND_RESOURCE);
  } catch (error) {
    if ((error as BusinessError).code !== RESOURCE_NOT_FOUND) {
      console.warn(`Unable to resolve the Expo splash background resource: ${String(error)}`);
    }
    return undefined;
  }

  try {
    const value = manager.getStringByNameSync(RESIZE_MODE_RESOURCE);
    if (value === 'contain' || value === 'cover' || value === 'native') resize = value;
    else console.warn(`Ignoring invalid Expo splash resize mode '${value}'.`);
  } catch (error) {
    console.warn(`Using the default Expo splash resize mode: ${String(error)}`);
  }

  try {
    width = Number(manager.getStringByNameSync(IMAGE_WIDTH_RESOURCE));
  } catch (error) {
    console.warn(`Using the default Expo splash image width: ${String(error)}`);
  }

  try {
    image = manager.getDrawableDescriptorByName(IMAGE_RESOURCE);
  } catch (error) {
    console.warn(`Expo splash image is unavailable; rendering the configured background only: ${String(error)}`);
  }

  if (!Number.isFinite(width) || width <= 0) width = DEFAULT_IMAGE_WIDTH;

  return new SplashScreenResources(background, image, resize, width);
}
