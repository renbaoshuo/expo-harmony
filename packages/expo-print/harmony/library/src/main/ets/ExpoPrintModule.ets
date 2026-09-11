import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  fileUriFromPath,
} from '@expo-harmony/expo-modules-core';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { materializePdf, outputPath, pageCount, removeFile, startPrint, writeBytes } from './PrintFiles';
import { PRINT_OPTIONS, PrintOptions } from './PrintOptions';
import { PrintRenderer } from './PrintRenderer';

class PrintResult {
  uri: string;
  numberOfPages: number;
  base64?: string;

  constructor(path: string, pages: number) {
    this.uri = fileUriFromPath(path);
    this.numberOfPages = pages;
  }
}

export class ExpoPrintModule extends ExpoModule {
  private destroyed: boolean = false;
  private generation: number = 0;
  private printing: boolean = false;
  private queue: Promise<void> = Promise.resolve();
  private renderers: Set<PrintRenderer> = new Set<PrintRenderer>();
  private requests: Set<http.HttpRequest> = new Set<http.HttpRequest>();

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoPrint')
      .constant('Orientation', { portrait: 'portrait', landscape: 'landscape' })
      .asyncFunction(
        'print',
        ExpoFunction.typed1(PRINT_OPTIONS, async (options: PrintOptions): Promise<void> => {
          await this.print(options);
        }),
      )
      .asyncFunction(
        'printToFileAsync',
        ExpoFunction.typed1(PRINT_OPTIONS, async (options: PrintOptions): Promise<PrintResult> => {
          return await this.printToFile(options);
        }),
      )
      .onBackground((): void => this.cancelPending('The application left the foreground.'))
      .onPrepareForReload(async (): Promise<void> => {
        this.destroy();
        await this.queue;
      })
      .onDestroy((): void => this.destroy());
  }

  private async print(options: PrintOptions): Promise<void> {
    const generation = this.generation;
    this.assertActive(generation);
    if (this.printing) throw new ExpoModuleError('ERR_PRINT_IN_PROGRESS', 'Another print request is already in progress.');
    if (!canIUse('SystemCapability.Print.PrintFramework')) {
      throw new ExpoModuleError('ERR_PRINT_UNAVAILABLE', 'This device does not support the HarmonyOS print framework.');
    }
    if (options.html === undefined && !options.uri) {
      throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', 'Must provide either html or uri to print.');
    }
    if (options.html && options.uri) {
      throw new ExpoModuleError('ERR_PRINT_INVALID_OPTIONS', 'Must provide exactly one of html and uri.');
    }

    this.printing = true;
    let path: string | undefined;
    try {
      path = await outputPath(this.context.cachePath, true);
      this.assertActive(generation);
      if (options.html !== undefined) {
        await writeBytes(path, await this.render(options, generation));
      } else {
        await materializePdf(options.uri!, path, this.requests, (): void => this.assertActive(generation), this.context);
      }

      this.assertActive(generation);
      await startPrint(path, this.context.uiAbilityContext);

      // Ownership transfers to the system print task's terminal event listeners.
      path = undefined;
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      throw new ExpoModuleError('ERR_PRINT_FAILED', 'Unable to start printing.', error as Object);
    } finally {
      this.printing = false;
      if (path !== undefined) await removeFile(path);
    }
  }

  private async printToFile(options: PrintOptions): Promise<PrintResult> {
    const generation = this.generation;
    this.assertActive(generation);
    if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) {
      throw new ExpoModuleError('ERR_PRINT_PDF_UNAVAILABLE', 'PDF Kit is required to determine the generated PDF page count.');
    }

    let path: string | undefined;
    try {
      const bytes = await this.render(options, generation);
      this.assertActive(generation);

      path = await outputPath(this.context.cachePath);
      await writeBytes(path, bytes);
      this.assertActive(generation);

      const result = new PrintResult(path, pageCount(path));
      if (options.base64) result.base64 = await new util.Base64Helper().encodeToString(bytes);

      this.assertActive(generation);
      path = undefined;
      return result;
    } catch (error) {
      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      throw new ExpoModuleError('ERR_PRINT_PDF_RENDER', 'Unable to create the PDF file.', error as Object);
    } finally {
      if (path !== undefined) await removeFile(path);
    }
  }

  private render(options: PrintOptions, generation: number): Promise<Uint8Array> {
    const result = this.queue.then(async (): Promise<Uint8Array> => {
      this.assertActive(generation);
      if (!canIUse('SystemCapability.Web.Webview.Core')) {
        throw new ExpoModuleError('ERR_PRINT_HTML_UNAVAILABLE', 'This device does not support ArkWeb HTML rendering.');
      }

      const window = await this.context.getReactNativeWindow();
      this.assertActive(generation);

      const renderer = new PrintRenderer(window.getUIContext(), options);
      this.renderers.add(renderer);
      try {
        return await renderer.render();
      } finally {
        this.renderers.delete(renderer);
      }
    });

    this.queue = result.then(
      (): void => {},
      (): void => {},
    );

    return result;
  }

  private assertActive(generation: number): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_PRINT_DESTROYED', 'The Expo Print module has been destroyed.');
    }
    if (generation !== this.generation || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_PRINT_BACKGROUND', 'Printing requires an active foreground application.');
    }
  }

  private cancelPending(message: string): void {
    this.generation += 1;
    this.renderers.forEach((renderer: PrintRenderer): void => {
      renderer.fail(new ExpoModuleError('ERR_PRINT_CANCELLED', message));
    });

    this.requests.forEach((request: http.HttpRequest): void => {
      try {
        request.destroy();
      } catch (_) {}
    });
    this.requests.clear();
  }

  private destroy(): void {
    if (this.destroyed) return;
    this.destroyed = true;
    this.cancelPending('The Expo Print module has been destroyed.');
  }
}
