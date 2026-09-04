import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

const TIMEOUT_MS: number = 5000;
const ERROR_DESTROYED: string = 'ERR_KEEP_AWAKE_DESTROYED';
const ERROR_WINDOW: string = 'ERR_KEEP_AWAKE_WINDOW';

type WindowResolver = () => Promise<window.Window>;

class ExpoKeepAwakeError extends ExpoModuleError {
  constructor(code: string, message: string) {
    super(code, message);
    this.name = 'ExpoKeepAwakeError';
  }
}

class AbilityKeepAwakeController {
  private readonly owners: Map<string, Set<string>> = new Map<string, Set<string>>();
  private window: window.Window | null = null;
  private foreground: boolean;
  private activated: boolean = false;
  private stateKnown: boolean = false;
  private pending: Promise<void> = Promise.resolve();
  private resolver: WindowResolver | null = null;
  private destroyed: boolean = false;

  constructor(foreground: boolean) {
    this.foreground = foreground;
  }

  retain(owner: string): void {
    if (!this.owners.has(owner)) this.owners.set(owner, new Set<string>());
  }

  async activate(owner: string, tag: string, resolve: WindowResolver): Promise<void> {
    await this.mutateTag(owner, tag, true, resolve);
  }

  async deactivate(owner: string, tag: string, resolve: WindowResolver): Promise<void> {
    await this.mutateTag(owner, tag, false, resolve);
  }

  hasTags(owner: string): boolean {
    return (this.owners.get(owner)?.size ?? 0) > 0;
  }

  setForeground(foreground: boolean, resolve: WindowResolver): void {
    if (this.destroyed) return;

    this.resolver = resolve;
    this.serialize(async (): Promise<void> => {
      this.foreground = foreground;
      await this.applyDesiredState(resolve, true);
    }).catch((error: Object): void => {
      if (!this.destroyed) {
        console.warn(`Unable to reconcile Expo KeepAwake after a lifecycle change: ${String(error)}`);
      }
    });
  }

  setWindow(target: window.Window): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      await this.applyDesiredState(async (): Promise<window.Window> => target, true);
    }).catch((error: Object): void => {
      if (!this.destroyed) {
        console.warn(`Unable to reconcile Expo KeepAwake for a new window: ${String(error)}`);
      }
    });
  }

  windowWillDestroy(): void {
    this.window = null;
    this.stateKnown = false;
    this.activated = false;
  }

  async release(owner: string): Promise<void> {
    if (!this.owners.has(owner)) return;

    await this.serialize(async (): Promise<void> => {
      this.owners.delete(owner);
      await this.applyDesiredState(null, true);
    });
  }

  async destroy(): Promise<void> {
    if (this.destroyed) return;

    this.destroyed = true;
    this.foreground = false;
    this.owners.clear();
    this.resolver = null;

    const target: window.Window | null = this.window;
    this.window = null;
    this.stateKnown = false;
    this.activated = false;

    if (target !== null) {
      try {
        await withTimeout(target.setWindowKeepScreenOn(false), 'release keep-screen-on');
      } catch (error) {
        console.warn(`Unable to release Expo KeepAwake during Ability teardown: ${String(error)}`);
      }
    }
  }

  private async mutateTag(owner: string, tag: string, adding: boolean, resolve: WindowResolver): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      this.assertActive();

      this.resolver = resolve;
      const tags: Set<string> = this.owners.get(owner) ?? new Set<string>();
      this.owners.set(owner, tags);
      const contained: boolean = tags.has(tag);

      if (adding) tags.add(tag);
      else tags.delete(tag);

      try {
        await this.applyDesiredState(resolve, true);
      } catch (error) {
        if (contained) tags.add(tag);
        else tags.delete(tag);

        try {
          await this.applyDesiredState(null, false);
        } catch (_) {
          this.stateKnown = false;
        }

        throw new ExpoKeepAwakeError(ERROR_WINDOW, `Unable to update the Harmony keep-screen-on state: ${String(error)}`);
      }
    });
  }

  private async applyDesiredState(resolve: WindowResolver | null, reconcile: boolean): Promise<void> {
    if (this.destroyed) return;

    const desired: boolean = this.foreground && this.hasAnyTags();
    let target: window.Window | null = this.window;

    if (desired) {
      const resolver: WindowResolver | null = resolve ?? this.resolver;
      if (resolver === null) {
        throw new ExpoKeepAwakeError(ERROR_WINDOW, 'No React Native window is available for Expo KeepAwake.');
      }

      target = await resolver();
      if (this.destroyed) return;
    }

    if (target === null) {
      this.activated = false;
      this.stateKnown = true;
      return;
    }

    const id: number = target.getWindowProperties().id;
    const activeId: number | null = this.window === null ? null : this.window.getWindowProperties().id;

    if (desired && this.window !== null && activeId !== id && this.activated) {
      await this.applyWindowValue(this.window, false, reconcile);
      this.window = null;
      this.stateKnown = false;
    }

    if (this.stateKnown && this.activated === desired && (!desired || activeId === id)) {
      return;
    }

    await this.applyWindowValue(target, desired, reconcile);
    if (this.destroyed) return;

    this.activated = desired;
    this.stateKnown = true;
    this.window = desired ? target : null;
  }

  private async applyWindowValue(target: window.Window, value: boolean, reconcile: boolean): Promise<void> {
    const operation: Promise<void> = target.setWindowKeepScreenOn(value);
    let timedOut: boolean = false;

    try {
      await withTimeout(operation, `set keep-screen-on to ${String(value)}`, (): void => {
        timedOut = true;
      });
    } catch (error) {
      this.stateKnown = false;
      if (timedOut && reconcile) {
        const settled = (): void => this.reconcileWindow(target);
        operation.then(settled, settled);
      }

      throw new ExpoKeepAwakeError(ERROR_WINDOW, `Unable to set keep-screen-on to ${String(value)}: ${String(error)}`);
    }
  }

  private reconcileWindow(target: window.Window): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      this.stateKnown = false;
      if (this.foreground && this.hasAnyTags()) {
        await this.applyDesiredState(null, false);
      } else {
        await this.applyWindowValue(target, false, false);
        this.window = null;
        this.activated = false;
        this.stateKnown = true;
      }
    }).catch((error: Object): void => {
      if (!this.destroyed) {
        console.warn(`Unable to reconcile a late Expo KeepAwake window operation: ${String(error)}`);
      }
    });
  }

  private hasAnyTags(): boolean {
    for (const tags of this.owners.values()) {
      if (tags.size > 0) return true;
    }
    return false;
  }

  private async serialize(task: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.pending.catch((): void => {}).then(task);
    this.pending = next;
    await next;
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoKeepAwakeError(ERROR_DESTROYED, 'The Expo KeepAwake Ability has already been destroyed.');
    }
  }
}

const controllers: WeakMap<common.UIAbilityContext, AbilityKeepAwakeController> = new WeakMap<common.UIAbilityContext, AbilityKeepAwakeController>();

function controllerFor(context: ExpoModuleContext): AbilityKeepAwakeController {
  const ability: common.UIAbilityContext = context.uiAbilityContext;
  let controller: AbilityKeepAwakeController | undefined = controllers.get(ability);

  if (controller === undefined) {
    controller = new AbilityKeepAwakeController(context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND);
    controllers.set(ability, controller);
  }

  return controller;
}

export class ExpoKeepAwakeModule extends ExpoModule {
  private readonly controller: AbilityKeepAwakeController;
  private readonly owner: string;
  private released: boolean = false;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.controller = controllerFor(context);
    this.owner = context.runtimeEpoch;
    this.controller.retain(this.owner);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoKeepAwake')
      .asyncFunction(
        'activate',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (tag: string): Promise<void> => {
          this.assertActive();
          await this.controller.activate(this.owner, tag, this.resolveWindow());
        }),
      )
      .asyncFunction(
        'deactivate',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (tag: string): Promise<void> => {
          this.assertActive();
          await this.controller.deactivate(this.owner, tag, this.resolveWindow());
        }),
      )
      .asyncFunction('isActivated', async (): Promise<boolean> => {
        this.assertActive();
        return this.controller.hasTags(this.owner);
      })
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => true)
      .onForeground((): void => this.controller.setForeground(true, this.resolveWindow()))
      .onBackground((): void => this.controller.setForeground(false, this.resolveWindow()))
      .onWindowStageSetup((stage: window.WindowStage): void => {
        stage
          .getMainWindow()
          .then((target: window.Window): void => this.controller.setWindow(target))
          .catch((error: Object): void => {
            if (!this.destroyed) {
              this.context.logger.warn(`Unable to locate the Expo KeepAwake main window: ${String(error)}`);
            }
          });
      })
      .onWindowStageWillDestroy((): void => this.controller.windowWillDestroy())
      .onPrepareForReload(async (): Promise<void> => this.release())
      .onAbilityDestroy((): void => {
        this.destroyed = true;
        controllers.delete(this.context.uiAbilityContext);
        this.controller.destroy().catch((): void => {});
      })
      .onDestroy((): void => {
        this.destroyed = true;
        this.release().catch((): void => {});
      });
  }

  private resolveWindow(): WindowResolver {
    return (): Promise<window.Window> => this.context.getReactNativeWindow();
  }

  private async release(): Promise<void> {
    if (this.released) return;

    this.released = true;
    await this.controller.release(this.owner);
  }

  private assertActive(): void {
    if (this.destroyed || this.released) {
      throw new ExpoKeepAwakeError(ERROR_DESTROYED, 'The Expo KeepAwake runtime has already been destroyed.');
    }
  }
}

async function withTimeout<T>(operation: Promise<T>, description: string, onTimeout?: () => void): Promise<T> {
  let timer: number | undefined = undefined;

  try {
    return await Promise.race([
      operation,
      new Promise<T>((_, reject) => {
        timer = setTimeout((): void => {
          onTimeout?.();
          reject(new ExpoKeepAwakeError(ERROR_WINDOW, `Timed out after ${TIMEOUT_MS} ms while trying to ${description}.`));
        }, TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
