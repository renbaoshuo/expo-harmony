/** Encodes an absolute local path as an authority-free file URI for use between Expo modules. */
export function fileUriFromPath(path: string): string {
  if (!path.startsWith('/')) {
    throw new Error('A file path must be absolute.');
  }

  // Harmony's getUriFromPath can add a bundle/provider authority; reserve it for system APIs.
  return `file://${path
    .split('/')
    .map((segment: string): string =>
      encodeURIComponent(segment).replace(/[!'()*]/g, (character: string): string => `%${character.charCodeAt(0).toString(16).toUpperCase()}`),
    )
    .join('/')}`;
}

export function filePathFromUri(uri: string): string {
  const match = /^file:\/\/([^/?#]*)(\/[^?#]*)$/i.exec(uri);
  if (match === null || (match[1].length > 0 && match[1].toLowerCase() !== 'localhost')) {
    throw new Error('Expected an authority-free local file URI without query or fragment.');
  }

  const path = decodeURIComponent(match[2]);
  if (path.includes('\0')) throw new Error('A file URI cannot contain a NUL character.');

  return path;
}

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

  const value = fileUriFromPath(path);
  return value.endsWith('/') ? value : `${value}/`;
}
