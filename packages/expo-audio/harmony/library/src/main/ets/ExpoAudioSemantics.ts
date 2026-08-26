const MILLISECONDS_PER_SECOND: number = 1000;

export function uriScheme(uri: string): string | undefined {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(uri);

  return match?.[1].toLowerCase();
}

export function isRemoteAudioUri(uri: string): boolean {
  const scheme = uriScheme(uri);

  return scheme === 'http' || scheme === 'https';
}

export function isDataAudioUri(uri: string): boolean {
  return uriScheme(uri) === 'data';
}

export function isPackagedAudioUri(uri: string): boolean {
  const scheme = uriScheme(uri);

  return scheme === 'asset' || scheme === 'rawfile';
}

export function packagedAudioResourceName(uri: string): string {
  const scheme = uriScheme(uri);
  const raw = uri
    .replace(/^(?:asset|rawfile):\/\//i, '')
    .replace(/^\/+/, '')
    .split(/[?#]/, 1)[0];

  let decoded: string;
  try {
    decoded = decodeURIComponent(raw).replace(/\\/g, '/');
  } catch (_) {
    throw new Error('The packaged audio URI contains invalid URL escaping.');
  }

  const parts = decoded.split('/');
  if (
    (scheme !== 'asset' && scheme !== 'rawfile') ||
    parts.length === 0 ||
    parts.some((part: string): boolean => part.length === 0 || part === '.' || part === '..' || part.includes('\0'))
  ) {
    throw new Error('The packaged audio URI path is invalid.');
  }

  const path = parts.join('/');

  return scheme === 'asset' ? `assets/${path}` : path;
}

export function effectivePlaying(playing: boolean, buffering: boolean, intendedPlaying: boolean): boolean {
  return playing || (buffering && intendedPlaying);
}

export function seekTargetMilliseconds(seconds: number, durationMilliseconds: number): number {
  const duration = Number.isSafeInteger(durationMilliseconds) && durationMilliseconds > 0
    ? durationMilliseconds
    : Number.MAX_SAFE_INTEGER;
  const maximumSeconds = duration / MILLISECONDS_PER_SECOND;

  if (!Number.isFinite(seconds)) return seconds > 0 ? duration : 0;
  if (seconds <= 0) return 0;
  if (seconds >= maximumSeconds) return duration;

  return Math.round(seconds * MILLISECONDS_PER_SECOND);
}

export function nextPlaylistIndex(index: number, count: number, loopAll: boolean): number {
  if (index + 1 < count) return index + 1;

  return loopAll && count > 0 ? 0 : -1;
}

export function previousPlaylistIndex(index: number, count: number, loopAll: boolean): number {
  if (index > 0 && index < count) return index - 1;

  return loopAll && count > 0 ? count - 1 : -1;
}

export function isSupportedRecordingExtension(extension: string): boolean {
  const value = extension.trim().toLowerCase().replace(/^\./, '');

  return value === 'm4a' || value === 'mp3';
}
