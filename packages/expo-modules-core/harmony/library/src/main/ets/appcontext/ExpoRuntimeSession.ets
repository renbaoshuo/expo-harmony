import type { Want } from '@kit.AbilityKit';

export class ExpoRuntimeSession {
  readonly projectId: string;
  readonly initialWant: Want | undefined;
  private closed: boolean = false;
  private readonly cleanup: Set<() => void> = new Set<() => void>();

  constructor(projectId: string, initialWant: Want | null = null) {
    if (projectId.length === 0) throw new Error('Expo session project ID cannot be empty.');

    this.projectId = projectId;
    this.initialWant = initialWant === null ? undefined : (JSON.parse(JSON.stringify(initialWant)) as Want);
  }

  assertOpen(): void {
    if (this.closed) throw new Error('The Expo project session is closed.');
  }

  get isOpen(): boolean {
    return !this.closed;
  }

  onClose(cleanup: () => void): () => void {
    this.assertOpen();
    this.cleanup.add(cleanup);

    return (): void => {
      this.cleanup.delete(cleanup);
    };
  }

  close(): void {
    if (this.closed) return;

    this.closed = true;
    this.cleanup.forEach((cleanup: () => void): void => {
      try {
        cleanup();
      } catch (error) {
        console.error(`Expo session cleanup failed: ${String(error)}`);
      }
    });

    this.cleanup.clear();
  }
}
