import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { ComponentContent, FrameCallback, UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { CSS_PIXELS_PER_INCH, pdfConfiguration, PrintOptions } from './PrintOptions';

const RENDER_TIMEOUT_MS: number = 60_000;
// Teardown may destroy the window without delivering another ArkUI frame or disappearance event.
const CLEANUP_TIMEOUT_MS: number = 2_000;

class PrintFrameCallback extends FrameCallback {
  private readonly callback: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onFrame(): void {}

  onIdle(): void {
    this.callback();
  }
}

@Builder
function printWebView(renderer: PrintRenderer) {
  Column() {
    Web({ src: '', controller: renderer.controller, incognitoMode: true })
      .javaScriptAccess(false)
      .fileAccess(false)
      .imageAccess(true)
      .onlineImageAccess(true)
      .textZoomRatio(renderer.options.textZoom)
      .onControllerAttached((): void => renderer.load())
      .onPageEnd((event): void => renderer.pageEnded(event.url))
      .onErrorReceive((event): void => {
        if (event.request.isMainFrame()) {
          renderer.fail(new ExpoModuleError('ERR_PRINT_HTML_LOAD', event.error.getErrorInfo()));
        }
      })
      .onRenderExited((): void => renderer.fail(new ExpoModuleError('ERR_PRINT_HTML_RENDER', 'The ArkWeb renderer exited.')))
      .width(renderer.config.width * CSS_PIXELS_PER_INCH)
      .height(renderer.config.height * CSS_PIXELS_PER_INCH)
      .focusable(false)
      .hitTestBehavior(HitTestMode.None)
  }
  .opacity(0)
  .accessibilityLevel('no-hide-descendants')
  .hitTestBehavior(HitTestMode.None)
  .onAppear((): void => renderer.appear())
  .onDisAppear((): void => renderer.disappear());
}

export class PrintRenderer {
  readonly options: PrintOptions;
  private readonly ui: UIContext;
  readonly controller: webview.WebviewController = new webview.WebviewController();
  readonly config: webview.PdfConfiguration;
  private content?: ComponentContent<PrintRenderer>;
  private timeout?: number;
  private loaded: boolean = false;
  private appeared: boolean = false;
  private disappeared: boolean = false;
  private onRemoved?: () => void;
  private scheduled: boolean = false;
  private settled: boolean = false;
  private attached: boolean = false;
  private resolve?: (bytes: Uint8Array) => void;
  private reject?: (error: ExpoModuleError) => void;

  constructor(ui: UIContext, options: PrintOptions) {
    this.ui = ui;
    this.options = options;
    this.config = pdfConfiguration(options);
  }

  async render(): Promise<Uint8Array> {
    const result = new Promise<Uint8Array>((resolve: (bytes: Uint8Array) => void, reject: (error: ExpoModuleError) => void): void => {
      this.resolve = resolve;
      this.reject = reject;
    });

    try {
      this.timeout = setTimeout((): void => {
        this.fail(new ExpoModuleError('ERR_PRINT_HTML_TIMEOUT', 'Timed out while rendering HTML to PDF.'));
      }, RENDER_TIMEOUT_MS);
      this.ui.postFrameCallback(
        new PrintFrameCallback((): void => {
          if (this.settled) return;
          try {
            this.content = new ComponentContent(this.ui, wrapBuilder<[PrintRenderer]>(printWebView), this);
            this.ui.getOverlayManager().addComponentContent(this.content);
          } catch (error) {
            this.fail(new ExpoModuleError('ERR_PRINT_HTML_RENDER', 'Unable to attach the print WebView.', error as Object));
          }
        }),
      );

      return await result;
    } finally {
      await this.dispose();
    }
  }

  load(): void {
    if (this.settled || this.attached) return;

    this.attached = true;
    try {
      // Base64 avoids loadData interpreting literal '%' or '#' in the supplied HTML as URL escapes.
      const bytes = new util.TextEncoder().encodeInto(this.options.html || '<!doctype html><html><body></body></html>');
      const html = new util.Base64Helper().encodeToStringSync(bytes);
      this.controller.onActive();
      this.controller.loadData(html, 'text/html', 'base64');
    } catch (error) {
      this.fail(new ExpoModuleError('ERR_PRINT_HTML_LOAD', 'Unable to load HTML for printing.', error as Object));
    }
  }

  pageEnded(url: string): void {
    // loadData without a base URL creates a data: document. Ignore the Web's initial empty page.
    if (!this.attached || !url.startsWith('data:')) return;
    this.loaded = true;
    this.schedule();
  }

  appear(): void {
    this.appeared = true;
    this.disappeared = false;
    this.schedule();
  }

  disappear(): void {
    this.disappeared = true;
    this.onRemoved?.();
    if (!this.settled) {
      this.fail(new ExpoModuleError('ERR_PRINT_HTML_RENDER', 'The print WebView was removed before rendering completed.'));
    }
  }

  private schedule(): void {
    if (this.settled || this.scheduled || !this.loaded || !this.appeared) return;

    this.scheduled = true;
    try {
      this.ui.postFrameCallback(
        new PrintFrameCallback((): void => {
          if (this.settled) return;
          this.capture().catch((error: Object): void => {
            this.fail(new ExpoModuleError('ERR_PRINT_PDF_RENDER', 'Unable to create the PDF.', error));
          });
        }),
      );
    } catch (error) {
      this.fail(new ExpoModuleError('ERR_PRINT_PDF_RENDER', 'Unable to schedule PDF rendering.', error as Object));
    }
  }

  private async capture(): Promise<void> {
    const data = await this.controller.createPdf(this.config);
    if (this.settled) return;

    const bytes = data.pdfArrayBuffer();
    if (bytes.byteLength === 0) throw new Error('ArkWeb returned an empty PDF.');

    this.settled = true;
    this.resolve?.(bytes);
  }

  fail(error: ExpoModuleError): void {
    if (this.settled) return;
    this.settled = true;
    this.reject?.(error);
  }

  private async dispose(): Promise<void> {
    if (this.timeout !== undefined) clearTimeout(this.timeout);
    if (this.attached) {
      try {
        this.controller.stop();
      } catch (_) {}
      try {
        this.controller.onInactive();
      } catch (_) {}
    }

    const content = this.content;
    this.content = undefined;
    if (content === undefined) return;

    try {
      await new Promise<void>((resolve: () => void): void => {
        let complete = false;
        const finish = (): void => {
          if (complete) return;
          complete = true;
          clearTimeout(timeout);
          this.onRemoved = undefined;
          resolve();
        };

        const timeout = setTimeout(finish, CLEANUP_TIMEOUT_MS);
        this.onRemoved = finish;

        try {
          this.ui.getOverlayManager().removeComponentContent(content);
          if (this.disappeared) {
            finish();
          } else if (!this.appeared) {
            // Removed before first appearance: no onDisAppear is guaranteed. Wait for the removal frame.
            this.ui.postFrameCallback(new PrintFrameCallback(finish));
          }
        } catch (_) {
          // A destroyed window has no component tree left to signal disappearance.
          finish();
        }
      });
    } finally {
      try {
        content.dispose();
      } catch (_) {}
    }
  }
}
