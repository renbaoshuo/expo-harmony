/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import {
  ExpoAbilityLifecycleSubscriber,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
  ExpoWindowKeepAwake,
} from '@expo-harmony/expo-modules-core';

const ERROR_DESTROYED: string = 'ERR_KEEP_AWAKE_DESTROYED';
const ERROR_WINDOW: string = 'ERR_KEEP_AWAKE_WINDOW';

class KeepAwakeOwner {
  readonly context: ExpoModuleContext;
  readonly tags: Set<string> = new Set<string>();
  windowId?: number;
  released: boolean = false;

  constructor(context: ExpoModuleContext) {
    this.context = context;
  }

  assertActive(): void {
    if (this.released || !this.context.isValid) {
      throw new ExpoModuleError(ERROR_DESTROYED, 'The Expo KeepAwake runtime has already been destroyed.');
    }
  }
}

class AbilityKeepAwakeController {
  private readonly owners: Set<KeepAwakeOwner> = new Set<KeepAwakeOwner>();
  private readonly windows: Map<number, window.Window> = new Map<number, window.Window>();
  private stage?: window.WindowStage;
  private foreground: boolean = false;
  private generation: number = 0;
  private pending: Promise<void> = Promise.resolve();
  private destroyed: boolean = false;

  retain(owner: KeepAwakeOwner): void {
    this.owners.add(owner);
  }

  activate(owner: KeepAwakeOwner, tag: string): Promise<void> {
    return this.serialize(async (): Promise<void> => {
      try {
        await this.bindWindow(owner, tag);
      } finally {
        // After a failed bind or a handoff, only windows with live owners may stay awake.
        await this.releaseUnusedWindows();
      }
    });
  }

  deactivate(owner: KeepAwakeOwner, tag: string): Promise<void> {
    return this.serialize(async (): Promise<void> => {
      this.assertActive();
      owner.assertActive();

      const id: number | undefined = owner.windowId;
      const removed: boolean = owner.tags.delete(tag);

      try {
        await this.releaseUnusedWindows(removed && id !== undefined && !this.hasWindowTags(id) ? id : undefined);
      } catch (error) {
        if (!owner.released && owner.context.isValid) owner.tags.add(tag);
        this.refresh();

        throw error as ExpoModuleError;
      }
    });
  }

  async isActivated(owner: KeepAwakeOwner): Promise<boolean> {
    await this.pending;
    this.assertActive();
    owner.assertActive();
    return owner.tags.size > 0;
  }

  release(owner: KeepAwakeOwner): Promise<void> {
    owner.released = true;
    return this.serialize(async (): Promise<void> => {
      this.owners.delete(owner);
      owner.tags.clear();
      await this.releaseUnusedWindows();
    });
  }

  setForeground(foreground: boolean): void {
    if (this.destroyed) return;

    this.foreground = foreground;
    this.refresh();
  }

  setStage(stage: window.WindowStage): void {
    if (this.destroyed) return;

    this.stage = stage;
    this.generation += 1;
  }

  windowWillDestroy(stage?: window.WindowStage): void {
    if (this.stage === undefined || (stage !== undefined && this.stage !== stage)) return;

    this.stage = undefined;
    this.generation += 1;
    for (const owner of this.owners) owner.windowId = undefined;

    this.refresh();
  }

  destroy(): void {
    this.destroyed = true;
    this.stage = undefined;
    this.generation += 1;
    for (const owner of this.owners) {
      owner.released = true;
      owner.tags.clear();
    }

    this.owners.clear();
    this.refresh();
  }

  refresh(): Promise<void> {
    return this.serialize(async (): Promise<void> => {
      if (this.foreground && this.stage !== undefined) {
        for (const owner of this.owners) {
          if (owner.tags.size === 0 || owner.released || !owner.context.isValid) continue;

          try {
            await this.bindWindow(owner);
          } catch (error) {
            console.warn(`Unable to reconcile Expo KeepAwake: ${String(error)}`);
          }
        }
      }
      await this.releaseUnusedWindows();
    });
  }

  private async bindWindow(owner: KeepAwakeOwner, tag?: string): Promise<void> {
    const generation: number = this.generation;
    this.assertStage(generation);
    owner.assertActive();

    let target: window.Window;

    try {
      target = await owner.context.getReactNativeWindow();
    } catch (error) {
      owner.assertActive();
      throw new ExpoModuleError(ERROR_WINDOW, `Unable to find the React Native window: ${String(error)}`);
    }

    this.assertStage(generation);
    owner.assertActive();

    let id: number;

    try {
      id = target.getWindowProperties().id;
      if (this.foreground) {
        // A write can fail or finish after the runtime or stage changes. Keep its cleanup target.
        this.windows.set(id, target);
        await ExpoWindowKeepAwake.acquire(target, this);
      }
    } catch (error) {
      throw new ExpoModuleError(ERROR_WINDOW, `Unable to enable keep-screen-on: ${String(error)}`);
    }

    this.assertStage(generation);
    owner.assertActive();

    owner.windowId = id;
    if (tag !== undefined) owner.tags.add(tag);
  }

  private async releaseUnusedWindows(strictWindowId?: number): Promise<void> {
    for (const entry of this.windows.entries()) {
      const id: number = entry[0];
      if (this.foreground && this.stage !== undefined && this.hasWindowTags(id)) continue;

      try {
        await ExpoWindowKeepAwake.release(entry[1], this);
        this.windows.delete(id);
      } catch (error) {
        const message: string = `Unable to release Expo KeepAwake window: ${String(error)}`;
        if (id === strictWindowId) throw new ExpoModuleError(ERROR_WINDOW, message);

        console.warn(message);
      }
    }
  }

  private hasWindowTags(id: number): boolean {
    for (const owner of this.owners) {
      if (owner.windowId === id && owner.tags.size > 0 && !owner.released && owner.context.isValid) return true;
    }
    return false;
  }

  private serialize(task: () => Promise<void>): Promise<void> {
    const next: Promise<void> = this.pending.then(task);
    this.pending = next.catch((): void => {});
    return next;
  }

  private assertActive(): void {
    if (this.destroyed) {
      throw new ExpoModuleError(ERROR_DESTROYED, 'The Expo KeepAwake Ability has already been destroyed.');
    }
  }

  private assertStage(generation: number): void {
    this.assertActive();
    if (this.stage === undefined || this.generation !== generation) {
      throw new ExpoModuleError(ERROR_WINDOW, 'The UIAbility window stage is unavailable or has changed.');
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
    await this.controller.refresh();
  }

  override onWindowStageWillDestroy(stage?: window.WindowStage): void {
    this.controller.windowWillDestroy(stage);
  }

  override onWindowStageDestroy(): void {
    this.controller.windowWillDestroy();
  }

  override onDestroy(): void {
    controllers.delete(this.context);
    this.controller.destroy();
  }
}

export class ExpoKeepAwakeModule extends ExpoModule {
  private readonly controller?: AbilityKeepAwakeController;
  private readonly owner: KeepAwakeOwner;

  constructor(context: ExpoModuleContext) {
    super(context);

    if (!context.isHeadless) {
      this.controller = controllers.get(context.uiAbilityContext);
      if (this.controller === undefined) {
        throw new ExpoModuleError(ERROR_DESTROYED, 'Expo KeepAwake requires its autolinked Ability lifecycle subscriber.');
      }
    }

    this.owner = new KeepAwakeOwner(context);
    this.controller?.retain(this.owner);
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoKeepAwake')
      .asyncFunction(
        'activate',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (tag: string): Promise<void> => {
          await this.requireController().activate(this.owner, tag);
        }),
      )
      .asyncFunction(
        'deactivate',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (tag: string): Promise<void> => {
          await this.requireController().deactivate(this.owner, tag);
        }),
      )
      .asyncFunction('isActivated', async (): Promise<boolean> => this.controller?.isActivated(this.owner) ?? false)
      .asyncFunction('isAvailableAsync', async (): Promise<boolean> => !this.context.isHeadless)
      .onContentAppeared((): void => {
        this.controller?.refresh();
      })
      .onPrepareForReload(async (): Promise<void> => this.controller?.release(this.owner))
      .onDestroy((): void => {
        this.controller?.release(this.owner);
      });
  }

  private requireController(): AbilityKeepAwakeController {
    const controller: AbilityKeepAwakeController | undefined = this.controller;
    if (controller === undefined) {
      throw new ExpoModuleError(ERROR_WINDOW, 'KeepAwake requires a UIAbility window.');
    }
    return controller;
  }
}
