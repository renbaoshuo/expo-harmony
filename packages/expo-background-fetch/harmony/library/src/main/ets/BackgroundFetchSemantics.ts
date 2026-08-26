export function workIdentity(taskType: string, taskName: string): string {
  return `${taskType}:${taskName}`;
}

export function stableWorkId(value: string, minimum: number, maximum: number): number {
  const offsetBasis = 0x811c9dc5;
  const prime = 0x01000193;
  let hash = offsetBasis;

  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, prime);
  }

  const range = maximum - minimum + 1;

  return ((hash >>> 0) % range) + minimum;
}
