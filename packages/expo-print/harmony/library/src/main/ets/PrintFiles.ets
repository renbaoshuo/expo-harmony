/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { pdfService } from '@kit.PDFKit';
import { print } from '@kit.BasicServicesKit';
import uri from '@ohos.uri';

const NETWORK_TIMEOUT_MS: number = 60_000;
// PDF readers permit the version header within the first 1024 bytes.
const PDF_HEADER_SCAN_BYTES: number = 1024;
const PDF_HEADER: string = '%PDF-';

export async function outputPath(cache: string, job: boolean = false): Promise<string> {
  const dir = `${cache}/Print${job ? '/jobs' : ''}`;
  try {
    await fileIo.mkdir(dir, true);
  } catch (error) {
    if (!(await fileIo.stat(dir)).isDirectory()) {
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
  downloadCancels: Set<(error: ExpoModuleError) => void>,
  assertActive: () => void,
  context: ExpoModuleContext,
): Promise<void> {
  try {
    assertActive();

    if (/^https?:/i.test(source)) {
      await downloadPdf(new uri.URI(source).toString(), path, downloadCancels, assertActive);
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
    await assertPdfHeader(path);
    assertActive();
    if (canIUse('SystemCapability.OfficeService.PDFService.Core')) {
      const document = new pdfService.PdfDocument();
      try {
        const status = document.loadDocument(path);
        if (
          status !== pdfService.ParseResult.PARSE_SUCCESS &&
          status !== pdfService.ParseResult.PARSE_ERROR_PASSWORD &&
          status !== pdfService.ParseResult.PARSE_ERROR_CERT
        ) {
          throw new Error(`PDF Kit could not open the source PDF (${status}).`);
        }
      } finally {
        document.releaseDocument();
      }
    }
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
  downloadCancels: Set<(error: ExpoModuleError) => void>,
  assertActive: () => void,
): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  let client: http.HttpRequest | undefined;
  let cancel: (error: ExpoModuleError) => void = (): void => {};
  let stopped = false;

  try {
    assertActive();

    client = http.createHttp();
    const cancelled = new Promise<number>((_resolve: (status: number) => void, reject: (error: ExpoModuleError) => void): void => {
      cancel = (error: ExpoModuleError): void => {
        stopped = true;
        reject(error);
      };
    });
    downloadCancels.add(cancel);

    client.on('dataReceive', (buffer: ArrayBuffer): void => {
      if (stopped) return;

      try {
        // Synchronous writes preserve stream order without buffering the entire PDF.
        let offset = 0;
        while (offset < buffer.byteLength) {
          const count = fileIo.writeSync(file.fd, offset === 0 ? buffer : buffer.slice(offset));
          if (count <= 0) throw new Error('Unable to write downloaded PDF data.');
          offset += count;
        }
      } catch (error) {
        cancel(new ExpoModuleError('ERR_PRINT_CANNOT_LOAD_URI', 'Unable to save downloaded PDF data.', error as Object));
      }
    });

    // Destroying the request can leave its promise pending.
    const status = await Promise.race([
      cancelled,
      client.requestInStream(source, {
        method: http.RequestMethod.GET,
        connectTimeout: NETWORK_TIMEOUT_MS,
        readTimeout: NETWORK_TIMEOUT_MS,
        usingCache: false,
      }),
    ]);
    if (status < 200 || status >= 300) throw new Error(`PDF request failed with HTTP status ${status}.`);
  } finally {
    stopped = true;
    downloadCancels.delete(cancel);

    try {
      client?.off('dataReceive');
    } catch (_) {}
    try {
      client?.destroy();
    } catch (_) {}

    await fileIo.close(file);
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

export function pageCount(path: string): number {
  const document = new pdfService.PdfDocument();

  try {
    const status = document.loadDocument(path);
    if (status !== pdfService.ParseResult.PARSE_SUCCESS) {
      throw new ExpoModuleError('ERR_PRINT_PDF_PARSE', `PDF Kit could not open the generated PDF (${status}).`);
    }

    const count = document.getPageCount();
    if (!Number.isSafeInteger(count) || count <= 0) {
      throw new ExpoModuleError('ERR_PRINT_PDF_PARSE', 'PDF Kit returned an invalid page count.');
    }

    return count;
  } finally {
    document.releaseDocument();
  }
}

export async function startPrint(path: string, context: Context): Promise<void> {
  const task = await print.print([fileUri.getUriFromPath(path)], context);

  let finished = false;
  const detach = (): void => {
    try {
      task.off('succeed', finish);
    } catch (_) {}
    try {
      task.off('fail', finish);
    } catch (_) {}
    try {
      task.off('cancel', finish);
    } catch (_) {}
  };
  const finish = (): void => {
    if (finished) return;
    finished = true;
    detach();
    void removeFile(path);
  };

  // Register independently; if events fail, retain the file for the accepted system job.
  try {
    task.on('succeed', finish);
  } catch (_) {}
  if (!finished) {
    try {
      task.on('fail', finish);
    } catch (_) {}
  }
  if (!finished) {
    try {
      task.on('cancel', finish);
    } catch (_) {}
  }
}
