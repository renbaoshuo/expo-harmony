/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { webview } from '@kit.ArkWeb';
import { STACK_PARSER_SCRIPT } from './generated/ExpoLogBoxScripts';

import { LOG_BOX_DOM_HOST_OS, LOG_BOX_ERROR_MESSAGE, LOG_BOX_READY_MESSAGE } from './ExpoLogBoxController';

const WEB_BRIDGE_NAME: string = 'ExpoLogBoxNative';
const WEB_BRIDGE_METHODS: string[] = ['postMessage'];
const DOCUMENT_START_SCRIPT_RULES: string[] = ['*'];
const LOG_BOX_READY_SELECTOR: string = '[data-expo-log-backdrop="true"]';
const DOM_READY: string = '$$dom_ready';
const DOM_EVENT: string = '$$dom_event';
const DOM_PROPS: string = '$$props';

interface LogBoxScriptItem {
  script: string;
  scriptRules: string[];
}

class ExpoLogBoxWebBridge {
  private readonly session: ExpoLogBoxWebSession;

  constructor(session: ExpoLogBoxWebSession) {
    this.session = session;
  }

  postMessage(message: string): void {
    this.session.handleMessage(message);
  }
}

export class ExpoLogBoxWebSession {
  readonly web: webview.WebviewController = new webview.WebviewController();
  readonly bridge: ExpoLogBoxWebBridge;
  readonly documentStartScripts: LogBoxScriptItem[];
  private disposed: boolean = false;
  private failed: boolean = false;
  private ready: boolean = false;
  private domReady: boolean = false;
  private controllerAttached: boolean = false;
  private startupTimeout?: number;
  private payload: string;
  private readonly onMessage: (message: string) => void;
  private readonly onReady: () => void;
  private readonly onError: (error: Object) => void;

  constructor(
    initialProps: string,
    devServerOrigin: string,
    onMessage: (message: string) => void,
    onReady: () => void,
    onError: (error: Object) => void,
  ) {
    this.onMessage = onMessage;
    this.onReady = onReady;
    this.onError = onError;
    this.payload = initialProps;
    this.bridge = new ExpoLogBoxWebBridge(this);
    this.documentStartScripts = [
      {
        script: bootstrapScript(initialProps, devServerOrigin),
        scriptRules: DOCUMENT_START_SCRIPT_RULES,
      },
    ];
  }

  handleMessage(message: string): void {
    if (this.disposed || this.failed) return;
    try {
      const event = JSON.parse(message) as PageMessage;
      if (event.type === DOM_READY) {
        // SDK 57 emits readiness after installing its props listener, including on reload.
        this.domReady = true;
        this.updateProps(this.payload);
      } else if (event.type === LOG_BOX_READY_MESSAGE) {
        this.ready = true;
        this.clearStartupTimeout();
        this.onReady();
      } else if (event.type === LOG_BOX_ERROR_MESSAGE) {
        this.fail(new Error(event.data?.message ?? 'The Expo LogBox page failed.'));
      } else {
        this.onMessage(message);
      }
    } catch (error) {
      this.fail(error as Object);
    }
  }

  updateProps(payload: string): void {
    this.payload = payload;
    if (!this.domReady || this.disposed || this.failed) return;

    this.inject(`window.dispatchEvent(new CustomEvent(${JSON.stringify(DOM_EVENT)}, { detail: {
      type: ${JSON.stringify(DOM_PROPS)}, data: window.$$EXPO_LOG_BOX_NORMALIZE_PROPS(${payload})
    } }));true;`).catch((error: Object): void => this.fail(error));
  }

  async inject(script: string): Promise<void> {
    if (this.disposed) return;
    await this.web.runJavaScript(script);
  }

  attached(): void {
    if (this.disposed) return;
    try {
      this.web.onActive();
      this.controllerAttached = true;
    } catch (error) {
      this.fail(error as Object);
    }
  }

  appear(): void {
    if (this.disposed || this.failed || this.ready || this.startupTimeout !== undefined) return;

    this.startupTimeout = setTimeout((): void => {
      this.startupTimeout = undefined;
      this.fail(new Error('The Expo LogBox page did not initialize within 15 seconds.'));
    }, 15000);
  }

  private clearStartupTimeout(): void {
    if (this.startupTimeout === undefined) return;
    clearTimeout(this.startupTimeout);
    this.startupTimeout = undefined;
  }

  fail(error: Object): void {
    if (this.disposed || this.failed) return;

    this.failed = true;
    this.clearStartupTimeout();

    console.error(`Expo LogBox Web failed: ${error instanceof Error ? error.message : String(error)}`);
    this.onError(error);
  }

  dispose(): void {
    if (this.disposed) return;

    this.disposed = true;
    this.clearStartupTimeout();

    if (!this.controllerAttached) return;
    try {
      this.web.stop();
    } catch (_error) {}
    try {
      this.web.onInactive();
    } catch (_error) {}
  }
}

@Component
export struct ExpoLogBoxWebView {
  @Require session?: ExpoLogBoxWebSession;

  build(): void {
    if (this.session !== undefined) {
      Web({
        src: $rawfile('expo_log_box/index.html'),
        controller: this.session.web,
        incognitoMode: true,
      })
        .javaScriptProxy({
          object: this.session.bridge,
          name: WEB_BRIDGE_NAME,
          methodList: WEB_BRIDGE_METHODS,
          controller: this.session.web,
        })
        .javaScriptOnDocumentStart(this.session.documentStartScripts)
        .javaScriptAccess(true)
        .fileAccess(false)
        .onlineImageAccess(false)
        .zoomAccess(false)
        .onAppear((): void => this.session?.appear())
        .onControllerAttached((): void => this.session?.attached())
        .onErrorReceive((event): void => {
          this.session?.fail(new Error(event.error.getErrorInfo()));
        })
        .onRenderExited((): void => this.session?.fail(new Error('The ArkWeb renderer exited.')))
        .width('100%')
        .height('100%')
        .backgroundColor('#111113')
        .focusable(true)
        .hitTestBehavior(HitTestMode.Block)
        .onDisAppear((): void => this.session?.dispose());
    }
  }
}

interface PageMessage {
  type?: string;
  data?: PageError;
}

interface PageError {
  message?: string;
}

function bootstrapScript(initialProps: string, devServerOrigin: string): string {
  const origin = JSON.stringify(devServerOrigin);
  const hostOS = JSON.stringify(LOG_BOX_DOM_HOST_OS);
  const nativeBridge = JSON.stringify(WEB_BRIDGE_NAME);
  const readyMessage = JSON.stringify(LOG_BOX_READY_MESSAGE);
  const errorMessage = JSON.stringify(LOG_BOX_ERROR_MESSAGE);
  const readySelector = JSON.stringify(LOG_BOX_READY_SELECTOR);

  return `
    ;(() => {
      const exports = {};
      ${STACK_PARSER_SCRIPT}
      window.$$EXPO_LOG_BOX_NORMALIZE_PROPS = (payload) => {
        for (const log of payload.props.nativeLogs || []) {
          if (typeof log.stack === 'string') {
            const rawStack = log.stack;
            log.stack = exports.parse(rawStack).map(frame => ({
              ...frame, column: frame.column == null ? null : frame.column - 1,
            }));
            if (!log.stack.length && rawStack) log.message += '\\n\\n' + rawStack;
          }
        }
        return payload;
      };
      var process = globalThis.process || {};
      globalThis.process = process;
      process.env = process.env || {};
      if (${origin}) process.env.EXPO_DEV_SERVER_ORIGIN = ${origin};

      // The shipped HTML reads this object synchronously before running the DOM bundle.
      window.ReactNativeWebView = {
        injectedObjectJson: () => JSON.stringify({
          EXPO_DOM_HOST_OS: ${hostOS},
          initialProps: window.$$EXPO_LOG_BOX_NORMALIZE_PROPS(${initialProps}),
        }),
        postMessage: (message) => window[${nativeBridge}].postMessage(message),
      };

      let settled = false;
      let observer;
      let scheduled = false;
      const postNative = (type, message) => {
        try {
          window.ReactNativeWebView.postMessage(JSON.stringify({
            type,
            data: message === undefined ? {} : { message },
          }));
        } catch (_error) {}
      };
      const finish = (type, message) => {
        if (settled) return;
        settled = true;
        observer?.disconnect();
        postNative(type, message);
      };
      const checkReady = () => {
        if (settled || scheduled || !document.querySelector(${readySelector})) return;
        scheduled = true;
        requestAnimationFrame(() => requestAnimationFrame(() => {
          scheduled = false;
          if (!settled && document.querySelector(${readySelector})) finish(${readyMessage});
        }));
      };
      window.addEventListener('error', (event) => {
        const message = event.message || 'The Expo LogBox page raised an error.';
        if (settled) postNative(${errorMessage}, message);
        else finish(${errorMessage}, message);
      });
      window.addEventListener('unhandledrejection', (event) => {
        // The inspector does not await actions such as Reload or Open in Editor.
        // A rejected action after startup should leave the error and controls visible.
        if (settled) return;
        const reason = event.reason;
        const message = reason instanceof Error ? reason.message : String(reason);
        finish(${errorMessage}, message);
      });
      window.addEventListener('DOMContentLoaded', () => {
        // Upstream positions only ios/android overlays on narrow viewports.
        // Keep the real host OS for symbolication and add only the missing layout.
        const style = document.createElement('style');
        style.textContent = '@media (max-width: 575px) { #root > :has(> ' + ${readySelector} +
          ') { top: env(safe-area-inset-top, 0px); } ' + ${readySelector} +
          ' + div { border-top-left-radius: 0; border-top-right-radius: 0; } }';
        document.head.appendChild(style);
        const root = document.documentElement;
        if (!root) {
          finish(${errorMessage}, 'The Expo LogBox document has no root element.');
          return;
        }
        observer = new MutationObserver(checkReady);
        observer.observe(root, { childList: true, subtree: true });
        checkReady();
      }, { once: true });
    })();
    true;
  `;
}
