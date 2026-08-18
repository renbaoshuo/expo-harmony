export class ExpoFetchError extends Error {
  readonly code: string;

  constructor(code: string, msg: string) {
    super(`${code}: ${msg}`);
    this.name = 'ExpoFetchError';
    this.code = code;
  }
}
