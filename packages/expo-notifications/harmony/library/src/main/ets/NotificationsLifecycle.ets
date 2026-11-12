/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { AbilityLifecycleCallback, UIAbility, Want, wantConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { pushCommon, pushService } from '@kit.PushKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { ExpoAbilityLifecycleSubscriber, ExpoAppLifecycleSubscriber, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { NotificationsStore } from './NotificationsStore';
import {
  DEFAULT_ACTION,
  RESPONSE_KEY,
  PUSH_LISTENER_ACTION,
  NotificationResponse,
  record,
  integer,
  pushNotification,
  parseResponse,
} from './NotificationTypes';

const NOTIFICATION_LAUNCH_REASON = 'ReasonMessage_Notification';
// ArkTS does not support reflecting over SDK enum classes with Object.values.
const SYSTEM_WANT_KEYS = new Set<string>([
  wantConstant.Params.ABILITY_BACK_TO_OTHER_MISSION_STACK,
  wantConstant.Params.ABILITY_RECOVERY_RESTART,
  wantConstant.Params.CONTENT_TITLE_KEY,
  wantConstant.Params.SHARE_ABSTRACT_KEY,
  wantConstant.Params.SHARE_URL_KEY,
  wantConstant.Params.SUPPORT_CONTINUE_PAGE_STACK_KEY,
  wantConstant.Params.SUPPORT_CONTINUE_SOURCE_EXIT_KEY,
  wantConstant.Params.SHOW_MODE_KEY,
  wantConstant.Params.PARAMS_STREAM,
  wantConstant.Params.APP_CLONE_INDEX_KEY,
  wantConstant.Params.CALLER_REQUEST_CODE,
  wantConstant.Params.PAGE_PATH,
  wantConstant.Params.ROUTER_NAME,
  wantConstant.Params.PAGE_SOURCE_FILE,
  wantConstant.Params.BUILD_FUNCTION,
  wantConstant.Params.SUB_PACKAGE_NAME,
  wantConstant.Params.APP_INSTANCE_KEY,
  wantConstant.Params.CREATE_APP_INSTANCE_KEY,
  wantConstant.Params.CALLER_APP_CLONE_INDEX,
  wantConstant.Params.DESTINATION_PLUGIN_ABILITY,
  wantConstant.Params.APP_LAUNCH_TRUSTLIST,
  wantConstant.Params.ATOMIC_SERVICE_SHARE_ROUTER,
  wantConstant.Params.LAUNCH_REASON_MESSAGE,
  wantConstant.Params.ABILITY_UNIFIED_DATA_KEY,
]);

function report(error: Object): void {
  hilog.error(
    0,
    'ExpoNotifications',
    'Notification lifecycle operation failed (code %{public}s).',
    String((error as BusinessError).code ?? 'invalid-payload'),
  );
}

function captureResponse(want: Want, store: NotificationsStore): void {
  const serialized = want.parameters?.[RESPONSE_KEY];
  if (typeof serialized === 'string') {
    try {
      store.respond(parseResponse(serialized));
    } catch (error) {
      report(error as Object);
    }

    return;
  }

  if (want.parameters?.[wantConstant.Params.LAUNCH_REASON_MESSAGE] !== NOTIFICATION_LAUNCH_REASON) return;

  // Push Kit flattens clickAction.data into Want parameters alongside system keys.
  const data: Record<string, ESObject> = {};
  Object.keys(want.parameters ?? {}).forEach((key: string): void => {
    if (!SYSTEM_WANT_KEYS.has(key)) data[key] = want.parameters?.[key];
  });

  const response: NotificationResponse = {
    actionIdentifier: DEFAULT_ACTION,
    notification: pushNotification(util.generateRandomUUID(), null, null, data, Date.now()),
  };
  response.notification.request.content['sound'] = null;

  store.respond(response);
}

export class ExpoNotificationsAbilityLifecycleSubscriber extends ExpoAbilityLifecycleSubscriber {
  onCreate(want: Want): void {
    captureResponse(want, NotificationsStore.get(this.context));
  }
  onNewWant(want: Want): void {
    captureResponse(want, NotificationsStore.get(this.context));
  }
}

class PushLifecycle extends AbilityLifecycleCallback {
  private receiver?: UIAbility;
  private ability?: UIAbility;
  private listener?: (token: string) => void;

  onAbilityCreate(ability: UIAbility): void {
    if (!ability.context.abilityInfo.metadata?.some((entry): boolean => entry.name === PUSH_LISTENER_ACTION && entry.value === 'true')) return;
    if (this.ability !== undefined && this.ability !== ability) this.onAbilityDestroy(this.ability);

    this.ability = ability;
    const store = NotificationsStore.get(ability.context);

    try {
      if (this.receiver !== ability) {
        pushService.receiveMessage('DEFAULT', ability, (payload: pushCommon.PushPayload): void => {
          const current = this.ability;
          if (current !== ability || payload.type !== 'ALERT') return;

          try {
            const envelope = record(JSON.parse(payload.data), 'Push Kit payload');
            const source = record(envelope.notification, 'Push Kit notification');
            const click: Record<string, ESObject> = source.clickAction === undefined ? {} : record(source.clickAction, 'clickAction');
            const data: Record<string, ESObject> = click.data === undefined ? {} : record(click.data, 'clickAction.data');

            for (const field of ['title', 'body']) {
              if (source[field] !== undefined && source[field] !== null && typeof source[field] !== 'string') {
                throw new ExpoModuleError('ERR_NOTIFICATIONS_INVALID_ARGUMENT', `Push Kit ${field} must be a string.`);
              }
            }

            // Push Kit uses -1 (or omission) to request an automatically generated ID.
            const id =
              source.notifyId === undefined || source.notifyId === -1
                ? util.generateRandomUUID()
                : String(integer(source.notifyId, 'Push Kit notifyId', 0, 2147483647));
            const notification = pushNotification(id, source.title ?? null, source.body ?? null, data, Date.now());

            store.receive(current.context, notification);
          } catch (error) {
            report(error as Object);
          }
        });
        this.receiver = ability;
      }
    } catch (error) {
      report(error as Object);
    }

    if (this.listener !== undefined) return;

    const listener = (token: string): void => {
      if (this.ability !== ability || store.tokens.size === 0) return;

      try {
        if (store.lastToken === undefined) return;

        const revision = store.tokenRevision;

        store
          .runToken(async (): Promise<void> => {
            if (this.ability === ability && store.tokens.size > 0 && store.tokenRevision === revision && store.lastToken !== undefined) {
              await store.updateToken(token);
            }
          })
          .catch((error: Object): void => report(error));
      } catch (error) {
        report(error as Object);
      }
    };

    try {
      pushService.on('tokenUpdate', ability, listener);
      this.listener = listener;
    } catch (error) {
      report(error as Object);
    }
  }

  onAbilityDestroy(ability: UIAbility): void {
    if (this.ability !== ability) return;

    this.ability = undefined;
    if (this.listener !== undefined) {
      try {
        pushService.off('tokenUpdate', this.listener);
      } catch (error) {
        report(error as Object);
      }
    }

    this.listener = undefined;
    // DEFAULT binds the Ability's callee and has no public off API. Register
    // once for each new Ability, matching the documented onCreate integration.
    this.receiver = undefined;
  }

  onWindowStageCreate(_ability: UIAbility, _stage: window.WindowStage): void {}
  onWindowStageActive(_ability: UIAbility, _stage: window.WindowStage): void {}
  onWindowStageInactive(_ability: UIAbility, _stage: window.WindowStage): void {}
  onWindowStageDestroy(_ability: UIAbility, _stage: window.WindowStage): void {}
  onAbilityForeground(_ability: UIAbility): void {}
  onAbilityBackground(_ability: UIAbility): void {}
  onAbilityContinue(_ability: UIAbility): void {}
}

export class ExpoNotificationsAppLifecycleSubscriber extends ExpoAppLifecycleSubscriber {
  onCreate(): void {
    this.context.on('abilityLifecycle', new PushLifecycle());
  }
}
