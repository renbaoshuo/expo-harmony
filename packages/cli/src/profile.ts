export async function timedAsync<T>(
  steps: Record<string, number>,
  name: string,
  operation: () => Promise<T> | T
): Promise<T> {
  const started = performance.now();

  try {
    return await operation();
  } finally {
    steps[name] = Math.max(0, Math.round(performance.now() - started));
  }
}
