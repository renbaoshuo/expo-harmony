interface HarmonyPrebuildErrorOptions {
  cause?: unknown;
  file?: string;
  operation?: string;
}

class HarmonyPrebuildError extends Error {
  readonly code: string;
  readonly file?: string;
  readonly operation: string;

  constructor(code: string, message: string, options: HarmonyPrebuildErrorOptions = {}) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });

    this.name = 'HarmonyPrebuildError';
    this.code = code;
    this.operation = options.operation || 'prebuild';
    if (options.file) this.file = options.file;
  }
}

export { HarmonyPrebuildError };
export type { HarmonyPrebuildErrorOptions };
