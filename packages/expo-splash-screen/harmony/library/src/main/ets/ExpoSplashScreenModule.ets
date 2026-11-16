/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

import {
  bindSplashScreenRuntime,
  DEFAULT_FADE_DURATION_MS,
  endSplashScreenRuntime,
  ExpoSplashScreenError,
  findSplashScreenRuntime,
  MAX_FADE_DURATION_MS,
  SplashScreenRuntimeOwner,
} from './SplashScreenLifecycle';

interface SplashScreenOptions {
  readonly duration: number;
  readonly fade: boolean;
}

const DEFAULT_OPTIONS: SplashScreenOptions = { duration: DEFAULT_FADE_DURATION_MS, fade: true };
const SPLASH_SCREEN_OPTIONS_TYPE: ExpoValueType<SplashScreenOptions> = new ExpoValueType<SplashScreenOptions>(
  'splash screen options object',
  (value: ESObject, path: string): SplashScreenOptions => decodeOptions(value, path),
  (value: SplashScreenOptions): SplashScreenOptions => value,
);

export class ExpoSplashScreenModule extends ExpoModule {
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return (
      new ExpoModuleDefinition()
        .name('ExpoSplashScreen')
        .syncFunction(
          'setOptions',
          ExpoFunction.typed1(SPLASH_SCREEN_OPTIONS_TYPE.nullable().optional(), (options?: SplashScreenOptions | null): void => {
            const settings: SplashScreenOptions = options ?? DEFAULT_OPTIONS;
            this.resolveOwner()?.setOptions(settings.duration, settings.fade);
          }),
        )
        .syncFunction('hide', (): void => {
          this.resolveOwner()?.hide();
        })
        .asyncFunction('hideAsync', async (): Promise<void> => {
          this.resolveOwner()?.hide();
        })
        .asyncFunction(
          'preventAutoHideAsync',
          ExpoFunction.typed0(async (): Promise<boolean> => {
            return this.resolveOwner()?.prevent(true) ?? true;
          }).returns(ExpoValueTypes.boolean()),
        )
        .asyncFunction('internalPreventAutoHideAsync', async (): Promise<void> => {
          this.resolveOwner()?.prevent(false);
        })
        .asyncFunction('internalMaybeHideAsync', async (): Promise<void> => {
          this.resolveOwner()?.internalMaybeHide();
        })
        .onCreate((): void => this.initialize())
        .onContentAppeared((): void => this.contentAppeared())
        // Core also invokes this hook when a runtime is suspended or destroyed.
        .onPrepareForReload(async (): Promise<void> => this.destroy())
        .onDestroy((): void => this.destroy())
    );
  }

  private contentAppeared(): void {
    if (!this.destroyed) this.resolveOwner()?.contentAppeared();
  }

  private initialize(): void {
    if (!this.destroyed && !this.context.isHeadless) bindSplashScreenRuntime(this.context.uiAbilityContext, this.context.runtimeEpoch);
  }

  private resolveOwner(): SplashScreenRuntimeOwner | undefined {
    if (this.destroyed) return undefined;
    return findSplashScreenRuntime(this.context.runtimeEpoch);
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    endSplashScreenRuntime(this.context.runtimeEpoch);
  }
}

function decodeOptions(value: ESObject, path: string): SplashScreenOptions {
  if (!isRecord(value)) {
    throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', `${path} expected a splash screen options object.`);
  }

  const input = value as Record<string, ESObject>;
  const duration: ESObject = input['duration'];
  const fade: ESObject = input['fade'];

  if (duration !== undefined && duration !== null && (
    typeof duration !== 'number' || !Number.isFinite(duration) || duration < 0 || duration > MAX_FADE_DURATION_MS
  )) {
    throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', `${path}.duration expected a number from 0 to ${MAX_FADE_DURATION_MS}.`);
  }
  if (fade !== undefined && fade !== null && typeof fade !== 'boolean') {
    throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', `${path}.fade expected a boolean.`);
  }

  return {
    duration: duration ?? DEFAULT_OPTIONS.duration,
    fade: fade ?? DEFAULT_OPTIONS.fade,
  };
}

function isRecord(value: ESObject): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
