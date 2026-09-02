/** Converts a platform path to a correctly escaped directory file URI. */
export function ensureDirectoryUri(path: string): string {
  if (path.length === 0) {
    throw new Error('A directory path cannot be empty.');
  }

  if (path.startsWith('file:')) {
    return path.endsWith('/') ? path : `${path}/`;
  }
  if (!path.startsWith('/')) {
    throw new Error('A directory path must be absolute.');
  }

  // Build a portable file URI instead of relying on Harmony's authority handling.
  const value: string = `file://${path
    .split('/')
    .map((segment: string): string =>
      encodeURIComponent(segment).replace(/[!'()*]/g, (character: string): string => `%${character.charCodeAt(0).toString(16).toUpperCase()}`),
    )
    .join('/')}`;
  return value.endsWith('/') ? value : `${value}/`;
}
