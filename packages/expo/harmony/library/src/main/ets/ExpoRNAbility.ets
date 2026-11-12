/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { Configuration, Want } from '@kit.AbilityKit';
import { AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { RnohAbility } from './adapter/RnohAbility';
import deviceInfo from '@ohos.deviceInfo';
import { ExpoReactHost } from './ExpoReactHost';
import type { ExpoHarmonyHostProvider } from './ExpoModulesPackage';
import {
  EXPO_LIFECYCLE_MEMORY_LEVEL,
  EXPO_LIFECYCLE_NEW_INTENT,
  EXPO_LIFECYCLE_WINDOW_STAGE_SETUP,
  EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY,
  copyWant,
} from '@expo-harmony/expo-modules-core';

export abstract class ExpoRNAbility extends RnohAbility {
  protected abstract getExpoHarmonyHostProvider(): ExpoHarmonyHostProvider;

  protected abstract getExpoHarmonyWorkerScriptUrl(): string;

  protected override getRNOHWorkerScriptUrl(): string {
    const script: string = this.getExpoHarmonyWorkerScriptUrl();
    if (script.length === 0) {
      throw new Error('ExpoRNAbility requires a non-empty RNOH worker script URL.');
    }

    return script;
  }

  override onCreate(want: Want, launch?: AbilityConstant.LaunchParam): void {
    const provider = this.getExpoHarmonyHostProvider();
    const routedWant = copyWant(want);

    provider.hostState.beginAbility(this.context, routedWant);
    try {
      provider.lifecycle.onCreate(this.context, routedWant, launch);
      super.onCreate(routedWant, launch);
      ExpoReactHost.attachAbility(this.context);
    } catch (error) {
      provider.lifecycle.onDestroy(this.context);
      try {
        provider.hostState.finishAbility(this.context);
      } finally {
        super.onDestroy();
      }

      throw new Error(`Unable to create the Expo ability: ${String(error)}`);
    }
  }

  override onShouldDisableCleaningRNInstances(): boolean {
    return ExpoReactHost.hasOtherOwner(this.context) || super.onShouldDisableCleaningRNInstances();
  }

  override onNewWant(want: Want, launch: AbilityConstant.LaunchParam): void {
    if (!this.activate()) return;

    const provider = this.getExpoHarmonyHostProvider();
    const routedWant = copyWant(want);
    provider.lifecycle.onNewWant(this.context, routedWant, launch);

    super.onNewWant(routedWant, launch);

    provider.hostState.dispatch(this.context, EXPO_LIFECYCLE_NEW_INTENT, routedWant);
  }

  protected override async onWindowSetup(target: window.Window): Promise<void> {
    await super.onWindowSetup(target);
    await this.getExpoHarmonyHostProvider().lifecycle.onWindowSetup(this.context, target);
  }

  protected override async onWindowStageSetup(stage: window.WindowStage): Promise<void> {
    const provider = this.getExpoHarmonyHostProvider();

    await provider.lifecycle.onWindowStageSetup(this.context, stage);
    if (!provider.lifecycle.isWindowStageActive(this.context, stage)) return;

    await super.onWindowStageSetup(stage);
    if (!provider.lifecycle.isWindowStageActive(this.context, stage)) return;

    provider.hostState.dispatch(this.context, EXPO_LIFECYCLE_WINDOW_STAGE_SETUP, stage);
  }

  override onWindowStageCreate(stage: window.WindowStage): void {
    this.getExpoHarmonyHostProvider().lifecycle.onWindowStageCreate(this.context, stage);
    super.onWindowStageCreate(stage);
  }

  override onWindowStageRestore(stage: window.WindowStage): void {
    this.getExpoHarmonyHostProvider().lifecycle.onWindowStageRestore(this.context, stage);
    super.onWindowStageRestore(stage);
  }

  override onWindowStageWillDestroy(stage?: window.WindowStage): void {
    const provider = this.getExpoHarmonyHostProvider();

    if (stage === undefined || provider.lifecycle.isWindowStageActive(this.context, stage)) {
      provider.hostState.dispatch(this.context, EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY);
    }
    if (provider.lifecycle.onWindowStageWillDestroy(this.context, stage)) super.onWindowStageWillDestroy();
  }

  override onWindowStageDestroy(): void {
    if (this.getExpoHarmonyHostProvider().lifecycle.onWindowStageDestroy(this.context)) super.onWindowStageDestroy();
  }

  override onWillForeground(): void {
    super.onWillForeground();
    this.getExpoHarmonyHostProvider().lifecycle.onWillForeground(this.context);
  }

  override onDidForeground(): void {
    super.onDidForeground();
    this.getExpoHarmonyHostProvider().lifecycle.onDidForeground(this.context);
  }

  override onWillBackground(): void {
    super.onWillBackground();
    this.getExpoHarmonyHostProvider().lifecycle.onWillBackground(this.context);
  }

  override onDidBackground(): void {
    super.onDidBackground();
    this.getExpoHarmonyHostProvider().lifecycle.onDidBackground(this.context);
  }

  override onForeground(): void {
    super.onForeground();
    this.getExpoHarmonyHostProvider().lifecycle.onForeground(this.context);
  }

  override onBackground(): void {
    this.getExpoHarmonyHostProvider().lifecycle.onBackground(this.context);
    super.onBackground();
  }

  override onConfigurationUpdate(configuration: Configuration): void {
    this.getExpoHarmonyHostProvider().lifecycle.onConfigurationUpdate(this.context, configuration);
    super.onConfigurationUpdate(configuration);
  }

  override onBackPressed(): boolean {
    const handled = this.getExpoHarmonyHostProvider().lifecycle.onBackPressed(this.context);
    const native = super.onBackPressed();

    return handled || native;
  }

  override onContinue(params: Record<string, Object>): AbilityConstant.OnContinueResult | Promise<AbilityConstant.OnContinueResult> {
    if (deviceInfo.sdkApiVersion >= 18) return this.continueAsync(params);

    const result = this.getExpoHarmonyHostProvider().lifecycle.onContinue(this.context, params);

    return result ?? super.onContinue(params);
  }

  private async continueAsync(params: Record<string, Object>): Promise<AbilityConstant.OnContinueResult> {
    const result = await this.getExpoHarmonyHostProvider().lifecycle.onContinueAsync(this.context, params);
    return result ?? (await super.onContinue(params));
  }

  override onSaveState(reason: AbilityConstant.StateType, params: Record<string, Object>): AbilityConstant.OnSaveResult {
    const result = this.getExpoHarmonyHostProvider().lifecycle.onSaveState(this.context, reason, params);
    return result ?? super.onSaveState(reason, params);
  }

  override async onSaveStateAsync(reason: AbilityConstant.StateType, params: Record<string, Object>): Promise<AbilityConstant.OnSaveResult> {
    const result = await this.getExpoHarmonyHostProvider().lifecycle.onSaveStateAsync(this.context, reason, params);
    return result ?? (await super.onSaveStateAsync(reason, params));
  }

  override onDestroy(): void {
    const provider = this.getExpoHarmonyHostProvider();

    try {
      provider.lifecycle.onDestroy(this.context);
    } finally {
      super.onDestroy();
    }
  }

  protected override onRNOHDestroyed(): void {
    try {
      this.getExpoHarmonyHostProvider().hostState.finishAbility(this.context);
    } finally {
      ExpoReactHost.detachAbility(this.context);
    }
  }

  override onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    this.getExpoHarmonyHostProvider().lifecycle.onMemoryLevel(this.context, level);
    this.getExpoHarmonyHostProvider().hostState.dispatch(this.context, EXPO_LIFECYCLE_MEMORY_LEVEL, level);
    super.onMemoryLevel(level);
  }
}
