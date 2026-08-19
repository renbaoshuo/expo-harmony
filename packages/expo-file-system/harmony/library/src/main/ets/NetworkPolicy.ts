export const PROGRESS_EVENT_INTERVAL_MS: number = 100;

export class ExpoFileSystemError extends Error {
  constructor(code: string, msg?: string) {
    super(msg === undefined ? code : `${code}: ${msg}`);
  }
}

export function normalizeUploadMethod(value?: string): string {
  const method = (value ?? 'POST').toUpperCase();

  if (method !== 'POST' && method !== 'PUT' && method !== 'PATCH') {
    throw new ExpoFileSystemError('ERR_FILE_SYSTEM_HTTP_METHOD', method);
  }

  return method;
}

export interface UploadMethodPolicy {
  method: string;
  standard: boolean;
}

export function uploadMethodPolicy(value?: string): UploadMethodPolicy {
  const method = normalizeUploadMethod(value);
  // Harmony's RequestMethod enum has POST and PUT, but PATCH is available only
  // through NetStack's API 23 customMethod field.
  return { method, standard: method !== 'PATCH' };
}

export class ProgressCadence {
  private lastEmittedAt?: number;
  private lastTransferred?: number;
  private lastExpected?: number;

  shouldEmit(
    now: number,
    transferred: number,
    expected: number,
    force: boolean = false
  ): boolean {
    if (force && this.lastTransferred === transferred && this.lastExpected === expected) {
      return false;
    }

    if (!force && this.lastEmittedAt !== undefined) {
      const elapsed = now - this.lastEmittedAt;
      if (elapsed >= 0 && elapsed < PROGRESS_EVENT_INTERVAL_MS) return false;
    }

    this.lastEmittedAt = now;
    this.lastTransferred = transferred;
    this.lastExpected = expected;
    return true;
  }
}
