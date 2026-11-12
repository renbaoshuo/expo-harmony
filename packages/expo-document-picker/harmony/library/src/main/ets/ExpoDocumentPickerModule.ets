/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoModuleError, fileUriFromPath, resolveFileReadSource } from '@expo-harmony/expo-modules-core';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { DOCUMENT_PICKER_OPTIONS, DocumentPickerOptions } from './DocumentPickerOptions';
import { filenameExtension, mimeTypeForName, suffixFilters } from './DocumentPickerTypes';

const MILLISECONDS_PER_SECOND: number = 1000;
const NANOSECONDS_PER_MILLISECOND: bigint = 1000000n;
// The system picker can outlive a React Native runtime in the same ability.
const activePickers: WeakSet<common.UIAbilityContext> = new WeakSet();

interface DocumentPickerAsset {
  uri: string;
  name: string;
  size?: number;
  mimeType?: string;
  lastModified: number;
}

interface DocumentPickerResult {
  canceled: boolean;
  assets: DocumentPickerAsset[] | null;
}

function lastModifiedMilliseconds(stat: fileIo.Stat): number {
  let modified = Date.now();
  try {
    const time = Math.trunc(stat.mtime * MILLISECONDS_PER_SECOND);
    if (Number.isSafeInteger(time)) modified = time;
  } catch (_) {}

  if (deviceInfo.sdkApiVersion >= 15) {
    try {
      const nanoseconds = stat.mtimeNs;
      if (nanoseconds !== undefined) {
        // The native getter exposes pre-epoch timestamps as unsigned 64-bit values.
        const signed = modified < 0 ? BigInt.asIntN(64, nanoseconds) : nanoseconds;
        const time = Number(signed / NANOSECONDS_PER_MILLISECOND);
        if (Number.isSafeInteger(time)) modified = time;
      }
    } catch (_) {}
  }

  return modified;
}

export class ExpoDocumentPickerModule extends ExpoModule {
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoDocumentPicker')
      .asyncFunction(
        'getDocumentAsync',
        ExpoFunction.typed1(DOCUMENT_PICKER_OPTIONS, (options: DocumentPickerOptions): Promise<DocumentPickerResult> => this.pick(options)),
      )
      .onPrepareForReload(async (): Promise<void> => {
        this.destroyed = true;
      })
      .onDestroy((): void => {
        this.destroyed = true;
      })
      .onAbilityDestroy((): void => {
        this.destroyed = true;
      });
  }

  private async pick(options: DocumentPickerOptions): Promise<DocumentPickerResult> {
    this.assertActive();

    const ability = this.context.isHeadless ? undefined : this.context.uiAbilityContext;
    if (ability !== undefined && activePickers.has(ability)) {
      throw new ExpoModuleError('ERR_PICKING_IN_PROGRESS', 'Different document picking in progress. Await other document picking first.');
    }
    if (options.type.length === 0) {
      throw new ExpoModuleError('ERR_DOCUMENT_PICKER_OPTIONS_EMPTY_LIST', "The 'type' argument must be a non-empty array.");
    }
    if (ability === undefined) {
      throw new ExpoModuleError('ERR_DOCUMENT_PICKER_UNAVAILABLE', 'Document picking requires a UIAbility.');
    }

    activePickers.add(ability);
    let directory: string | undefined;

    try {
      const selection = new picker.DocumentSelectOptions();
      if (!options.multiple) selection.maxSelectNumber = 1;
      selection.fileSuffixFilters = suffixFilters(options.type);

      let uris: string[];

      try {
        uris = await new picker.DocumentViewPicker(ability).select(selection);
      } catch (error) {
        this.assertActive();

        throw new ExpoModuleError('ERR_DOCUMENT_PICKER_FAILED', `HarmonyOS document selection failed: ${(error as BusinessError).message}`, error);
      }

      this.assertActive();
      if (uris.length === 0) return { canceled: true, assets: null };

      try {
        if (options.copyToCacheDirectory) {
          // mkdtemp requires six trailing Xs and reserves the directory atomically.
          directory = await fileIo.mkdtemp(`${this.context.cachePath}/DocumentPicker-XXXXXX`);
          this.assertActive();
        }

        const assets: DocumentPickerAsset[] = [];
        const grants = new Set<string>();
        const selected = options.multiple ? uris : uris.slice(0, 1);

        for (const uri of selected) {
          assets.push(await this.readAsset(uri, grants, directory));
          this.assertActive();
        }

        for (const source of grants) this.context.grantFileAccess(source, false, false);

        return { canceled: false, assets };
      } catch (error) {
        if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause);

        throw new ExpoModuleError('ERR_FAILED_TO_READ_DOCUMENT', 'Failed to read the selected document.', error);
      }
    } catch (error) {
      if (directory !== undefined) {
        try {
          await fileIo.rmdir(directory);
        } catch (failure) {
          if (this.context.isValid) this.context.logger.warn(`Unable to remove document picker cache: ${(failure as BusinessError).message}`);
        }
      }

      if (error instanceof ExpoModuleError) throw new ExpoModuleError(error.code, error.message, error.cause);

      throw new ExpoModuleError('ERR_DOCUMENT_PICKER_FAILED', 'Unable to prepare the HarmonyOS document picker.', error);
    } finally {
      activePickers.delete(ability);
    }
  }

  private async readAsset(uri: string, grants: Set<string>, directory?: string): Promise<DocumentPickerAsset> {
    this.assertActive();

    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);

    try {
      this.assertActive();

      const stat = await fileIo.stat(file.fd);
      if (!stat.isFile()) throw new ExpoModuleError('ERR_FAILED_TO_READ_DOCUMENT', 'The selected document is not a regular file.');

      const name = file.name;
      if (name.length === 0 || /[/\0]/.test(name)) {
        throw new ExpoModuleError('ERR_FAILED_TO_READ_DOCUMENT', 'The selected document has an invalid filename.');
      }

      this.assertActive();

      let target = uri;
      let size = documentSize(stat);
      if (directory !== undefined) {
        const path = `${directory}/${util.generateRandomUUID()}${filenameExtension(name)}`;

        await fileIo.copyFile(file.fd, path);
        // Providers can materialize or change a file after the first fstat.
        size = documentSize(await fileIo.stat(path));
        target = fileUriFromPath(path);
      } else {
        grants.add(resolveFileReadSource(uri, this.context.uiAbilityContext.cacheDir));
      }

      const asset: DocumentPickerAsset = { uri: target, name, lastModified: lastModifiedMilliseconds(stat) };
      if (size !== undefined) asset.size = size;

      const mime = mimeTypeForName(name);
      if (mime !== undefined) asset.mimeType = mime;

      return asset;
    } finally {
      try {
        await fileIo.close(file.fd);
      } catch (error) {
        if (this.context.isValid) this.context.logger.warn(`Unable to close a picked document: ${(error as BusinessError).message}`);
      }
    }
  }

  private assertActive(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_DOCUMENT_PICKER_DESTROYED', 'The document picker runtime has been destroyed.');
    }
  }
}

function documentSize(stat: fileIo.Stat): number | undefined {
  try {
    const size = stat.size;
    if (Number.isSafeInteger(size) && size >= 0) return size;
  } catch (_) {}
  return undefined;
}
