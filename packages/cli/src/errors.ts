interface HarmonyCliErrorOptions {
  cause?: unknown;
  exitCode?: number;
  operation?: string;
}

class HarmonyCliError extends Error {
  code: string;
  exitCode: number;
  operation: string;

  constructor(code: string, message: string, options: HarmonyCliErrorOptions = {}) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });

    this.name = 'HarmonyCliError';
    this.code = code;
    this.exitCode = options.exitCode || 1;
    this.operation = options.operation || 'cli';
  }
}

export { HarmonyCliError };
