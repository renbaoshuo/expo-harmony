import { common } from '@kit.AbilityKit';
import window from '@ohos.window';
import {
  ExpoAbilityLifecycleSubscriber,
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
  private foreground: boolean = false;
  private generation: number = 0;
  private activated: boolean = false;
  private known: boolean = false;
  private pending: Promise<void> = Promise.resolve();
  private resolver: WindowResolver | null = null;
  private destroyed: boolean = false;

  retain(owner: string): void {
    if (!this.owners.has(owner)) this.owners.set(owner, new Set<string>());
  }

  async activate(owner: string, tag: string): Promise<void> {
    await this.mutateTag(owner, tag, true);
  }

  async deactivate(owner: string, tag: string): Promise<void> {
    await this.mutateTag(owner, tag, false);
  }

  hasTags(owner: string): boolean {
    return (this.owners.get(owner)?.size ?? 0) > 0;
  }

  setForeground(foreground: boolean): void {
    if (this.destroyed) return;

    this.foreground = foreground;
    this.refresh();
  }

  setStage(stage: window.WindowStage): void {
    this.windowWillDestroy();
    this.resolver = (): Promise<window.Window> => stage.getMainWindow();
  }

  async prepareWindow(): Promise<void> {
    await this.serialize(async (): Promise<void> => this.applyDesiredState(true));
  }

  private refresh(): void {
    this.prepareWindow().catch((error: Object): void => {
      if (!this.destroyed) console.warn(`Unable to reconcile Expo KeepAwake: ${String(error)}`);
    });
  }

  windowWillDestroy(): void {
    this.generation += 1;
    this.resolver = null;
    this.window = null;
    this.known = false;
    this.activated = false;
  }

  async release(owner: string): Promise<void> {
    if (!this.owners.has(owner)) return;

    await this.serialize(async (): Promise<void> => {
      this.owners.delete(owner);
      await this.applyDesiredState(true);
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
    this.known = false;
    this.activated = false;

    if (target !== null) {
      try {
        await withTimeout(target.setWindowKeepScreenOn(false), 'release keep-screen-on');
      } catch (error) {
        console.warn(`Unable to release Expo KeepAwake during Ability teardown: ${String(error)}`);
      }
    }
  }

  private async mutateTag(owner: string, tag: string, adding: boolean): Promise<void> {
    await this.serialize(async (): Promise<void> => {
      this.assertActive();

      const tags: Set<string> = this.owners.get(owner) ?? new Set<string>();

      this.owners.set(owner, tags);

      const contained: boolean = tags.has(tag);

      if (adding) tags.add(tag);
      else tags.delete(tag);

      try {
        await this.applyDesiredState(true);
      } catch (error) {
        if (contained) tags.add(tag);
        else tags.delete(tag);

        try {
          await this.applyDesiredState(false);
        } catch (_) {
          this.known = false;
        }

        throw new ExpoKeepAwakeError(ERROR_WINDOW, `Unable to update the Harmony keep-screen-on state: ${String(error)}`);
      }
    });
  }

  private async applyDesiredState(reconcile: boolean): Promise<void> {
    if (this.destroyed) return;

    const generation = this.generation;
    let desired: boolean = this.foreground && this.hasAnyTags();
    let target: window.Window | null = this.window;

    if (desired) {
      const resolver: WindowResolver | null = this.resolver;
      if (resolver === null) return;

      target = await resolver();
      if (this.destroyed || generation !== this.generation) return;

      desired = this.foreground && this.hasAnyTags();
    }

    if (target === null) {
      this.activated = false;
      this.known = true;

      return;
    }

    const id: number = target.getWindowProperties().id;
    const current: number | null = this.window === null ? null : this.window.getWindowProperties().id;

    if (desired && this.window !== null && current !== id && this.activated) {
      await this.applyWindowValue(this.window, false, reconcile);
      if (this.destroyed || generation !== this.generation) return;

      desired = this.foreground && this.hasAnyTags();
      this.window = null;
      this.known = false;
    }

    if (this.known && this.activated === desired && (!desired || current === id)) {
      return;
    }

    await this.applyWindowValue(target, desired, reconcile);
    if (this.destroyed || generation !== this.generation) return;

    this.activated = desired;
    this.known = true;
    this.window = desired ? target : null;
  }

  private async applyWindowValue(target: window.Window, value: boolean, reconcile: boolean): Promise<void> {
    const generation = this.generation;
    const operation: Promise<void> = target.setWindowKeepScreenOn(value);
    let expired: boolean = false;

    try {
      await withTimeout(operation, `set keep-screen-on to ${String(value)}`, (): void => {
        expired = true;
      });
    } catch (error) {
      this.known = false;
      if (expired && reconcile) {
        const settled = (): void => {
          if (generation === this.generation) this.reconcileWindow(target);
        };
        operation.then(settled, settled);
      }

      throw new ExpoKeepAwakeError(ERROR_WINDOW, `Unable to set keep-screen-on to ${String(value)}: ${String(error)}`);
    }
  }

  private reconcileWindow(target: window.Window): void {
    if (this.destroyed) return;

    const generation = this.generation;

    this.serialize(async (): Promise<void> => {
      if (this.destroyed || generation !== this.generation) return;

      this.known = false;
      if (this.foreground && this.hasAnyTags()) {
        await this.applyDesiredState(false);
      } else {
        await this.applyWindowValue(target, false, false);
        if (this.destroyed || generation !== this.generation) return;

        this.window = null;
        this.activated = false;
        this.known = true;
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

export class ExpoKeepAwakeLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  private readonly controller: AbilityKeepAwakeController = new AbilityKeepAwakeController();

  constructor(context: common.UIAbilityContext) {
    super(context);
    controllers.set(context, this.controller);
  }

  override onForeground(): void {
    this.controller.setForeground(true);
  }
  override onBackground(): void {
    this.controller.setForeground(false);
  }
  override onWindowStageCreate(stage: window.WindowStage): void {
    this.controller.setStage(stage);
  }
  override onWindowStageRestore(stage: window.WindowStage): void {
    this.controller.setStage(stage);
  }
  override async onWindowStageSetup(): Promise<void> {
    await this.controller.prepareWindow();
  }
  override onWindowStageWillDestroy(): void {
    this.controller.windowWillDestroy();
  }
  override onWindowStageDestroy(): void {
    this.controller.windowWillDestroy();
  }
  override onDestroy(): void {
    controllers.delete(this.context);
    this.controller.destroy().catch((error: Object): void => console.warn(`Unable to destroy Expo KeepAwake: ${String(error)}`));
  }
}

export class ExpoKeepAwakeModule extends ExpoModule {
  private readonly controller?: AbilityKeepAwakeController;
  private readonly owner: string;
  private released: boolean = false;
  private destroyed: boolean = false;

  constructor(context: ExpoModuleContext) {
    super(context);

    const controller = controllers.get(context.uiAbilityContext);
    if (controller === undefined && !context.isHeadless)
      throw new ExpoKeepAwakeError(ERROR_DESTROYED, 'Expo KeepAwake requires its autolinked Ability lifecycle subscriber.');

    this.controller = controller;
    this.owner = context.runtimeEpoch;
    this.controller?.retain(this.owner);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoKeepAwake')
      .asyncFunction(
        'activate',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (tag: string): Promise<void> => {
          this.assertActive();
          await this.controller?.activate(this.owner, tag);
        }),
      )
      .asyncFunction(
        'deactivate',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (tag: string): Promise<void> => {
          this.assertActive();
          await this.controller?.deactivate(this.owner, tag);
        }),
      )
      .asyncFunction('isActivated', async (): Promise<boolean> => {
        if (this.context.isHeadless) return false;
        this.assertActive();
        return this.controller?.hasTags(this.owner) ?? false;
      })
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => !this.context.isHeadless)
      .onPrepareForReload(async (): Promise<void> => this.release())
      .onDestroy((): void => {
        this.destroyed = true;
        this.release().catch((): void => {});
      });
  }

  private async release(): Promise<void> {
    if (this.released) return;

    this.released = true;
    await this.controller?.release(this.owner);
  }

  private assertActive(): void {
    if (this.context.isHeadless) throw new ExpoKeepAwakeError(ERROR_WINDOW, 'KeepAwake requires a foreground UIAbility window.');

    if (this.destroyed || this.released || !this.context.isValid) {
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
