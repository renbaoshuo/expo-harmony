import path from 'node:path';

function isInside(root: string, target: string): boolean {
  const relative = path.relative(root, target);

  return relative === ''
    || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

function toPosixPath(value: string): string {
  return value.split(path.sep).join('/');
}

function assertSafeRelative(relative: string, label: string): string {
  const segments = typeof relative === 'string' ? relative.split('/') : [];
  const native = segments.join(path.sep);

  if (!relative || relative.includes('\\') || relative.includes('\0')
    || segments.some(segment => !segment || segment === '.' || segment === '..')
    || path.isAbsolute(native)) {
    throw new Error(`${label} contains an unsafe path.`);
  }

  return native;
}

export { assertSafeRelative, isInside, toPosixPath };
