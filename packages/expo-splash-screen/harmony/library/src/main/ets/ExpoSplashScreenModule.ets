import { window } from '@kit.ArkUI';
import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';

import {
  bindSplashScreenRuntime,
  destroySplashScreenAbility,
  endSplashScreenRuntime,
  ExpoSplashScreenError,
  findSplashScreenRuntime,
  prepareSplashScreenRuntimeReload,
  SplashScreenRuntimeOwner,
  ExpoSplashScreenLifecycle,
} from './SplashScreenLifecycle';

class SplashScreenOptions {
  duration: number = 400;
  fade: boolean = true;
}

const SPLASH_SCREEN_OPTIONS_TYPE: ExpoValueType<SplashScreenOptions> = new ExpoValueType<SplashScreenOptions>(
  'splash screen options object',
  (value: ESObject, path: string): SplashScreenOptions => decodeOptions(value, path),
  (value: SplashScreenOptions): ESObject => encodeOptions(value),
);

export class ExpoSplashScreenModule extends ExpoModule {
  private owner?: SplashScreenRuntimeOwner = undefined;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoSplashScreen')
      .syncFunction(
        'setOptions',
        ExpoFunction.typed1(SPLASH_SCREEN_OPTIONS_TYPE.nullable().optional(), (options?: SplashScreenOptions | null): void => {
          const settings: SplashScreenOptions = options ?? new SplashScreenOptions();
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
      .onWindowStageSetup((_stage: window.WindowStage): void => {
        this.setupWindow();
      })
      .onContentAppeared((): void => this.contentAppeared())
      .onPrepareForReload(async (): Promise<void> => {
        if (!this.destroyed) prepareSplashScreenRuntimeReload(this.context.runtimeEpoch);
      })
      .onWindowStageWillDestroy((): void => this.destroyAbility())
      .onAbilityDestroy((): void => this.destroyAbility())
      .onDestroy((): void => this.destroy());
  }

  private contentAppeared(): void {
    if (!this.destroyed) this.resolveOwner()?.contentAppeared();
  }

  private initialize(): void {
    this.owner = bindSplashScreenRuntime(this.context.uiAbilityContext, this.context.runtimeEpoch);
  }

  private setupWindow(): void {
    if (this.destroyed) return;

    ExpoSplashScreenLifecycle.onWindowStageSetup(this.context.uiAbilityContext);
    this.owner = bindSplashScreenRuntime(this.context.uiAbilityContext, this.context.runtimeEpoch);
  }

  private resolveOwner(): SplashScreenRuntimeOwner | undefined {
    if (this.destroyed) return undefined;
    return this.owner ?? findSplashScreenRuntime(this.context.runtimeEpoch);
  }

  private destroyAbility(): void {
    if (this.destroyed) return;

    destroySplashScreenAbility(this.context.uiAbilityContext);
    this.owner = undefined;
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    endSplashScreenRuntime(this.context.runtimeEpoch);
    this.owner = undefined;
  }
}

function decodeOptions(value: ESObject, path: string): SplashScreenOptions {
  if (!isRecord(value)) {
    throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', `${path} expected a splash screen options object.`);
  }

  const input = value as Record<string, ESObject>;
  const duration: ESObject = input['duration'];
  const fade: ESObject = input['fade'];

  if (duration !== undefined && duration !== null) {
    if (typeof duration !== 'number' || !Number.isFinite(duration) || duration < 0) {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', `${path}.duration expected a non-negative finite number.`);
    }
  }
  if (fade !== undefined && fade !== null) {
    if (typeof fade !== 'boolean') {
      throw new ExpoSplashScreenError('ERR_SPLASH_SCREEN_OPTIONS', `${path}.fade expected a boolean.`);
    }
  }

  const options = new SplashScreenOptions();
  if (duration !== undefined && duration !== null) options.duration = duration;
  if (fade !== undefined && fade !== null) options.fade = fade;

  return options;
}

function encodeOptions(value: SplashScreenOptions): ESObject {
  return {
    duration: value.duration,
    fade: value.fade,
  };
}

function isRecord(value: ESObject): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
