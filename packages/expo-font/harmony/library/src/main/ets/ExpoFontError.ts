export class ExpoFontError extends Error {
  readonly code: string;

  constructor(code: string, msg: string) {
    super(msg);
    this.name = 'ExpoFontError';
    this.code = code;
  }
}
