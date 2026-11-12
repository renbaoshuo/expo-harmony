/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { adaptRnohWindow } from './RnohWindow';
import { RNAbility, RNOHCoreContext, RNOHLogger } from '@rnoh/react-native-openharmony';
import { RnohPackagerClient, RnohContextLifecycle } from '@expo-harmony/expo-modules-core';
import { redactRnohWantLogs } from './RnohWantLogs';

export abstract class RnohAbility extends RNAbility {
  private core?: RNOHCoreContext;
  private client?: RnohPackagerClient;
  private lifetime?: RnohContextLifecycle;
  private destruction?: Promise<void>;
  private readonly windows = new Map<window.Window, () => void>();

  protected override createLogger(): RNOHLogger {
    return redactRnohWantLogs(super.createLogger());
  }

  override onCreate(want: Want, launch?: AbilityConstant.LaunchParam): void {
    if (this.core !== undefined || this.destruction !== undefined) throw new Error('The RNOH ability has already been created or destroyed.');

    const previous = AppStorage.get<RNOHCoreContext>('RNOHCoreContext');
    const client = new RnohPackagerClient();

    try {
      super.onCreate(want, launch);
      const core = AppStorage.get<RNOHCoreContext>('RNOHCoreContext');
      // A cached coordinator does not publish a new client.
      if (core === undefined || core.uiAbilityContext !== this.context || client.isCurrent()) {
        throw new Error('The RNOH coordinator is already owned by another ability.');
      }

      this.core = core;
      this.client = new RnohPackagerClient();
      this.lifetime = RnohContextLifecycle.install(core);
    } catch (error) {
      if (this.core === undefined) {
        if (previous === undefined) AppStorage.delete('RNOHCoreContext');
        else AppStorage.setOrCreate('RNOHCoreContext', previous);
        client.restore();
      }
      throw new Error(`Unable to create the RNOH ability: ${String(error)}`);
    }
  }

  override onDestroy(): void {
    if (this.destruction !== undefined) return;
    this.destruction = this.destroyContext();
    this.destruction.catch((error: Error): void => console.error(`Unable to destroy the RNOH context: ${String(error)}`));
  }

  private async destroyContext(): Promise<void> {
    const core = this.core;
    if (core === undefined) return;

    try {
      await this.lifetime?.destroy();
    } finally {
      for (const restore of this.windows.values()) {
        try {
          restore();
        } catch (error) {
          console.error(`Unable to restore an RNOH window listener: ${String(error)}`);
        }
      }
      this.windows.clear();
      try {
        this.client?.destroy((): void => super.onDestroy());
      } finally {
        if (AppStorage.get<RNOHCoreContext>('RNOHCoreContext') === core) AppStorage.delete('RNOHCoreContext');
        this.client = undefined;
        this.core = undefined;
        this.onRNOHDestroyed();
      }
    }
  }

  protected activate(): boolean {
    if (this.core === undefined || this.destruction !== undefined) return false;

    AppStorage.setOrCreate('RNOHCoreContext', this.core);
    this.client?.restore();

    return true;
  }

  override onForeground(): void {
    if (this.activate()) super.onForeground();
  }

  override onWindowStageCreate(stage: window.WindowStage): void {
    if (this.activate()) super.onWindowStageCreate(stage);
  }

  protected override async onWindowSetup(view: window.Window): Promise<void> {
    if (!this.windows.has(view))
      this.windows.set(
        view,
        adaptRnohWindow(view, (): boolean => this.destruction !== undefined),
      );
    await super.onWindowSetup(view);
  }

  protected onRNOHDestroyed(): void {}

  override onNewWant(want: Want, launch: AbilityConstant.LaunchParam): void {
    if (!this.activate()) return;

    // RNOH emits a Linking event even when the Want has no URI.
    if (want.uri !== undefined && want.uri.length > 0) super.onNewWant(want, launch);
  }

  protected override async onPrepareRNInstance(context: RNOHCoreContext): Promise<void> {
    if (context !== this.core) throw new Error('The RNOH context belongs to another ability.');

    // RNOH 0.86.1 forwards the initial Want URI to RNInstanceRegistry itself.
    await super.onPrepareRNInstance(context);
  }

  override onWindowStageRestore(stage: window.WindowStage): void {
    if (!this.activate()) return;
    super.onWindowStageRestore(stage);
    // RNAbility only sets up a window on onWindowStageCreate.
    super.onWindowStageCreate(stage);
  }

  override onWillForeground(): void {
    super.onWillForeground?.();
  }
  override onDidForeground(): void {
    super.onDidForeground?.();
  }
  override onWillBackground(): void {
    super.onWillBackground?.();
  }
  override onDidBackground(): void {
    super.onDidBackground?.();
  }
  override onBackPressed(): boolean {
    return super.onBackPressed?.() ?? false;
  }
}
