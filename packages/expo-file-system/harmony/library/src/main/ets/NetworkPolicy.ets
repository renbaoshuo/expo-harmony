import { ExpoModuleError } from '@expo-harmony/expo-modules-core';

export const PROGRESS_EVENT_INTERVAL_MS: number = 100;

export class ExpoFileSystemError extends ExpoModuleError {
  constructor(code: string, message?: string, cause?: Object) {
    super(code, message ?? code, cause);
  }
}

export function asFileSystemError(error: Object, code: string = 'ERR_FILE_SYSTEM'): ExpoModuleError {
  if (error instanceof ExpoModuleError) return error;
  const message = error instanceof Error ? error.message : String(error);
  return new ExpoFileSystemError(code, message, error);
}

export interface ContentRange {
  start: number;
  end: number;
  total: number;
}

export function parseContentRange(value: string | null): ContentRange | null {
  if (value === null) return null;
  const match = /^bytes\s+(\d+)-(\d+)\/(\d+|\*)$/i.exec(value.trim());
  if (match === null) return null;
  const start = Number(match[1]);
  const end = Number(match[2]);
  const total = match[3] === '*' ? -1 : Number(match[3]);
  if (
    !Number.isSafeInteger(start) ||
    !Number.isSafeInteger(end) ||
    start < 0 ||
    end < start ||
    (total !== -1 && (!Number.isSafeInteger(total) || total <= end))
  )
    return null;
  return { start, end, total };
}

export function isRedirectStatus(status: number): boolean {
  return status === 301 || status === 302 || status === 303 || status === 307 || status === 308;
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
  return { method, standard: method !== 'PATCH' };
}

export class ProgressCadence {
  private lastEmittedAt?: number;
  private lastTransferred?: number;
  private lastExpected?: number;

  shouldEmit(now: number, transferred: number, expected: number, force: boolean = false): boolean {
    if (force && this.lastTransferred === transferred && this.lastExpected === expected) return false;

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
