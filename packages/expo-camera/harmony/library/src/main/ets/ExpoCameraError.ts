export class ExpoCameraError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'ExpoCameraError';
    this.code = code;
  }
}
