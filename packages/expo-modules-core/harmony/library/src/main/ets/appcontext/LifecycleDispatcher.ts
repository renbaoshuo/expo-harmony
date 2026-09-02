export interface ExpoLifecycleEvent {
  readonly eventName: string;
  readonly payload?: ESObject;
}

export interface ExpoLifecycleSink {
  postLifecycleEvent(eventName: string, payload?: ESObject): void;
}

/** Stable identity for one RN Host inside an Ability-owned provider scope. */
export function expoLifecycleHostIdentity(abilityId: string, hostKey: number): string {
  if (abilityId.length === 0 || !Number.isSafeInteger(hostKey) || hostKey < 0) {
    throw new Error('Expo lifecycle Host identity requires a valid Ability ID and RN instance ID.');
  }
  return `${abilityId}:rn-${hostKey}`;
}

/** FIFO for Ability/Host and Host/Runtime hand-offs. */
export class ExpoLifecycleEventQueue {
  private readonly events: ExpoLifecycleEvent[] = [];

  enqueue(eventName: string, payload?: ESObject): void {
    this.events.push({ eventName, payload });
  }

  drain(sink: ExpoLifecycleSink): void {
    while (this.events.length > 0) {
      const event: ExpoLifecycleEvent = this.events.shift() as ExpoLifecycleEvent;
      deliverLifecycleEvent(sink, event.eventName, event.payload);
    }
  }

  clear(): void {
    this.events.length = 0;
  }

  hasEvent(eventName: string): boolean {
    return this.events.some(
      (event: ExpoLifecycleEvent): boolean => event.eventName === eventName,
    );
  }

  get length(): number {
    return this.events.length;
  }
}

class ExpoLifecycleHostEntry implements ExpoLifecycleSink {
  readonly pending: ExpoLifecycleEventQueue = new ExpoLifecycleEventQueue();
  sink?: ExpoLifecycleSink = undefined;
  draining: boolean = false;

  postLifecycleEvent(eventName: string, payload?: ESObject): void {
    const sink: ExpoLifecycleSink | undefined = this.sink;
    if (sink === undefined || this.draining) {
      this.pending.enqueue(eventName, payload);
      return;
    }
    deliverLifecycleEvent(sink, eventName, payload);
  }
}

/** UIAbility-scoped lifecycle routing channel. */
export class ExpoLifecycleChannel {
  private readonly hosts: Map<number, ExpoLifecycleHostEntry> =
    new Map<number, ExpoLifecycleHostEntry>();
  private readonly beforeFirstHost: ExpoLifecycleEventQueue =
    new ExpoLifecycleEventQueue();
  private began: boolean = false;
  private valid: boolean = true;

  beginAbility(): void {
    this.assertValid();
    if (this.began) throw new Error('The Expo lifecycle Ability scope began more than once.');
    this.began = true;
  }

  openHost(hostKey: number, bootstrapEvents: ExpoLifecycleEvent[] = []): void {
    this.assertValid();
    if (this.hosts.has(hostKey)) {
      throw new Error(`Expo lifecycle Host '${hostKey}' is already open.`);
    }

    const entry = new ExpoLifecycleHostEntry();
    bootstrapEvents.forEach((event: ExpoLifecycleEvent): void => {
      // Avoid duplicating a persistent event already in the FIFO.
      if (this.hosts.size > 0 || !this.beforeFirstHost.hasEvent(event.eventName)) {
        entry.pending.enqueue(event.eventName, event.payload);
      }
    });

    if (this.hosts.size === 0) {
      this.beforeFirstHost.drain(entry);
    }

    this.hosts.set(hostKey, entry);
  }

  bindHost(hostKey: number, sink: ExpoLifecycleSink): () => void {
    this.assertValid();

    const entry: ExpoLifecycleHostEntry = this.requireHost(hostKey);
    if (entry.sink !== undefined) {
      throw new Error(`Expo lifecycle Host '${hostKey}' is already bound.`);
    }

    entry.sink = sink;
    entry.draining = true;
    try {
      entry.pending.drain(sink);
    } finally {
      entry.draining = false;
    }

    return (): void => {
      const current: ExpoLifecycleHostEntry | undefined = this.hosts.get(hostKey);
      if (current !== entry || current.sink !== sink) return;

      this.hosts.delete(hostKey);
      current.sink = undefined;
      current.draining = false;
      current.pending.clear();
    };
  }

  releaseHost(hostKey: number): void {
    const entry: ExpoLifecycleHostEntry | undefined = this.hosts.get(hostKey);
    if (entry === undefined) return;
    this.hosts.delete(hostKey);
    entry.sink = undefined;
    entry.draining = false;
    entry.pending.clear();
  }

  dispatch(eventName: string, payload?: ESObject, queueWhenEmpty: boolean = true): void {
    if (!this.valid) return;
    if (this.hosts.size === 0) {
      if (queueWhenEmpty) this.beforeFirstHost.enqueue(eventName, payload);
      return;
    }

    this.hosts.forEach((entry: ExpoLifecycleHostEntry): void => {
      entry.postLifecycleEvent(eventName, payload);
    });
  }

  /** Delivers terminal Ability events only to bound Hosts. */
  close(eventName: string, payload?: ESObject): void {
    if (!this.valid) return;

    this.valid = false;
    this.beforeFirstHost.clear();

    this.hosts.forEach((entry: ExpoLifecycleHostEntry): void => {
      const sink: ExpoLifecycleSink | undefined = entry.sink;

      entry.pending.clear();
      entry.sink = undefined;
      entry.draining = false;

      if (sink !== undefined) deliverLifecycleEvent(sink, eventName, payload);
    });

    this.hosts.clear();
  }

  private requireHost(hostKey: number): ExpoLifecycleHostEntry {
    const entry: ExpoLifecycleHostEntry | undefined = this.hosts.get(hostKey);
    if (entry === undefined) {
      throw new Error(`Cannot find Expo lifecycle Host '${hostKey}'.`);
    }
    return entry;
  }

  private assertValid(): void {
    if (!this.valid) throw new Error('The Expo lifecycle Ability scope was destroyed.');
  }
}

function deliverLifecycleEvent(
  sink: ExpoLifecycleSink,
  eventName: string,
  payload?: ESObject,
): void {
  try {
    sink.postLifecycleEvent(eventName, payload);
  } catch (error) {
    try {
      console.error(`Expo lifecycle sink failed during '${eventName}': ${String(error)}`);
    } catch (_) {}
  }
}

/** Routes lifecycle events by UIAbility context. */
export class ExpoLifecycleScopeRegistry<ScopeKey> {
  private readonly scopes: Map<ScopeKey, ExpoLifecycleChannel> =
    new Map<ScopeKey, ExpoLifecycleChannel>();

  openScope(scopeKey: ScopeKey): ExpoLifecycleChannel {
    if (this.scopes.has(scopeKey)) {
      throw new Error('The Expo lifecycle Ability scope is already open.');
    }
    const scope = new ExpoLifecycleChannel();
    this.scopes.set(scopeKey, scope);
    return scope;
  }

  ensureScope(scopeKey: ScopeKey): ExpoLifecycleChannel {
    const current: ExpoLifecycleChannel | undefined = this.scopes.get(scopeKey);
    return current ?? this.openScope(scopeKey);
  }

  scope(scopeKey: ScopeKey): ExpoLifecycleChannel | undefined {
    return this.scopes.get(scopeKey);
  }

  closeScope(scopeKey: ScopeKey, eventName: string, payload?: ESObject): void {
    const scope: ExpoLifecycleChannel | undefined = this.scopes.get(scopeKey);
    if (scope === undefined) return;
    this.scopes.delete(scopeKey);
    scope.close(eventName, payload);
  }
}
