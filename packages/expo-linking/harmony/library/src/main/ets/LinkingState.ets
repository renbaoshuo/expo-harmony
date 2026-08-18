/**
 * Pure URL transition owner for one UIAbility. EntryAbility records lifecycle
 * transitions before ExpoModulesCore broadcasts them; each runtime then reads
 * this owner to reject broadcasts that belong to another UIAbility.
 */
export class AbilityLinkingState {
  private launch: string | null;
  private current: string | null;
  private revision: number;
  private readonly events: DispatchedLinkingEvent[] = [];
  private readonly runtimes: Set<number> = new Set();
  private destroyed: boolean = false;

  constructor(launch: string | null) {
    this.launch = launch;
    this.current = launch;

    this.revision = launch === null ? 0 : 1;
  }

  getInitialURL(): string | null {
    return this.destroyed ? null : this.launch;
  }

  getURL(): string | null {
    return this.destroyed ? null : this.current;
  }

  getRevision(): number {
    return this.revision;
  }

  registerRuntime(id: number): void {
    if (!this.destroyed) this.runtimes.add(id);
  }

  unregisterRuntime(id: number): void {
    this.runtimes.delete(id);
    this.events.forEach((event) => event.acknowledge(id));

    this.pruneAcknowledgedEvents();
  }

  recordNewWant(url: string | null): boolean {
    if (this.destroyed) return false;

    if (url === null) {
      // Empty Wants never become React Native or Expo Linking URL events.
      // EntryAbility still forwards them to the shared lifecycle dispatcher.
      return false;
    }

    this.current = url;
    this.revision += 1;

    // Retain a warm event only for runtimes that existed when the Ability
    // received it. Each runtime acknowledges from its matching NEW_INTENT
    // callback; teardown also acknowledges, so the queue is bounded by actual
    // in-flight lifecycle work rather than an arbitrary lossy event cap.
    if (this.runtimes.size > 0) {
      this.events.push(new DispatchedLinkingEvent(url, this.revision, this.runtimes));
    }

    return true;
  }

  takeDispatchedRevision(id: number, url: string, after: number): number | null {
    if (this.destroyed) return null;

    for (let index = 0; index < this.events.length; index += 1) {
      const event = this.events[index];
      if (event.isPending(id) && event.revision > after && event.url === url) {
        event.acknowledge(id);
        this.pruneAcknowledgedEvents();

        return event.revision;
      }
    }
    return null;
  }

  clear(): number {
    if (this.destroyed) return this.revision;

    this.current = null;
    this.revision += 1;

    return this.revision;
  }

  destroy(): void {
    if (this.destroyed) return;

    this.launch = null;
    this.current = null;
    this.events.length = 0;
    this.runtimes.clear();

    this.revision += 1;
    this.destroyed = true;
  }

  isDestroyed(): boolean {
    return this.destroyed;
  }

  private pruneAcknowledgedEvents(): void {
    for (let index = this.events.length - 1; index >= 0; index -= 1) {
      if (!this.events[index].hasPendingRuntimes()) {
        this.events.splice(index, 1);
      }
    }
  }
}

class DispatchedLinkingEvent {
  readonly url: string;
  readonly revision: number;
  private readonly pending: Set<number>;

  constructor(url: string, revision: number, ids: Set<number>) {
    this.url = url;
    this.revision = revision;
    this.pending = new Set(ids);
  }

  isPending(id: number): boolean {
    return this.pending.has(id);
  }

  acknowledge(id: number): void {
    this.pending.delete(id);
  }

  hasPendingRuntimes(): boolean {
    return this.pending.size > 0;
  }
}
