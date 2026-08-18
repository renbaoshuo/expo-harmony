import { LifecycleState, RNOHPackage } from '@rnoh/react-native-openharmony';
import type { RNPackageContext } from '@rnoh/react-native-openharmony/ts';
import { ExpoPlatformServiceRegistry } from '@expo-harmony/expo-modules-core';
import type { UITurboModuleContext } from '@rnoh/react-native-openharmony';

const SERVICE_NAME: string = 'ExpoKeepAwakeService';
const WINDOW_OPERATION_TIMEOUT_MS: number = 5000;
let registered: boolean = false;

class ExpoKeepAwakeError extends Error {
  readonly code: string;

  constructor(code: string, msg: string) {
    super(msg);
    this.name = 'ExpoKeepAwakeError';
    this.code = code;
  }
}

class KeepAwakeService {
  readonly name: string = SERVICE_NAME;
  private readonly context: UITurboModuleContext;
  private readonly tags: Set<string> = new Set();
  private readonly cleanups: Array<() => void> = [];
  private foreground: boolean;
  private activated: boolean = false;
  private stateKnown: boolean = false;
  private activeId: number | null = null;
  private generation: number = 0;
  private mutation: Promise<void> = Promise.resolve();
  private destroyed: boolean = false;

  constructor(context: UITurboModuleContext) {
    this.context = context;
    this.foreground = context.rnInstance.getLifecycleState() === LifecycleState.READY;

    this.cleanups.push(
      context.rnInstance.subscribeToLifecycleEvents('FOREGROUND', () => {
        this.scheduleLifecycleState(true);
      }),
      context.rnInstance.subscribeToLifecycleEvents('BACKGROUND', () => {
        this.scheduleLifecycleState(false);
      }),
      context.rnInstance.subscribeToLifecycleEvents('WINDOW_SIZE_CHANGE', () => {
        this.stateKnown = false;
        this.scheduleReconciliation();
      }),
    );
  }

  onDestroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.cleanups.forEach((cleanup) => cleanup());
    this.cleanups.length = 0;
    this.foreground = false;
    this.tags.clear();
    this.stateKnown = false;

    this.scheduleReconciliation(true);
  }

  async invoke(method: string, args: ESObject[]): Promise<ESObject> {
    if (method === 'destroy') {
      this.onDestroy();
      await this.mutation.catch((): void => {});

      return true;
    }

    if (this.destroyed) {
      throw new ExpoKeepAwakeError('ERR_KEEP_AWAKE_DESTROYED', 'The Expo Keep Awake runtime has already been destroyed.');
    }

    if (method === 'activate') {
      const tag = requireTag(args[0]);

      await this.serialize(async (): Promise<void> => {
        this.tags.add(tag);
        await this.applyDesiredState();
      });

      return null;
    }

    if (method === 'deactivate') {
      const tag = requireTag(args[0]);

      await this.serialize(async (): Promise<void> => {
        this.tags.delete(tag);
        await this.applyDesiredState();
      });

      return null;
    }

    if (method === 'isActivated') {
      await this.mutation.catch((): void => {});

      return this.tags.size > 0;
    }

    if (method === 'isAvailable') {
      return true;
    }

    if (method === 'foreground') {
      await this.serialize(async (): Promise<void> => {
        this.foreground = true;
        await this.applyDesiredStateBestEffort();
      });

      return true;
    }

    if (method === 'background') {
      await this.serialize(async (): Promise<void> => {
        this.foreground = false;
        await this.applyDesiredStateBestEffort();
      });

      return true;
    }

    throw new ExpoKeepAwakeError('ERR_KEEP_AWAKE_UNKNOWN_METHOD', `Unknown Expo Keep Awake method '${method}'.`);
  }

  private async serialize(task: () => Promise<void>): Promise<void> {
    const next = this.mutation.catch((): void => {}).then(task);

    this.mutation = next;
    await next;
  }

  private async applyDesiredState(): Promise<void> {
    const desired = this.foreground && this.tags.size > 0;

    try {
      const window = await this.withTimeout(this.context.rnInstance.getRNWindow(), 'locate the current React Native window');

      const windowId = window.getWindowProperties().id;
      if (this.stateKnown && desired === this.activated && (!desired || this.activeId === windowId)) {
        return;
      }

      this.stateKnown = false;
      const generation = this.generation + 1;
      this.generation = generation;
      const operation = window.setWindowKeepScreenOn(desired);
      let settled: boolean = false;
      let timedOut: boolean = false;
      const observe = (): void => {
        settled = true;
        if (timedOut) this.reconcileLateWindowOperation(generation);
      };

      operation.then(observe, observe);

      await this.withTimeout(operation, `set keep-screen-on to ${String(desired)}`, (): void => {
        timedOut = true;
        if (settled) this.reconcileLateWindowOperation(generation);
      });

      this.activated = desired;
      this.stateKnown = true;
      this.activeId = desired ? windowId : null;
    } catch (error) {
      this.context.logger.warn(`Unable to update the Expo Keep Awake window state yet: ${String(error)}`);

      throw new ExpoKeepAwakeError('ERR_KEEP_AWAKE_WINDOW', `Unable to update the Harmony keep-screen-on state: ${String(error)}`);
    }
  }

  private async applyDesiredStateBestEffort(): Promise<void> {
    try {
      await this.applyDesiredState();
    } catch (_) {
      // Lifecycle transitions have no JavaScript caller to receive a rejection.
      // Keep the tags as source of truth so the next mutation can reconcile.
    }
  }

  private scheduleLifecycleState(foreground: boolean): void {
    if (this.destroyed) return;

    this.serialize(async (): Promise<void> => {
      this.foreground = foreground;
      await this.applyDesiredStateBestEffort();
    }).catch((): void => {});
  }

  private reconcileLateWindowOperation(generation: number): void {
    if (generation > this.generation) return;

    this.stateKnown = false;
    this.scheduleReconciliation(true);
  }

  private scheduleReconciliation(force: boolean = false): void {
    if (this.destroyed && !force) return;

    this.serialize(async (): Promise<void> => {
      await this.applyDesiredStateBestEffort();
    }).catch((): void => {});
  }

  private async withTimeout<T>(operation: Promise<T>, description: string, onTimeout?: () => void): Promise<T> {
    let timer: number = -1;

    try {
      return await Promise.race([
        operation,
        new Promise<T>((_, reject) => {
          timer = setTimeout(() => {
            onTimeout?.();
            reject(new Error(`Timed out after ${WINDOW_OPERATION_TIMEOUT_MS} ms while trying to ${description}.`));
          }, WINDOW_OPERATION_TIMEOUT_MS);
        }),
      ]);
    } finally {
      if (timer >= 0) clearTimeout(timer);
    }
  }
}

function requireTag(value: ESObject): string {
  if (typeof value !== 'string') {
    throw new ExpoKeepAwakeError('ERR_KEEP_AWAKE_TAG', 'Expo Keep Awake expected a string tag.');
  }

  return value;
}

function registerService(): void {
  if (registered) return;

  ExpoPlatformServiceRegistry.register({
    name: SERVICE_NAME,
    create: (context: UITurboModuleContext) => new KeepAwakeService(context),
  });

  registered = true;
}

export class ExpoKeepAwakePackage extends RNOHPackage {
  constructor(context: RNPackageContext) {
    super(context);

    registerService();
  }

  override getDebugName(): string {
    return '@expo-harmony/expo-keep-awake';
  }
}
