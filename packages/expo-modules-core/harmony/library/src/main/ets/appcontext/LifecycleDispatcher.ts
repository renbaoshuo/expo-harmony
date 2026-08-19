import type { Want } from '@kit.AbilityKit';
import {
  EXPO_LIFECYCLE_ACTIVITY_DESTROY,
  EXPO_LIFECYCLE_ACTIVITY_RESULT,
  EXPO_LIFECYCLE_NEW_INTENT,
  EXPO_LIFECYCLE_USER_LEAVES,
} from '../protocol/Protocol';

export interface HarmonyAbilityResult {
  resultCode: number;
  want?: Want;
}

export interface ExpoLifecycleSink {
  postLifecycleEvent(eventName: string, payload?: ESObject): void;
}

/**
 * Ability-level lifecycle events are not exposed by RNOH itself. Applications
 * forward the corresponding UIAbility callbacks to this dispatcher. Every
 * active ExpoModulesCore TurboModule receives the event and relays it to the
 * C++ module registry on the owning JavaScript executor.
 */
export class ExpoLifecycleDispatcher {
  private static readonly sinks: Set<ExpoLifecycleSink> = new Set();

  static register(sink: ExpoLifecycleSink): () => void {
    ExpoLifecycleDispatcher.sinks.add(sink);
    return (): void => {
      ExpoLifecycleDispatcher.sinks.delete(sink);
    };
  }

  static onNewWant(want: Want): void {
    ExpoLifecycleDispatcher.dispatch(EXPO_LIFECYCLE_NEW_INTENT, want);
  }

  static onUserLeavesAbility(): void {
    ExpoLifecycleDispatcher.dispatch(EXPO_LIFECYCLE_USER_LEAVES);
  }

  static onAbilityDestroy(): void {
    ExpoLifecycleDispatcher.dispatch(EXPO_LIFECYCLE_ACTIVITY_DESTROY);
  }

  static onActivityResult(
    requestCode: number,
    result: HarmonyAbilityResult
  ): void {
    ExpoLifecycleDispatcher.dispatch(EXPO_LIFECYCLE_ACTIVITY_RESULT, {
      requestCode,
      resultCode: result.resultCode,
      data: result.want,
    });
  }

  private static dispatch(eventName: string, payload?: ESObject): void {
    Array.from(ExpoLifecycleDispatcher.sinks).forEach(sink =>
      sink.postLifecycleEvent(eventName, payload));
  }
}
