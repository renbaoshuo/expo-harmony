import type { Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import type { ExpoModuleRegistration } from '../modules/ExpoModule';
import {
  EXPO_LIFECYCLE_ACTIVITY_DESTROY,
  EXPO_LIFECYCLE_NEW_INTENT,
  EXPO_LIFECYCLE_WINDOW_STAGE_SETUP,
  EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY,
} from '../protocol/Protocol';
import {
  ExpoLifecycleChannel,
  ExpoLifecycleEvent,
  expoLifecycleHostIdentity,
  ExpoLifecycleScopeRegistry,
  ExpoLifecycleSink,
} from './LifecycleDispatcher';

class ExpoHarmonyAbilityState {
  readonly abilityId: string;
  readonly lifecycle: ExpoLifecycleChannel;
  readonly generations: Map<number, number> = new Map<number, number>();
  readonly openedRuntimeIds: Set<number> = new Set<number>();
  readonly bootstrapEvents: Map<string, ExpoLifecycleEvent> = new Map<string, ExpoLifecycleEvent>();
  initialWant?: Want = undefined;
  nextRuntimeGeneration: number = 1;

  constructor(abilityId: string, lifecycle: ExpoLifecycleChannel) {
    this.abilityId = abilityId;
    this.lifecycle = lifecycle;
  }
}

/** @internal One exact RN Host generation within a UIAbility scope. */
export class ExpoHarmonyHostBinding {
  readonly abilityContext: common.UIAbilityContext;
  readonly runtimeId: number;
  readonly hostId: string;
  readonly runtimeGeneration: number;
  readonly initialWant?: Want;

  constructor(abilityContext: common.UIAbilityContext, runtimeId: number, hostId: string, runtimeGeneration: number, initialWant?: Want) {
    this.abilityContext = abilityContext;
    this.runtimeId = runtimeId;
    this.hostId = hostId;
    this.runtimeGeneration = runtimeGeneration;
    this.initialWant = initialWant;
  }
}

/** Provider-owned Ability/Host state. */
export class ExpoHarmonyHostState {
  private readonly lifecycle: ExpoLifecycleScopeRegistry<common.UIAbilityContext> = new ExpoLifecycleScopeRegistry<common.UIAbilityContext>();
  private readonly abilities: Map<common.UIAbilityContext, ExpoHarmonyAbilityState> = new Map<common.UIAbilityContext, ExpoHarmonyAbilityState>();
  private nextAbilityIdentity: number = 1;

  beginAbility(context: common.UIAbilityContext, want: Want): void {
    const state: ExpoHarmonyAbilityState = this.ensureAbility(context);

    state.lifecycle.beginAbility();
    state.initialWant = want;
  }

  openHost(context: common.UIAbilityContext, runtimeId: number): ExpoHarmonyHostBinding {
    const state: ExpoHarmonyAbilityState = this.ensureAbility(context);

    if (state.generations.has(runtimeId)) {
      throw new Error(`Expo Harmony RN Host '${runtimeId}' is already open.`);
    }

    const generation: number = state.nextRuntimeGeneration++;
    const firstHostGeneration: boolean = !state.openedRuntimeIds.has(runtimeId);

    state.lifecycle.openHost(runtimeId, firstHostGeneration ? Array.from(state.bootstrapEvents.values()) : []);
    state.openedRuntimeIds.add(runtimeId);
    state.generations.set(runtimeId, generation);

    return new ExpoHarmonyHostBinding(context, runtimeId, expoLifecycleHostIdentity(state.abilityId, runtimeId), generation, state.initialWant);
  }

  bindHost(binding: ExpoHarmonyHostBinding, sink: ExpoLifecycleSink): () => void {
    const state: ExpoHarmonyAbilityState = this.requireBinding(binding);
    const unbind: () => void = state.lifecycle.bindHost(binding.runtimeId, sink);

    return (): void => {
      unbind();

      const current: ExpoHarmonyAbilityState | undefined = this.abilities.get(binding.abilityContext);

      if (current === state && current.generations.get(binding.runtimeId) === binding.runtimeGeneration) {
        current.generations.delete(binding.runtimeId);
      }
    };
  }

  releaseHost(binding: ExpoHarmonyHostBinding): void {
    const state: ExpoHarmonyAbilityState | undefined = this.abilities.get(binding.abilityContext);

    if (
      state === undefined ||
      expoLifecycleHostIdentity(state.abilityId, binding.runtimeId) !== binding.hostId ||
      state.generations.get(binding.runtimeId) !== binding.runtimeGeneration
    ) {
      return;
    }

    state.generations.delete(binding.runtimeId);
    state.lifecycle.releaseHost(binding.runtimeId);
  }

  dispatch(context: common.UIAbilityContext, eventName: string, payload?: ESObject): void {
    const state: ExpoHarmonyAbilityState | undefined = this.abilities.get(context);
    if (state === undefined) return;

    const bootstrapEvent: boolean = eventName === EXPO_LIFECYCLE_NEW_INTENT || eventName === EXPO_LIFECYCLE_WINDOW_STAGE_SETUP;

    if (bootstrapEvent) {
      state.bootstrapEvents.delete(eventName);
      state.bootstrapEvents.set(eventName, { eventName, payload });
      if (eventName === EXPO_LIFECYCLE_NEW_INTENT && payload !== undefined) {
        state.initialWant = payload as Want;
      }
    } else if (eventName === EXPO_LIFECYCLE_WINDOW_STAGE_WILL_DESTROY) {
      state.bootstrapEvents.delete(EXPO_LIFECYCLE_WINDOW_STAGE_SETUP);
    }

    // Preserve FIFO order and avoid duplicating persistent bootstrap events.
    state.lifecycle.dispatch(eventName, payload);
  }

  finishAbility(context: common.UIAbilityContext): void {
    const state: ExpoHarmonyAbilityState | undefined = this.abilities.get(context);
    if (state === undefined) return;

    this.abilities.delete(context);
    state.generations.clear();
    state.openedRuntimeIds.clear();
    state.bootstrapEvents.clear();
    this.lifecycle.closeScope(context, EXPO_LIFECYCLE_ACTIVITY_DESTROY);
  }

  private ensureAbility(context: common.UIAbilityContext): ExpoHarmonyAbilityState {
    const current: ExpoHarmonyAbilityState | undefined = this.abilities.get(context);
    if (current !== undefined) return current;

    const state = new ExpoHarmonyAbilityState(`expo-ability-${this.nextAbilityIdentity++}`, this.lifecycle.openScope(context));

    this.abilities.set(context, state);
    return state;
  }

  private requireBinding(binding: ExpoHarmonyHostBinding): ExpoHarmonyAbilityState {
    const state: ExpoHarmonyAbilityState | undefined = this.abilities.get(binding.abilityContext);

    if (
      state === undefined ||
      expoLifecycleHostIdentity(state.abilityId, binding.runtimeId) !== binding.hostId ||
      state.generations.get(binding.runtimeId) !== binding.runtimeGeneration
    ) {
      throw new Error('The Expo Harmony RN Host binding is stale.');
    }

    return state;
  }
}

export interface ExpoHarmonyHostProvider {
  readonly expoModules: ExpoModuleRegistration[];
  readonly hostState: ExpoHarmonyHostState;
}
