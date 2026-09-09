import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
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

export async function outputPath(cacheDir: string, job: boolean = false): Promise<string> {
  const dir = `${cacheDir}/Print${job ? '/jobs' : ''}`;
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
      const data = bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength);
      const count = await fileIo.write(file.fd, data);
      if (count <= 0) throw new Error('Unable to write the PDF file.');
      offset += count;
    }
  } finally {
    await fileIo.close(file);
  }
}

export async function materializePdf(source: string, path: string, requests: Set<http.HttpRequest>, assertActive: () => void): Promise<void> {
  try {
    assertActive();
    const parsed = new uri.URI(source);
    // URI's SDK types say string, but absent components are null at runtime.
    const scheme = (parsed.scheme ?? '').toLowerCase();

    if (scheme === 'http' || scheme === 'https') {
      await downloadPdf(parsed.toString(), path, requests, assertActive);
    } else if (scheme === 'data') {
      const comma = source.indexOf(',');
      const metadata = source.slice(5, comma).toLowerCase().split(';');
      if (comma < 0 || metadata[0] !== 'application/pdf' || metadata[metadata.length - 1] !== 'base64') {
        throw new Error('Expected a base64 application/pdf data URI.');
      }

      const bytes = await new util.Base64Helper().decode(decodeURIComponent(source.slice(comma + 1)));
      assertActive();
      await writeBytes(path, bytes);
    } else {
      let inputPath = source;
      if (scheme === 'file') {
        if (parsed.query || parsed.fragment) throw new Error('File URIs must not contain a query or fragment.');
        if (parsed.path?.includes('\0')) throw new Error('File paths must not contain a NUL character.');
        // Keep provider authorities for DocumentPicker grants. URI.path is already percent-decoded;
        // decoding again changes literal percent escapes in filenames (for example %2520).
        if (!parsed.authority || parsed.authority.toLowerCase() === 'localhost') {
          inputPath = parsed.path ?? '';
          if (!inputPath.startsWith('/')) throw new Error('A local file URI must contain an absolute path.');
        }
      } else if (scheme.length > 0 || !source.startsWith('/')) {
        throw new Error('Expected an HTTP(S), file, or PDF data URI.');
      }
      if (inputPath.includes('\0')) throw new Error('File paths must not contain a NUL character.');

      const input = await fileIo.open(inputPath, fileIo.OpenMode.READ_ONLY);
      try {
        assertActive();
        if (!(await fileIo.stat(input.fd)).isFile()) throw new Error('The URI must refer to a file.');
        await fileIo.copyFile(input.fd, path);
      } finally {
        await fileIo.close(input);
      }
    }

    await assertPdfFile(path);
  } catch (error) {
    await removeFile(path);
    if (error instanceof ExpoModuleError) {
      throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
    }

    // HttpRequest.destroy() rejects with a platform error, so recheck lifecycle cancellation.
    assertActive();
    throw new ExpoModuleError('ERR_PRINT_CANNOT_LOAD_URI', 'Unable to load the PDF URI.', error as Object);
  }
}

async function downloadPdf(source: string, path: string, requests: Set<http.HttpRequest>, assertActive: () => void): Promise<void> {
  const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  let client: http.HttpRequest | undefined;
  let failure: Error | undefined;
  try {
    assertActive();
    client = http.createHttp();
    requests.add(client);
    client.on('dataReceive', (buffer: ArrayBuffer): void => {
      if (failure !== undefined) return;
      try {
        // Write synchronously to preserve chunk order without buffering the entire PDF.
        let offset = 0;
        while (offset < buffer.byteLength) {
          const count = fileIo.writeSync(file.fd, buffer.slice(offset));
          if (count <= 0) throw new Error('Unable to write downloaded PDF data.');
          offset += count;
        }
      } catch (error) {
        failure = new Error(`Unable to save downloaded PDF: ${(error as Error).message}`);
        client?.destroy();
      }
    });

    const status = await client.requestInStream(source, {
      method: http.RequestMethod.GET,
      connectTimeout: NETWORK_TIMEOUT_MS,
      readTimeout: NETWORK_TIMEOUT_MS,
      usingCache: false,
    });
    if (failure !== undefined) throw new Error(failure.message);
    if (status < 200 || status >= 300) throw new Error(`PDF request failed with HTTP status ${status}.`);
  } finally {
    if (client !== undefined) requests.delete(client);
    try {
      client?.off('dataReceive');
    } catch (_) {}
    try {
      client?.destroy();
    } catch (_) {}
    await fileIo.close(file);
  }
}

async function assertPdfFile(path: string): Promise<void> {
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

  // A system print job can outlive the RN runtime. This closure owns its cache file independently.
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
