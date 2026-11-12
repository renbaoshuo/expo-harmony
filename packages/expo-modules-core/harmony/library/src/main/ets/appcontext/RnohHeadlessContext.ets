/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { common } from '@kit.AbilityKit';
import { RNInstance, RNInstancesCoordinator, StandardRNOHLogger } from '@rnoh/react-native-openharmony';
import { ExpoModuleError } from '../modules/ExpoModuleError';
import { RnohContextLifecycle } from './RnohContextLifecycle';
import { RnohPackagerClient } from './RnohPackagerClient';
import { adaptRnohExtensionContext } from './RnohExtensionContext';

const WINDOW_NOT_FOUND: number = 1300002;

export class RnohHeadlessContext {
  readonly coordinator: RNInstancesCoordinator;
  readonly ability: common.UIAbilityContext;
  readonly ready: Promise<void>;
  private readonly lifetime: RnohContextLifecycle;
  private readonly client: RnohPackagerClient;
  private readonly restore: () => void;
  private closed = false;

  constructor(context: common.Context, worker: string, hasOtherOwner: (context: common.UIAbilityContext) => boolean) {
    const native: ESObject = context;
    if (native.extensionAbilityInfo === undefined) {
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'Background execution requires an ExtensionAbility context.');
    }

    this.restore = adaptRnohExtensionContext(context);
    this.ability = native as common.UIAbilityContext;

    const previous = new RnohPackagerClient();

    try {
      this.coordinator = RNInstancesCoordinator.create(
        {
          uiAbilityContext: this.ability,
          logger: new StandardRNOHLogger(),
          rnohWorkerScriptUrl: worker,
          defaultBackPressHandler: (): void => {},
        },
        { disableCleaningRNInstances: hasOtherOwner(this.ability) },
      );
      if (previous.isCurrent()) {
        throw new ExpoModuleError('ERR_REACT_HOST_OWNER', 'The RNOH coordinator for this ability is already owned by another host.');
      }
      this.client = new RnohPackagerClient();
    } catch (error) {
      this.restore();
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'Unable to create the background RNOH coordinator.', error as Object);
    } finally {
      previous.restore();
    }

    try {
      const core = this.coordinator.getRNOHCoreContext();
      this.lifetime = RnohContextLifecycle.install(core);
      const insets: ESObject = core.safeAreaInsetsProvider;
      // Only a missing window is expected for ExtensionAbility; other failures still reject startup.
      this.ready = insets.ready.catch((error: ESObject): void => {
        if (error?.code !== WINDOW_NOT_FOUND)
          throw new ExpoModuleError('ERR_REACT_HOST_INSETS', 'Unable to initialize background display insets.', error as Object);
      });
      insets.ready = this.ready;
      this.ready.catch((): void => {});
      this.coordinator.onBackground();
    } catch (error) {
      this.close();
      throw new ExpoModuleError('ERR_REACT_HOST_CONTEXT', 'Unable to prepare the background RNOH context.', error as Object);
    }
  }

  destroyInstance(instance: RNInstance): Promise<void> {
    return this.lifetime.destroyInstance(instance);
  }

  destroy(): Promise<void> {
    return this.lifetime.destroy();
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    try {
      this.client.destroy((): void => this.coordinator.onDestroy());
    } finally {
      this.restore();
    }
  }
}
