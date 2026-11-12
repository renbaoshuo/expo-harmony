/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { AbilityConstant } from '@kit.AbilityKit';
import type { Configuration, Want, common } from '@kit.AbilityKit';
import type { window } from '@kit.ArkUI';
import observer from '@ohos.arkui.observer';
import {
  ExpoModuleError,
  ExpoAbilityLifecycleSubscriber,
  ExpoAbilityLifecycleSubscriberRegistration,
  ExpoAppLifecycleSubscriberRegistration,
} from '@expo-harmony/expo-modules-core';
import { ApplicationLifecycleDispatcher, reportSubscriberFailure, validateRegistrations } from './ApplicationLifecycleDispatcher';

class AbilitySubscriberEntry {
  readonly id: string;
  readonly subscriber: ExpoAbilityLifecycleSubscriber;

  constructor(id: string, subscriber: ExpoAbilityLifecycleSubscriber) {
    this.id = id;
    this.subscriber = subscriber;
  }
}

class AbilitySubscribers {
  readonly entries: AbilitySubscriberEntry[] = [];
  stage?: window.WindowStage;
  destroyingStage?: window.WindowStage;
  windowSetup?: Promise<void>;
  ready: boolean = false;
  page?: (info: observer.RouterPageInfo) => void;
}

export class ExpoHarmonyLifecycleDispatcher {
  private readonly apps: ExpoAppLifecycleSubscriberRegistration[];
  private readonly abilities: ExpoAbilityLifecycleSubscriberRegistration[];
  private readonly scopes: Map<common.UIAbilityContext, AbilitySubscribers> = new Map();

  constructor(apps: ExpoAppLifecycleSubscriberRegistration[] = [], abilities: ExpoAbilityLifecycleSubscriberRegistration[] = []) {
    validateRegistrations(apps.map((entry: ExpoAppLifecycleSubscriberRegistration): string => entry.registrationId));
    validateRegistrations(abilities.map((entry: ExpoAbilityLifecycleSubscriberRegistration): string => entry.registrationId));

    this.apps = apps.slice();
    this.abilities = abilities.slice();
  }

  initializeApplication(context: common.ApplicationContext): void {
    ApplicationLifecycleDispatcher.initialize(context, this.apps);
  }

  onCreate(context: common.UIAbilityContext, want: Want, launch?: AbilityConstant.LaunchParam): void {
    this.initializeApplication(context.getApplicationContext());
    if (this.scopes.has(context)) throw new Error('Expo lifecycle subscribers already exist for this UIAbility.');

    const scope = new AbilitySubscribers();

    this.scopes.set(context, scope);
    for (const registration of this.abilities) {
      try {
        scope.entries.push(new AbilitySubscriberEntry(registration.registrationId, registration.create(context)));
      } catch (error) {
        this.onDestroy(context);
        throw new ExpoModuleError(
          'ERR_ABILITY_LIFECYCLE',
          `Unable to construct ability subscriber '${registration.registrationId}'.`,
          error as Object,
        );
      }
    }

    for (const entry of scope.entries.slice()) {
      try {
        entry.subscriber.onWillReceiveWant(want);
      } catch (error) {
        this.onDestroy(context);
        throw new ExpoModuleError('ERR_ABILITY_LIFECYCLE', `Unable to prepare launch intent '${entry.id}'.`, error as Object);
      }
    }

    for (const entry of scope.entries.slice()) {
      try {
        entry.subscriber.onCreate(want, launch);
      } catch (error) {
        this.onDestroy(context);
        throw new ExpoModuleError('ERR_ABILITY_LIFECYCLE', `Unable to initialize ability subscriber '${entry.id}'.`, error as Object);
      }
    }

    const page = (info: observer.RouterPageInfo): void => {
      if (info.state !== observer.RouterPageState.ON_PAGE_SHOW) return;

      this.onWindowStageReady(context).catch((error: Object): void => {
        reportSubscriberFailure('ability', 'onWindowStageReady', error);
      });
    };

    try {
      observer.on('routerPageUpdate', context, page);
      scope.page = page;
    } catch (error) {
      this.onDestroy(context);
      throw new ExpoModuleError('ERR_ABILITY_LIFECYCLE', 'Unable to observe ability page events.', error as Object);
    }
  }

  onNewWant(context: common.UIAbilityContext, want: Want, launch: AbilityConstant.LaunchParam): void {
    this.dispatch(context, 'onWillReceiveWant', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWillReceiveWant(want));
    this.dispatch(context, 'onNewWant', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onNewWant(want, launch));
  }

  onWillForeground(context: common.UIAbilityContext): void {
    this.dispatch(context, 'onWillForeground', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWillForeground());
  }

  onDidForeground(context: common.UIAbilityContext): void {
    this.dispatch(context, 'onDidForeground', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onDidForeground());
  }

  onWillBackground(context: common.UIAbilityContext): void {
    this.dispatch(context, 'onWillBackground', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWillBackground());
  }

  onDidBackground(context: common.UIAbilityContext): void {
    this.dispatch(context, 'onDidBackground', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onDidBackground());
  }

  onForeground(context: common.UIAbilityContext): void {
    this.dispatch(context, 'onForeground', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onForeground());
  }

  onBackground(context: common.UIAbilityContext): void {
    this.dispatch(context, 'onBackground', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onBackground());
  }

  onConfigurationUpdate(context: common.UIAbilityContext, configuration: Configuration): void {
    this.dispatch(context, 'onConfigurationUpdate', (subscriber: ExpoAbilityLifecycleSubscriber): void =>
      subscriber.onConfigurationUpdate(configuration),
    );
  }

  onMemoryLevel(context: common.UIAbilityContext, level: AbilityConstant.MemoryLevel): void {
    this.dispatch(context, 'onMemoryLevel', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onMemoryLevel(level));
  }

  onWindowStageCreate(context: common.UIAbilityContext, stage: window.WindowStage): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    scope.stage = stage;
    scope.windowSetup = undefined;
    scope.ready = false;
    this.dispatch(context, 'onWindowStageCreate', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWindowStageCreate(stage));
  }

  onWindowStageRestore(context: common.UIAbilityContext, stage: window.WindowStage): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    scope.stage = stage;
    scope.windowSetup = undefined;
    scope.ready = false;
    this.dispatch(context, 'onWindowStageRestore', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWindowStageRestore(stage));
  }

  async onWindowSetup(context: common.UIAbilityContext, target: window.Window): Promise<void> {
    const scope = this.scopes.get(context);
    const stage = scope?.stage;
    if (scope === undefined || stage === undefined || scope.entries.length === 0) return;

    try {
      // RNOH's asynchronous setup for a previous stage can finish after a new stage arrives.
      const mainWindow = stage.getMainWindowSync();
      if (mainWindow.getWindowProperties().id !== target.getWindowProperties().id) return;
    } catch (error) {
      reportSubscriberFailure('ability', 'onWindowSetup', error);
      return;
    }

    if (scope.windowSetup === undefined) {
      const setup = Promise.resolve().then(async (): Promise<void> => {
        for (const entry of scope.entries) {
          if (this.scopes.get(context) !== scope || scope.windowSetup !== setup) return;
          try {
            await entry.subscriber.onWindowSetup(target);
          } catch (error) {
            reportSubscriberFailure(entry.id, 'onWindowSetup', error);
          }
        }
      });
      scope.windowSetup = setup;
    }
    await scope.windowSetup;
  }

  async onWindowStageSetup(context: common.UIAbilityContext, stage: window.WindowStage): Promise<void> {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    for (const entry of scope.entries) {
      if (this.scopes.get(context) !== scope || scope.stage !== stage) return;
      try {
        await entry.subscriber.onWindowStageSetup(stage);
      } catch (error) {
        reportSubscriberFailure(entry.id, 'onWindowStageSetup', error);
      }
    }
  }

  isWindowStageActive(context: common.UIAbilityContext, stage: window.WindowStage): boolean {
    return this.scopes.get(context)?.stage === stage;
  }

  private async onWindowStageReady(context: common.UIAbilityContext): Promise<void> {
    const scope = this.scopes.get(context);
    if (scope === undefined || scope.ready || scope.stage === undefined) return;

    const stage = scope.stage;

    scope.ready = true;
    for (const entry of scope.entries) {
      if (this.scopes.get(context) !== scope || scope.stage !== stage) return;

      try {
        await entry.subscriber.onWindowStageReady(stage);
      } catch (error) {
        reportSubscriberFailure(entry.id, 'onWindowStageReady', error);
      }
    }
  }

  onWindowStageWillDestroy(context: common.UIAbilityContext, stage?: window.WindowStage): boolean {
    const scope = this.scopes.get(context);
    if (scope === undefined) return true;

    const current = stage ?? scope.stage;
    scope.destroyingStage = current;
    if (stage !== undefined && scope.stage !== stage) return false;

    scope.stage = undefined;
    scope.windowSetup = undefined;
    this.dispatch(context, 'onWindowStageWillDestroy', (subscriber: ExpoAbilityLifecycleSubscriber): void =>
      subscriber.onWindowStageWillDestroy(current),
    );
    return true;
  }

  onWindowStageDestroy(context: common.UIAbilityContext): boolean {
    const scope = this.scopes.get(context);
    if (scope === undefined) return true;

    const destroying = scope.destroyingStage;
    scope.destroyingStage = undefined;
    if (destroying !== undefined && scope.stage !== undefined && destroying !== scope.stage) return false;

    scope.stage = undefined;
    scope.windowSetup = undefined;
    this.dispatch(context, 'onWindowStageDestroy', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWindowStageDestroy());
    return true;
  }

  onBackPressed(context: common.UIAbilityContext): boolean {
    let handled: boolean = false;

    this.dispatch(context, 'onBackPressed', (subscriber: ExpoAbilityLifecycleSubscriber): void => {
      if (subscriber.onBackPressed()) handled = true;
    });

    return handled;
  }

  onContinue(context: common.UIAbilityContext, params: Record<string, Object>): AbilityConstant.OnContinueResult | undefined {
    let result: AbilityConstant.OnContinueResult | undefined = undefined;
    const scope = this.scopes.get(context);

    this.dispatch(context, 'onContinue', (subscriber: ExpoAbilityLifecycleSubscriber): void => {
      try {
        result = mergeContinueResult(result, subscriber.onContinue(params));
      } catch (error) {
        result = AbilityConstant.OnContinueResult.REJECT;

        throw new Error(String(error));
      }
    });

    return this.scopes.get(context) === scope ? result : AbilityConstant.OnContinueResult.REJECT;
  }

  async onContinueAsync(context: common.UIAbilityContext, params: Record<string, Object>): Promise<AbilityConstant.OnContinueResult | undefined> {
    let result: AbilityConstant.OnContinueResult | undefined = undefined;
    const scope = this.scopes.get(context);
    if (scope === undefined) return result;

    for (const entry of scope.entries.slice()) {
      if (this.scopes.get(context) !== scope) return AbilityConstant.OnContinueResult.REJECT;

      let vote: AbilityConstant.OnContinueResult | undefined;

      try {
        vote = await entry.subscriber.onContinueAsync(params);
      } catch (error) {
        reportSubscriberFailure(entry.id, 'onContinueAsync', error);
        vote = AbilityConstant.OnContinueResult.REJECT;
      }

      result = mergeContinueResult(result, vote);
    }

    return this.scopes.get(context) === scope ? result : AbilityConstant.OnContinueResult.REJECT;
  }

  onSaveState(
    context: common.UIAbilityContext,
    reason: AbilityConstant.StateType,
    params: Record<string, Object>,
  ): AbilityConstant.OnSaveResult | undefined {
    let result: AbilityConstant.OnSaveResult | undefined = undefined;
    const scope = this.scopes.get(context);

    this.dispatch(context, 'onSaveState', (subscriber: ExpoAbilityLifecycleSubscriber): void => {
      try {
        result = mergeSaveResult(reason, result, subscriber.onSaveState(reason, params));
      } catch (error) {
        result = AbilityConstant.OnSaveResult.ALL_REJECT;

        throw new Error(String(error));
      }
    });

    return this.scopes.get(context) === scope ? result : AbilityConstant.OnSaveResult.ALL_REJECT;
  }

  async onSaveStateAsync(
    context: common.UIAbilityContext,
    reason: AbilityConstant.StateType,
    params: Record<string, Object>,
  ): Promise<AbilityConstant.OnSaveResult | undefined> {
    let result: AbilityConstant.OnSaveResult | undefined = undefined;
    const scope = this.scopes.get(context);
    if (scope === undefined) return result;

    for (const entry of scope.entries.slice()) {
      if (this.scopes.get(context) !== scope) return AbilityConstant.OnSaveResult.ALL_REJECT;
      try {
        result = mergeSaveResult(reason, result, await entry.subscriber.onSaveStateAsync(reason, params));
      } catch (error) {
        reportSubscriberFailure(entry.id, 'onSaveStateAsync', error);
        result = AbilityConstant.OnSaveResult.ALL_REJECT;
      }
    }

    return this.scopes.get(context) === scope ? result : AbilityConstant.OnSaveResult.ALL_REJECT;
  }

  onDestroy(context: common.UIAbilityContext): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    this.scopes.delete(context);
    scope.stage = undefined;

    if (scope.page !== undefined) {
      try {
        observer.off('routerPageUpdate', context, scope.page);
      } catch (error) {
        reportSubscriberFailure('ability', 'routerPageUpdate cleanup', error);
      }
      scope.page = undefined;
    }

    scope.entries.forEach((entry: AbilitySubscriberEntry): void => {
      try {
        entry.subscriber.onDestroy();
      } catch (error) {
        reportSubscriberFailure(entry.id, 'onDestroy', error);
      }
    });

    scope.entries.length = 0;
  }

  private dispatch(context: common.UIAbilityContext, callback: string, body: (subscriber: ExpoAbilityLifecycleSubscriber) => void): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    for (const entry of scope.entries.slice()) {
      if (this.scopes.get(context) !== scope) return;
      try {
        body(entry.subscriber);
      } catch (error) {
        reportSubscriberFailure(entry.id, callback, error);
      }
    }
  }
}

function mergeContinueResult(
  current: AbilityConstant.OnContinueResult | undefined,
  vote: AbilityConstant.OnContinueResult | undefined,
): AbilityConstant.OnContinueResult | undefined {
  if (vote === undefined) return current;

  if (
    current === undefined ||
    vote === AbilityConstant.OnContinueResult.REJECT ||
    (vote === AbilityConstant.OnContinueResult.MISMATCH && current === AbilityConstant.OnContinueResult.AGREE)
  )
    return vote;

  return current;
}

function mergeSaveResult(
  reason: AbilityConstant.StateType,
  current: AbilityConstant.OnSaveResult | undefined,
  vote: AbilityConstant.OnSaveResult | undefined,
): AbilityConstant.OnSaveResult | undefined {
  if (vote === undefined) return current;

  const recovery = reason === AbilityConstant.StateType.APP_RECOVERY;
  const allowed: AbilityConstant.OnSaveResult[] = recovery
    ? [
        AbilityConstant.OnSaveResult.ALL_AGREE,
        AbilityConstant.OnSaveResult.ALL_REJECT,
        AbilityConstant.OnSaveResult.RECOVERY_AGREE,
        AbilityConstant.OnSaveResult.RECOVERY_REJECT,
      ]
    : [
        AbilityConstant.OnSaveResult.ALL_AGREE,
        AbilityConstant.OnSaveResult.ALL_REJECT,
        AbilityConstant.OnSaveResult.CONTINUATION_REJECT,
        AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH,
      ];
  if (!allowed.includes(vote)) throw new ExpoModuleError('ERR_SAVE_STATE_RESULT', `Save result ${vote} is not valid for state type ${reason}.`);

  const reject = recovery ? AbilityConstant.OnSaveResult.RECOVERY_REJECT : AbilityConstant.OnSaveResult.CONTINUATION_REJECT;
  const agree = recovery ? AbilityConstant.OnSaveResult.RECOVERY_AGREE : AbilityConstant.OnSaveResult.ALL_AGREE;

  if (current === AbilityConstant.OnSaveResult.ALL_REJECT || vote === AbilityConstant.OnSaveResult.ALL_REJECT)
    return AbilityConstant.OnSaveResult.ALL_REJECT;
  if (current === reject || vote === reject) return reject;

  if (!recovery && (current === AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH || vote === AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH))
    return AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH;
  if (recovery && (current === AbilityConstant.OnSaveResult.RECOVERY_AGREE || vote === AbilityConstant.OnSaveResult.RECOVERY_AGREE)) return agree;

  return current ?? vote;
}
