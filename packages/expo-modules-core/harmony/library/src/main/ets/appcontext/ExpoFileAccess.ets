import type { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import type { ExpoRuntimeDirectories } from './ExpoRuntimeDirectories';
import { ExpoService, ExpoServiceKey } from './ExpoServicesRegistry';

export type ExpoFileAccessMode = 'read' | 'write';

export interface ExpoFileAccessPolicy {
  assertAccess(path: string, mode: ExpoFileAccessMode): void;

  grantExternalPath(path: string, directory: boolean, writable: boolean): void;
}

export const ExpoFileAccessKey = new ExpoServiceKey<ExpoFileAccessPolicy>('ExpoFileAccessPolicy');

class ExternalGrant {
  readonly path: string;
  readonly directory: boolean;
  readonly writable: boolean;

  constructor(path: string, directory: boolean, writable: boolean) {
    this.path = path;
    this.directory = directory;
    this.writable = writable;
  }
}

/**
 * Optional project policy. Harmony lacks a synchronous realpath API; reject all
 * symlink segments instead of following them. Never grant host data through a picker.
 */
export class ExpoScopedFileAccess extends ExpoService implements ExpoFileAccessPolicy {
  static readonly key = new ExpoServiceKey<ExpoScopedFileAccess>('ExpoScopedFileAccess');
  readonly identity = ExpoScopedFileAccess.key.bind(this);
  readonly interfaces = [ExpoFileAccessKey.bind(this)];

  private readonly roots: string[];
  private readonly protectedRoots: string[];
  private readonly grants: ExternalGrant[] = [];

  constructor(roots: string[], protectedRoots: string[]) {
    super();
    if (roots.length === 0 || protectedRoots.length === 0) throw new Error('Scoped file access requires project and host roots.');

    this.roots = roots.map((path: string): string => checkedFilePath(path));
    this.protectedRoots = protectedRoots.map((path: string): string => checkedFilePath(path));
  }

  static forContext(context: common.UIAbilityContext, directories: ExpoRuntimeDirectories): ExpoScopedFileAccess {
    const bases = [context.filesDir, context.cacheDir, context.tempDir];
    const roots = bases.map((path: string): string => directories.directory(path));

    const protectedRoots = bases.map((path: string): string => parentPath(path));
    protectedRoots.push(context.databaseDir, context.preferencesDir);

    const application = context.getApplicationContext();
    protectedRoots.push(parentPath(application.filesDir), parentPath(application.cacheDir), parentPath(application.tempDir), application.databaseDir, application.preferencesDir);

    return new ExpoScopedFileAccess(roots, protectedRoots);
  }

  assertAccess(path: string, mode: ExpoFileAccessMode): void {
    const canonical = checkedFilePath(path);
    if (this.roots.some((root: string): boolean => inside(root, canonical))) return;

    this.assertExternal(canonical);
    if (this.grants.some((grant: ExternalGrant): boolean =>
      (mode === 'read' || grant.writable) && (grant.directory ? inside(grant.path, canonical) : grant.path === canonical))) return;

    throw new Error('The project has no file access grant for this path.');
  }

  grantExternalPath(path: string, directory: boolean, writable: boolean): void {
    const canonical = checkedFilePath(path);
    if (this.roots.some((root: string): boolean => inside(root, canonical))) return;

    this.assertExternal(canonical);
    if (directory && this.protectedRoots.some((root: string): boolean => inside(canonical, root))) {
      throw new Error('A file grant cannot contain host data directories.');
    }

    this.grants.push(new ExternalGrant(canonical, directory, writable));
  }

  private assertExternal(path: string): void {
    if (this.protectedRoots.some((root: string): boolean => inside(root, path))) {
      throw new Error('The path belongs to the host or another project.');
    }
  }
}

function inside(root: string, path: string): boolean {
  return root === '/' || path === root || path.startsWith(`${root}/`);
}

function parentPath(path: string): string {
  const normalized = path.replace(/\/+$/, '');
  const slash = normalized.lastIndexOf('/');
  return slash <= 0 ? '/' : normalized.slice(0, slash);
}

function checkedFilePath(path: string): string {
  if (!path.startsWith('/') || path.includes('\0') || path.includes('\\')) throw new Error('Expected an absolute local file path.');

  // Inspect original segments before collapsing '..', including dangling links.
  const segments: string[] = [];
  for (const segment of path.split('/')) {
    if (segment === '' || segment === '.') continue;
    if (segment === '..') {
      if (segments.length === 0) throw new Error('File path escapes its root.');
      segments.pop();
      continue;
    }

    segments.push(segment);
    try {
      if (fs.lstatSync(`/${segments.join('/')}`).isSymbolicLink()) throw new Error('Symbolic links are not allowed by the project file policy.');
    } catch (error) {
      const code: ESObject = Reflect.get(error as Object, 'code');
      // Missing leaves are valid write destinations. Other failures deny access.
      if (code !== 13900002) throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  return `/${segments.join('/')}`;
}
