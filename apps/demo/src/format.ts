export function json(value: unknown): string {
  return JSON.stringify(value, null, 2);
}
