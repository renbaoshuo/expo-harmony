/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoServiceKey } from './ExpoServicesRegistry';
import fs from '@ohos.file.fs';

export type ExpoFileAccessMode = 'read' | 'write';

export interface ExpoFileAccessPolicy {
  /** Read checks for a provider-backed file receive its original URI. */
  assertAccess(path: string, mode: ExpoFileAccessMode): void;

  /** Provider grants use the original URI rather than the provider's projected path. */
  grantExternalPath(path: string, directory: boolean, writable: boolean): void;
}

export const ExpoFileAccessKey = new ExpoServiceKey<ExpoFileAccessPolicy>('ExpoFileAccessPolicy');

export type ExpoFileAccessHandler = (path: string, mode: ExpoFileAccessMode, policy?: ExpoFileAccessPolicy) => boolean | undefined;

export class ExpoFileAccessRegistry {
  private static readonly handlers: Map<number, Set<ExpoFileAccessHandler>> = new Map();

  static assertAccess(id: number | undefined, path: string, mode: ExpoFileAccessMode, policy?: ExpoFileAccessPolicy): boolean {
    const granted = id === undefined ? undefined : ExpoFileAccessRegistry.check(id, path, mode, policy);
    if (granted === false) throw new Error('The file access policy denied this operation.');
    if (granted === true) return true;

    policy?.assertAccess(path, mode);

    return policy !== undefined;
  }

  static assertReadDescriptor(
    id: number | undefined, source: string, file: fs.File, policy?: ExpoFileAccessPolicy,
  ): string {
    if (!source.startsWith('/')) return source;

    // File.path can resolve the original path again. dup starts from the already opened descriptor.
    const duplicate = fs.dup(file.fd);
    try {
      const path = duplicate.path;
      if (fs.statSync(duplicate.fd).ino !== fs.statSync(path).ino) {
        throw new Error('The opened file no longer matches its resolved path.');
      }
      if (path !== source) ExpoFileAccessRegistry.assertAccess(id, path, 'read', policy);

      return path;
    } finally {
      fs.closeSync(duplicate.fd);
    }
  }

  static register(id: number, handler: ExpoFileAccessHandler): () => void {
    let handlers = ExpoFileAccessRegistry.handlers.get(id);
    if (handlers === undefined) {
      handlers = new Set();
      ExpoFileAccessRegistry.handlers.set(id, handlers);
    }
    handlers.add(handler);

    return (): void => {
      const handlers = ExpoFileAccessRegistry.handlers.get(id);
      handlers?.delete(handler);
      if (handlers?.size === 0) ExpoFileAccessRegistry.handlers.delete(id);
    };
  }

  static check(id: number, path: string, mode: ExpoFileAccessMode, policy?: ExpoFileAccessPolicy): boolean | undefined {
    const handlers = ExpoFileAccessRegistry.handlers.get(id);
    if (handlers === undefined) return undefined;

    let granted: boolean | undefined;

    for (const handler of handlers) {
      const result = handler(path, mode, policy);
      if (result === false) return false;
      if (result === true) granted = true;
    }

    return granted;
  }
}
