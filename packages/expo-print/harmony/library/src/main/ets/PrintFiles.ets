/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { fileIo } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { pdfService } from '@kit.PDFKit';
import { print } from '@kit.BasicServicesKit';
import lazy { rcp } from '@kit.RemoteCommunicationKit';
import uri from '@ohos.uri';
import { ORIENTATION_LANDSCAPE, ORIENTATION_PORTRAIT } from './PrintOptions';

const NETWORK_TIMEOUT_MS: number = 60_000;
// PDF readers permit the version header within the first 1024 bytes.
const PDF_HEADER_SCAN_BYTES: number = 1024;
const PDF_HEADER: string = '%PDF-';

export async function outputPath(cache: string, job: boolean = false): Promise<string> {
  const dir = `${cache}/Print${job ? '/jobs' : ''}`;
  try {
    await fileIo.mkdir(dir, true);
  } catch (error) {
    const stat = await fileIo.stat(dir).catch((): undefined => undefined);

    if (!stat?.isDirectory()) {
      throw new ExpoModuleError('ERR_PRINT_CACHE_DIRECTORY', 'Unable to create the print cache directory.', error as Object);
    }
  }

  return `${dir}/${util.generateRandomUUID(true)}.pdf`;
}

export async function removeFile(path: string): Promise<void> {
  try {
    await fileIo.unlink(path);
  } catch (_) {}
}

export async function writeBytes(path: string, bytes: Uint8Array): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);

  try {
    let offset = 0;
    while (offset < bytes.byteLength) {
      const data = offset === 0 && bytes.byteLength === bytes.buffer.byteLength
        ? bytes.buffer
        : bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength);
      const count = await fileIo.write(file.fd, data);
      if (count <= 0) throw new Error('Unable to write the PDF file.');
      offset += count;
    }
  } finally {
    await fileIo.close(file);
  }
}

export async function materializePdf(
  source: string,
  path: string,
  downloadCancels: Set<() => void>,
  assertActive: () => void,
  context: ExpoModuleContext,
): Promise<void> {
  try {
    assertActive();

    if (/^https?:/i.test(source)) {
      const address = new uri.URI(source);

      if (!address.host) throw new Error('A remote PDF URI must include a hostname.');
      if (!canIUse('SystemCapability.Collaboration.RemoteCommunication')) {
        throw new Error('This device does not support remote PDF downloads.');
      }

      await downloadPdf(address.toString(), path, downloadCancels);
    } else if (/^data:/i.test(source)) {
      const comma = source.indexOf(',');
      const metadata = source.slice(5, comma).toLowerCase().split(';');
      if (comma < 0 || metadata[0] !== 'application/pdf' || metadata[metadata.length - 1] !== 'base64') {
        throw new Error('Expected a base64 application/pdf data URI.');
      }

      const bytes = await new util.Base64Helper().decode(decodeURIComponent(source.slice(comma + 1)));
      assertActive();

      await writeBytes(path, bytes);
    } else {
      await copyLocalPdf(source, path, assertActive, context);
    }

    assertActive();

    if (canIUse('SystemCapability.OfficeService.PDFService.Core')) {
      await taskpool.execute(inspectPdf, path, true);
    } else {
      await assertPdfHeader(path);
    }

    assertActive();
  } catch (error) {
    if (error instanceof ExpoModuleError) {
      throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
    }

    assertActive();

    throw new ExpoModuleError('ERR_PRINT_CANNOT_LOAD_URI', 'Unable to load the PDF URI.', error as Object);
  }
}

async function copyLocalPdf(source: string, path: string, assertActive: () => void, context: ExpoModuleContext): Promise<void> {
  // Preserve the historical file:/path spelling as well as standard file URIs.
  const input = context.fileSourceForRead(/^file:\/(?!\/)/i.test(source) ? `file://${source.slice(5)}` : source);

  const file = await fileIo.open(input, fileIo.OpenMode.READ_ONLY | fileIo.OpenMode.NONBLOCK);
  try {
    assertActive();
    if (!(await fileIo.stat(file.fd)).isFile()) throw new Error('The URI must refer to a file.');

    assertActive();
    context.readPathForDescriptor(input, file);
    await fileIo.copyFile(file.fd, path);
  } finally {
    await fileIo.close(file);
  }
}

async function downloadPdf(
  source: string,
  path: string,
  downloadCancels: Set<() => void>,
): Promise<void> {
  const session = rcp.createSession({
    headers: { 'accept-encoding': 'gzip' },
    requestConfiguration: {
      transfer: { timeout: { connectMs: NETWORK_TIMEOUT_MS, transferMs: 0, inactivityMs: NETWORK_TIMEOUT_MS } },
    },
  });

  const cancel = (): void => {
    try {
      session.cancel();
    } catch (_) {}
  };
  downloadCancels.add(cancel);

  try {
    const response = await session.downloadToFile(source, { kind: 'file', file: path });
    const status = response.statusCode;

    if (status < 200 || status >= 300) throw new Error(`PDF request failed with HTTP status ${status}.`);
  } finally {
    downloadCancels.delete(cancel);

    try {
      session.close();
    } catch (_) {}
  }
}

async function assertPdfHeader(path: string): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);

  try {
    const buffer = new ArrayBuffer(PDF_HEADER_SCAN_BYTES);
    const count = await fileIo.read(file.fd, buffer);
    const bytes = new Uint8Array(buffer, 0, count);

    for (let offset = 0; offset + PDF_HEADER.length <= count; offset += 1) {
      let matches = true;
      for (let index = 0; index < PDF_HEADER.length; index += 1) {
        if (bytes[offset + index] !== PDF_HEADER.charCodeAt(index)) {
          matches = false;
          break;
        }
      }
      if (matches) return;
    }

    throw new Error('Only PDF documents can be printed.');
  } finally {
    await fileIo.close(file);
  }
}

@Concurrent
function inspectPdf(path: string, allowEncrypted: boolean): number {
  const document = new pdfService.PdfDocument();

  try {
    const status = document.loadDocument(path);
    if (status === pdfService.ParseResult.PARSE_SUCCESS) {
      return document.getPageCount();
    }
    if (allowEncrypted && (status === pdfService.ParseResult.PARSE_ERROR_PASSWORD || status === pdfService.ParseResult.PARSE_ERROR_CERT)) {
      return 0;
    }

    throw new Error(`PDF Kit could not open the document (${status}).`);
  } finally {
    document.releaseDocument();
  }
}

export async function pageCount(path: string): Promise<number> {
  try {
    const count = (await taskpool.execute(inspectPdf, path, false)) as number;
    if (!Number.isSafeInteger(count) || count <= 0) {
      throw new Error('PDF Kit returned an invalid page count.');
    }

    return count;
  } catch (error) {
    throw new ExpoModuleError('ERR_PRINT_PDF_PARSE', 'Unable to read the generated PDF page count.', error as Object);
  }
}

class PdfPrintAdapter implements print.PrintDocumentAdapter {
  private readonly path: string;
  private finished: boolean = false;
  private pendingWrites: number = 0;

  constructor(path: string) {
    this.path = path;
  }

  onStartLayoutWrite(
    jobId: string,
    _oldAttributes: print.PrintAttributes,
    _newAttributes: print.PrintAttributes,
    fd: number,
    complete: (jobId: string, state: print.PrintFileCreationState) => void,
  ): void {
    void this.write(jobId, fd, complete);
  }

  private async write(jobId: string, fd: number, complete: (jobId: string, state: print.PrintFileCreationState) => void): Promise<void> {
    let state = print.PrintFileCreationState.PRINT_FILE_CREATION_FAILED;

    if (!this.finished) {
      this.pendingWrites += 1;

      try {
        // The print service owns the destination descriptor.
        await fileIo.copyFile(this.path, fd);

        if (!this.finished) state = print.PrintFileCreationState.PRINT_FILE_CREATED;
      } catch (error) {
        console.warn(`Unable to provide the PDF to the print service: ${String(error)}`);
      } finally {
        this.pendingWrites -= 1;
        this.removeFinishedFile();
      }
    }

    try {
      complete(jobId, state);
    } catch (_) {
      // The preview may close during the copy.
    }
  }

  onJobStateChanged(_jobId: string, state: print.PrintDocumentAdapterState): void {
    if (this.finished) return;

    if (
      state !== print.PrintDocumentAdapterState.PREVIEW_DESTROY &&
      state !== print.PrintDocumentAdapterState.PRINT_TASK_SUCCEED &&
      state !== print.PrintDocumentAdapterState.PRINT_TASK_FAIL &&
      state !== print.PrintDocumentAdapterState.PRINT_TASK_CANCEL
    ) return;

    this.finished = true;
    this.removeFinishedFile();
  }

  private removeFinishedFile(): void {
    if (this.finished && this.pendingWrites === 0) void removeFile(this.path);
  }
}

export async function startPrint(path: string, context: Context, orientation?: string): Promise<void> {
  const attributes: print.PrintAttributes = {};
  if (orientation === ORIENTATION_LANDSCAPE) {
    attributes.directionMode = print.PrintDirectionMode.DIRECTION_MODE_LANDSCAPE;
  } else if (orientation === ORIENTATION_PORTRAIT) {
    attributes.directionMode = print.PrintDirectionMode.DIRECTION_MODE_PORTRAIT;
  }

  await print.print('Document.pdf', new PdfPrintAdapter(path), attributes, context);
}
