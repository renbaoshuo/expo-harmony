import type { AutolinkingErrorJson, Diagnostic } from './types';

const ErrorPrefix = 'ERR_EXPO_HARMONY_';

interface HarmonyAutolinkingErrorDetails {
  cause?: unknown;
  stage?: string;
  packageName?: string;
  diagnostics?: ReadonlyArray<Diagnostic>;
  details?: unknown;
}

class HarmonyAutolinkingError extends Error {
  readonly code: string;
  readonly stage: string;
  readonly packageName?: string;
  readonly diagnostics?: ReadonlyArray<Diagnostic>;
  readonly details?: unknown;

  constructor(code: string, message: string, details: HarmonyAutolinkingErrorDetails = {}) {
    const value = code.startsWith(ErrorPrefix) ? code : `${ErrorPrefix}${code}`;

    super(message, details.cause ? { cause: details.cause } : undefined);
    this.name = 'HarmonyAutolinkingError';
    this.code = value;
    this.stage = details.stage || 'unknown';
    this.packageName = details.packageName;
    this.diagnostics = details.diagnostics;
    this.details = details.details;
    Error.captureStackTrace?.(this, HarmonyAutolinkingError);
  }

  toJSON(): AutolinkingErrorJson {
    const value: AutolinkingErrorJson = {
      name: 'HarmonyAutolinkingError' as const,
      code: this.code,
      message: this.message,
      stage: this.stage,
      ...(this.packageName ? { packageName: this.packageName } : {}),
      ...(this.diagnostics ? { diagnostics: this.diagnostics } : {}),
      ...(this.details ? { details: this.details } : {}),
    };

    return value;
  }
}

export { HarmonyAutolinkingError };
