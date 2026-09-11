export type Log = Pick<Console, 'error' | 'log' | 'warn'>;

export function progress(options: { io?: Log }, message: string): void {
  options.io?.log(`› ${message}`);
}
