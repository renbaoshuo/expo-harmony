import type { ExpoServiceClass } from './ExpoServicesRegistry';
import type { ExpoHarmonyLifecycleDispatcher } from './ExpoHarmonyLifecycleDispatcher';
import type { Want } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import type { ExpoModuleRegistration } from '../modules/ExpoModule';
import { ExpoRuntimeSession } from './ExpoRuntimeSession';
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
  readonly sessionDisposers: Map<number, () => void> = new Map<number, () => void>();
  readonly bindings: Map<number, ExpoHarmonyHostBinding> = new Map<number, ExpoHarmonyHostBinding>();
  readonly bootstrapEvents: Map<string, ExpoLifecycleEvent> = new Map<string, ExpoLifecycleEvent>();
  initialWant?: Want = undefined;
  nextRuntimeGeneration: number = 1;

  constructor(abilityId: string, lifecycle: ExpoLifecycleChannel) {
    this.abilityId = abilityId;
    this.lifecycle = lifecycle;
  }
}

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

export class ExpoHarmonyHostState {
  private readonly lifecycle: ExpoLifecycleScopeRegistry<common.UIAbilityContext> = new ExpoLifecycleScopeRegistry<common.UIAbilityContext>();
  private readonly abilities: Map<common.UIAbilityContext, ExpoHarmonyAbilityState> = new Map<common.UIAbilityContext, ExpoHarmonyAbilityState>();
  private nextAbilityIdentity: number = 1;

  beginAbility(context: common.UIAbilityContext, want: Want): void {
    const state: ExpoHarmonyAbilityState = this.ensureAbility(context);

    state.lifecycle.beginAbility();
    state.initialWant = want;
  }

  openHost(context: common.UIAbilityContext, runtimeId: number, session?: ExpoRuntimeSession): ExpoHarmonyHostBinding {
    session?.assertOpen();

    const state: ExpoHarmonyAbilityState = this.ensureAbility(context);

    if (state.generations.has(runtimeId)) {
      throw new Error(`Expo Harmony RN Host '${runtimeId}' is already open.`);
    }

    const generation: number = state.nextRuntimeGeneration++;
    const first: boolean = !state.openedRuntimeIds.has(runtimeId);

    state.lifecycle.openHost(
      runtimeId,
      first ? Array.from(state.bootstrapEvents.values()) : [],
      session === undefined ? [] : [EXPO_LIFECYCLE_NEW_INTENT],
    );
    state.openedRuntimeIds.add(runtimeId);
    state.generations.set(runtimeId, generation);

    const binding = new ExpoHarmonyHostBinding(
      context,
      runtimeId,
      expoLifecycleHostIdentity(state.abilityId, runtimeId),
      generation,
      session === undefined ? state.initialWant : session.initialWant,
    );

    state.bindings.set(runtimeId, binding);
    if (session !== undefined)
      state.sessionDisposers.set(
        runtimeId,
        session.onClose((): void => this.releaseHost(binding)),
      );

    return binding;
  }

  bindHost(binding: ExpoHarmonyHostBinding, sink: ExpoLifecycleSink): () => void {
    const state: ExpoHarmonyAbilityState = this.requireBinding(binding);
    const unbind: () => void = state.lifecycle.bindHost(binding.runtimeId, sink);

    return (): void => {
      unbind();

      const current: ExpoHarmonyAbilityState | undefined = this.abilities.get(binding.abilityContext);

      if (current === state && current.generations.get(binding.runtimeId) === binding.runtimeGeneration) {
        current.generations.delete(binding.runtimeId);
        current.bindings.delete(binding.runtimeId);
        current.sessionDisposers.get(binding.runtimeId)?.();
        current.sessionDisposers.delete(binding.runtimeId);
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
    state.bindings.delete(binding.runtimeId);
    state.sessionDisposers.get(binding.runtimeId)?.();
    state.sessionDisposers.delete(binding.runtimeId);
    state.lifecycle.releaseHost(binding.runtimeId);
  }

  dispatchWant(binding: ExpoHarmonyHostBinding, want: Want): void {
    const state = this.requireBinding(binding);
    state.lifecycle.dispatchToHost(binding.runtimeId, EXPO_LIFECYCLE_NEW_INTENT, JSON.parse(JSON.stringify(want)) as Want);
  }

  getHostBinding(context: common.UIAbilityContext, runtimeId: number): ExpoHarmonyHostBinding | undefined {
    return this.abilities.get(context)?.bindings.get(runtimeId);
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

    state.lifecycle.dispatch(eventName, payload);
  }

  finishAbility(context: common.UIAbilityContext): void {
    const state: ExpoHarmonyAbilityState | undefined = this.abilities.get(context);
    if (state === undefined) return;

    this.abilities.delete(context);
    state.generations.clear();
    state.bindings.clear();
    state.sessionDisposers.forEach((dispose: () => void): void => dispose());
    state.sessionDisposers.clear();
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
  readonly lifecycle: ExpoHarmonyLifecycleDispatcher;
  readonly expoServices: ExpoServiceClass[];
  readonly expoModules: ExpoModuleRegistration[];
  readonly hostState: ExpoHarmonyHostState;
}
