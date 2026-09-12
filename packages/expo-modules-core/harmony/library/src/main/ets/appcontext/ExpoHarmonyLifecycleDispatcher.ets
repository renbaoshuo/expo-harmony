import { AbilityConstant, ApplicationStateChangeCallback, EnvironmentCallback } from '@kit.AbilityKit';
import type { Configuration, Want, common } from '@kit.AbilityKit';
import type { window } from '@kit.ArkUI';
import observer from '@ohos.arkui.observer';
import {
  ExpoAbilityLifecycleSubscriber,
  ExpoAbilityLifecycleSubscriberRegistration,
  ExpoAppLifecycleSubscriber,
  ExpoAppLifecycleSubscriberRegistration,
} from './ExpoLifecycleSubscriber';

function reportSubscriberFailure(id: string, callback: string, error: ESObject): void {
  console.error(`Expo lifecycle subscriber '${id}' failed in ${callback}: ${String(error)}`);
}

function validateRegistrations(ids: string[]): void {
  const seen = new Set<string>();
  ids.forEach((id: string): void => {
    if (id.length === 0 || seen.has(id)) throw new Error(`Invalid or duplicate Expo lifecycle subscriber registration '${id}'.`);
    seen.add(id);
  });
}

class AppSubscriberEntry {
  readonly id: string;
  readonly subscriber: ExpoAppLifecycleSubscriber;

  constructor(id: string, subscriber: ExpoAppLifecycleSubscriber) {
    this.id = id;
    this.subscriber = subscriber;
  }
}

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
  ready: boolean = false;
  page?: (info: observer.RouterPageInfo) => void;
}

class AppEnvironmentCallback extends EnvironmentCallback {
  override onConfigurationUpdated(configuration: Configuration): void {
    ExpoAppLifecycleDispatcher.dispatch('onConfigurationUpdate', (subscriber: ExpoAppLifecycleSubscriber): void =>
      subscriber.onConfigurationUpdate(configuration),
    );
  }

  override onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    ExpoAppLifecycleDispatcher.dispatch('onMemoryLevel', (subscriber: ExpoAppLifecycleSubscriber): void => subscriber.onMemoryLevel(level));
  }
}

class AppStateCallback extends ApplicationStateChangeCallback {
  override onApplicationForeground(): void {
    ExpoAppLifecycleDispatcher.dispatch('onForeground', (subscriber: ExpoAppLifecycleSubscriber): void => subscriber.onForeground());
  }

  override onApplicationBackground(): void {
    ExpoAppLifecycleDispatcher.dispatch('onBackground', (subscriber: ExpoAppLifecycleSubscriber): void => subscriber.onBackground());
  }
}

class ExpoAppLifecycleDispatcher {
  private static context?: common.ApplicationContext;
  private static readonly registered: Set<string> = new Set<string>();
  private static readonly entries: AppSubscriberEntry[] = [];
  private static readonly environment: AppEnvironmentCallback = new AppEnvironmentCallback();
  private static readonly state: AppStateCallback = new AppStateCallback();

  static initialize(context: common.ApplicationContext, registrations: ExpoAppLifecycleSubscriberRegistration[]): void {
    if (ExpoAppLifecycleDispatcher.context === undefined) {
      const id = context.on('environment', ExpoAppLifecycleDispatcher.environment);

      try {
        context.on('applicationStateChange', ExpoAppLifecycleDispatcher.state);
      } catch (error) {
        context.off('environment', id).catch((failure: Object): void => {
          reportSubscriberFailure('application', 'environment cleanup', failure);
        });

        throw new Error(`Unable to subscribe to native application lifecycle events: ${String(error)}`);
      }

      ExpoAppLifecycleDispatcher.context = context;
    }

    const created: AppSubscriberEntry[] = [];

    registrations.forEach((registration: ExpoAppLifecycleSubscriberRegistration): void => {
      if (ExpoAppLifecycleDispatcher.registered.has(registration.registrationId)) return;

      // Mark before construction to make reentrant and repeated initialization safe.
      ExpoAppLifecycleDispatcher.registered.add(registration.registrationId);

      try {
        const entry = new AppSubscriberEntry(
          registration.registrationId,
          registration.create(ExpoAppLifecycleDispatcher.context as common.ApplicationContext),
        );

        ExpoAppLifecycleDispatcher.entries.push(entry);
        created.push(entry);
      } catch (error) {
        reportSubscriberFailure(registration.registrationId, 'constructor', error);
      }
    });

    created.forEach((entry: AppSubscriberEntry): void => {
      try {
        entry.subscriber.onCreate();
      } catch (error) {
        reportSubscriberFailure(entry.id, 'onCreate', error);
      }
    });
  }

  static dispatch(callback: string, body: (subscriber: ExpoAppLifecycleSubscriber) => void): void {
    ExpoAppLifecycleDispatcher.entries.slice().forEach((entry: AppSubscriberEntry): void => {
      try {
        body(entry.subscriber);
      } catch (error) {
        reportSubscriberFailure(entry.id, callback, error);
      }
    });
  }
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
    ExpoAppLifecycleDispatcher.initialize(context, this.apps);
  }

  onCreate(context: common.UIAbilityContext, want: Want, launch?: AbilityConstant.LaunchParam): void {
    this.initializeApplication(context.getApplicationContext());
    if (this.scopes.has(context)) throw new Error('Expo lifecycle subscribers already exist for this UIAbility.');

    const scope = new AbilitySubscribers();

    this.scopes.set(context, scope);
    this.abilities.forEach((registration: ExpoAbilityLifecycleSubscriberRegistration): void => {
      try {
        scope.entries.push(new AbilitySubscriberEntry(registration.registrationId, registration.create(context)));
      } catch (error) {
        reportSubscriberFailure(registration.registrationId, 'constructor', error);
      }
    });

    this.dispatch(context, 'onCreate', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onCreate(want, launch));

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
      reportSubscriberFailure('ability', 'routerPageUpdate', error);
    }
  }

  onNewWant(context: common.UIAbilityContext, want: Want, launch: AbilityConstant.LaunchParam): void {
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
    scope.ready = false;
    this.dispatch(context, 'onWindowStageCreate', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWindowStageCreate(stage));
  }

  onWindowStageRestore(context: common.UIAbilityContext, stage: window.WindowStage): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    scope.stage = stage;
    scope.ready = false;
    this.dispatch(context, 'onWindowStageRestore', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWindowStageRestore(stage));
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

  onWindowStageWillDestroy(context: common.UIAbilityContext, stage?: window.WindowStage): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    const current = stage ?? scope.stage;

    scope.stage = undefined;
    this.dispatch(context, 'onWindowStageWillDestroy', (subscriber: ExpoAbilityLifecycleSubscriber): void =>
      subscriber.onWindowStageWillDestroy(current),
    );
  }

  onWindowStageDestroy(context: common.UIAbilityContext): void {
    const scope = this.scopes.get(context);
    if (scope === undefined) return;

    scope.stage = undefined;
    this.dispatch(context, 'onWindowStageDestroy', (subscriber: ExpoAbilityLifecycleSubscriber): void => subscriber.onWindowStageDestroy());
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
  const rejected =
    vote === AbilityConstant.OnSaveResult.ALL_REJECT ||
    (recovery
      ? vote === AbilityConstant.OnSaveResult.RECOVERY_REJECT
      : vote === AbilityConstant.OnSaveResult.CONTINUATION_REJECT || vote === AbilityConstant.OnSaveResult.RECOVERY_AGREE);
  if (current === AbilityConstant.OnSaveResult.ALL_REJECT || rejected) return AbilityConstant.OnSaveResult.ALL_REJECT;

  if (!recovery && (current === AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH || vote === AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH))
    return AbilityConstant.OnSaveResult.CONTINUATION_MISMATCH;

  return AbilityConstant.OnSaveResult.ALL_AGREE;
}
