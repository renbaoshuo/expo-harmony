export class ExpoHarmonyMetroError extends Error {
  readonly code: string;

  constructor(code: string, message: string, options?: ErrorOptions) {
    super(message, options);

    this.name = 'ExpoHarmonyMetroError';
    this.code = code;
  }
}
