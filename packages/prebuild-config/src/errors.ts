interface HarmonyPrebuildErrorOptions {
  cause?: unknown;
  file?: string;
  operation?: string;
  packageName?: string;
}

class HarmonyPrebuildError extends Error {
  readonly code: string;
  readonly file?: string;
  readonly operation: string;
  readonly packageName?: string;

  constructor(code: string, message: string, options: HarmonyPrebuildErrorOptions = {}) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = 'HarmonyPrebuildError';
    this.code = code;
    this.operation = options.operation || 'prebuild';
    if (options.file) this.file = options.file;
    if (options.packageName) this.packageName = options.packageName;
  }
}

class HarmonySigningError extends HarmonyPrebuildError {
  constructor(message: string, options: HarmonyPrebuildErrorOptions = {}) {
    super('ERR_HARMONY_SIGNING_INVALID', message, {
      ...options,
      operation: 'validate-signing',
    });
    this.name = 'HarmonySigningError';
  }
}

export { HarmonyPrebuildError, HarmonySigningError };
export type { HarmonyPrebuildErrorOptions };
