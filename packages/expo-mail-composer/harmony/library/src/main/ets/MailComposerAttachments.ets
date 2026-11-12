/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { fileIo, fileUri } from '@kit.CoreFileKit';

const EXTERNAL_ATTACHMENT_MESSAGE = 'Copy the attachment into the app sandbox before composing mail.';

export async function attachmentUri(value: string, context: ExpoModuleContext): Promise<string> {
  try {
    const path = context.filePathForRead(value);
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

    try {
      if (!(await fileIo.stat(file.fd)).isFile()) {
        throw new Error('The attachment must be a regular file.');
      }

      // Grant only a URI owned by the caller, including when it is an app clone.
      const ability = context.uiAbilityContext;
      const app = ability.getApplicationContext();
      const canonical = context.readPathForDescriptor(path, file);
      const roots = [
        ability.filesDir, ability.cacheDir, ability.tempDir, ability.distributedFilesDir,
        app.filesDir, app.cacheDir, app.tempDir, app.distributedFilesDir,
      ];
      if (!roots.some((root: string): boolean => root.length > 0 && canonical.startsWith(root.endsWith('/') ? root : `${root}/`))) {
        throw new Error(EXTERNAL_ATTACHMENT_MESSAGE);
      }

      // getUriFromPath also assigns the current bundle authority to paths
      // outside the shareable application directories, so check both.
      const authority = new fileUri.FileUri(ability.cacheDir).authority;
      const uri = fileUri.getUriFromPath(canonical);
      if (authority.length === 0 || !uri.startsWith(`file://${authority}/`)) {
        throw new Error(EXTERNAL_ATTACHMENT_MESSAGE);
      }

      return uri;
    } finally {
      try {
        await fileIo.close(file);
      } catch (error) {
        context.logger.warn(`Unable to close the mail attachment: ${(error as Error)?.message ?? String(error)}`);
      }
    }
  } catch (error) {
    throw new ExpoModuleError(
      'ERR_MAIL_COMPOSER_ATTACHMENT',
      `Unable to read the attachment: ${(error as Error)?.message ?? String(error)}`,
      error as Object,
    );
  }
}
