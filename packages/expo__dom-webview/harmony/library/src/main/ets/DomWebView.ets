/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { webview } from '@kit.ArkWeb';
import { FrameCallback } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { ExpoModuleError, ExpoView, ExpoViewContext, ExpoViewContentContext } from '@expo-harmony/expo-modules-core';
import { INSTALL_GLOBALS_SCRIPT, NATIVE_EVAL_WRAPPER_SCRIPT } from './generated/DomWebViewBrowserScripts';

const EVAL_PROMPT_HEADER: string = '__EXPO_DOM_WEBVIEW_JS_EVAL__';
const REGISTER_PROMPT: string = '__EXPO_DOM_WEBVIEW_REGISTER__';
const DOCUMENT_MARKER_PREFIX: string = '__EXPO_DOM_WEBVIEW_DOCUMENT__';
const EVAL_REQUEST: string = 'ExpoDomWebView.eval';
const EVAL_CANCEL: string = 'ExpoDomWebView.evalCancel';
const EVAL_RESULT: string = 'ExpoDomWebView.evalResult';
const EVAL_RETIRE: string = 'ExpoDomWebView.retireDocument';
const NATIVE_DOCUMENTS: string = '$$DomWebViewDocuments';
const MESSAGE_BRIDGE_NAME: string = 'ReactNativeWebView';
const SCROLL_ANIMATION_DURATION_MS: number = 250;
const EVAL_TIMEOUT_MS: number = 30000;

interface DocumentRegistration {
  id: number;
  token: string;
}

interface EvalParams {
  deferredId: number;
  source: string;
}

interface EvalResult {
  requestId: string;
  result?: string;
  error?: string;
}

interface PendingEval {
  result: JsResult;
  timer: number;
}

interface MessagePayload {
  url: string;
  title: string;
  data: string;
}

interface RenderProcessGonePayload {
  url: string;
  title: string;
  didCrash: boolean;
}

class MessageBridge {
  private readonly view: DomWebView;

  constructor(view: DomWebView) {
    this.view = view;
  }

  postMessage(message: string): void {
    this.view.dispatchMessage(String(message));
  }

  injectedObjectJson(): string {
    return this.view.injectedObjectJson;
  }

  retireExpoDomDocument(token: string): void {
    this.view.retireDocumentWithToken(token);
  }
}

// IDs never repeat during the ArkTS process lifetime, including RN reloads.
let nextId: number = 0;

// ArkWeb exposes one debugging switch for the whole process.
const debuggingOwners: Set<number> = new Set();
let debuggingEnabled: boolean = false;

function updateDebugging(owner: number, enabled: boolean): void {
  if (enabled) debuggingOwners.add(owner);
  else debuggingOwners.delete(owner);

  const requested = debuggingOwners.size > 0;
  if (requested === debuggingEnabled) return;

  try {
    webview.WebviewController.setWebDebuggingAccess(requested);
    debuggingEnabled = requested;
  } catch (error) {
    console.warn(`Expo DOM WebView could not update web debugging: ${error instanceof Error ? error.message : String(error)}`);
  }
}

@Observed
export class DomWebView extends ExpoView {
  readonly id: number = nextId++;
  readonly controller: webview.WebviewController = new webview.WebviewController();
  readonly bridge: MessageBridge = new MessageBridge(this);
  source: string | null = null;
  script: string = '';
  endScript: string = '';
  injectedObjectJson: string = '{}';
  mediaPlaybackRequiresUserAction: boolean = true;
  debugging: boolean = false;
  horizontal: boolean = true;
  vertical: boolean = true;
  nested: boolean = true;
  private bridgeEnabled: boolean = false;
  private bridgeRevision: number = 0;
  private attached: boolean = false;
  private rendererGone: boolean = false;
  private recovering: boolean = false;
  private loadedSource: string | null = null;
  private readonly debuggable: boolean;
  private loadedScripts?: string;
  private url: string = '';
  private title: string = '';
  // Only the top document's injected closure sends the registration prompt.
  private readonly registrationKey: string = util.generateRandomUUID();
  private readonly ready: Promise<void>;
  private attach?: () => void;
  private destroyed: boolean = false;
  private document?: DocumentRegistration;
  private readonly register: (id: number, view: DomWebView) => void;
  private readonly unregister: (id: number) => void;
  private sequence: number = 0;
  private pending: Map<string, PendingEval> = new Map();
  private unsubscribe?: () => void;
  private update?: () => void;
  private pendingProps?: Promise<boolean>;
  private finishProps?: (navigated: boolean) => void;

  constructor(context: ExpoViewContext, register: (id: number, view: DomWebView) => void, unregister: (id: number) => void) {
    super(context);
    this.debuggable = context.moduleContext.uiAbilityContext.applicationInfo.debug;
    this.ready = new Promise<void>((resolve: () => void): void => {
      this.attach = resolve;
    });

    this.register = register;
    this.unregister = unregister;
    this.unsubscribe = context.rnComponentContext.rnInstance.cppEventEmitter.subscribe(EVAL_RESULT, (payload: ESObject): void => {
      const response = payload as EvalResult;
      const pending = this.pending.get(response.requestId);
      if (pending === undefined) return;

      this.pending.delete(response.requestId);
      clearTimeout(pending.timer);

      this.confirmPrompt(pending.result, response.error === undefined ? (response.result ?? '') : JSON.stringify({ error: response.error }));
    });
  }

  setContentUpdater(update?: () => void): void {
    this.update = update;
  }

  private get registerPrompt(): string {
    return `${REGISTER_PROMPT}${this.registrationKey}:${this.bridgeRevision}`;
  }

  get allowsAppFileAccess(): boolean {
    return this.source?.toLowerCase().startsWith('file://') === true;
  }

  setExpoModulesBridge(enabled: boolean): void {
    if (enabled === this.bridgeEnabled) return;

    this.bridgeEnabled = enabled;
    // Disabling can retire a document even if the bridge is enabled again before ArkUI updates.
    this.bridgeRevision += 1;
    if (!enabled) this.retireDocument();
  }

  commitProps(): void {
    if (this.update === undefined) return;

    if (this.pendingProps === undefined) {
      this.pendingProps = new Promise<boolean>((resolve: (navigated: boolean) => void): void => {
        this.finishProps = resolve;
      });
    }

    try {
      this.update();
    } catch (error) {
      this.completeProps(false);
      throw new ExpoModuleError('ERR_WEBVIEW_LOAD', error instanceof Error ? error.message : String(error));
    }
  }

  documentStartScript(): string {
    if (!this.bridgeEnabled && this.script.length === 0) return '';

    // The upstream listener interpolates its document ID inside a template literal.
    const install = INSTALL_GLOBALS_SCRIPT.split('"%%WEBVIEW_ID%%"').join('${webViewId}');
    const bridge = this.bridgeEnabled ? `
      if (window === window.top) {
        const prompt = window.prompt.bind(window);
        let active;

        function installBridge() {
          const json = prompt(${JSON.stringify(this.registerPrompt)});
          if (json === null) throw new Error('Expo DOM WebView registration was cancelled');

          const { id: webViewId, token } = JSON.parse(json);
          if (!Number.isSafeInteger(webViewId) || webViewId < 0 || typeof token !== 'string') {
            throw new Error('Invalid Expo DOM WebView registration');
          }

          const marker = ${JSON.stringify(DOCUMENT_MARKER_PREFIX)} + token;
          active = { marker, token };
          Object.defineProperty(window, marker, { value: true, configurable: true });
          window.ExpoDomWebViewBridge = { webViewId, eval: function(params) {
            let succeeded = false;

            try {
              const json = prompt(${JSON.stringify(EVAL_PROMPT_HEADER)} + token + ':' + params);
              if (json === null) throw new Error('Expo DOM WebView evaluation was cancelled');

              const result = JSON.parse(json);
              if (result.error !== undefined) throw new Error(result.error);

              succeeded = true;
              return json;
            } finally {
              if (!succeeded) window.ExpoDomWebView?.removeDeferred(JSON.parse(params).deferredId);
            }
          } };

          ${install}
        }

        window.addEventListener('pagehide', function() {
          if (!active) return;

          const { marker, token } = active;
          active = undefined;

          delete window[marker];
          delete window.ExpoDomWebView;
          delete window.ExpoDomWebViewBridge;
          window.ReactNativeWebView?.retireExpoDomDocument(token);
        });
        window.addEventListener('pageshow', function(event) {
          if (event.persisted && !active) installBridge();
        });

        installBridge();
      }
    ` : '';

    return `
      (function() {
        try {
          ${bridge}
        } finally {
          ${this.script ? `(function() { ${this.script}\n})();` : ''}
        }
      })();
      true;
    `;
  }

  documentEndScript(): string {
    return this.endScript ? `(function() { ${this.endScript}\n})();true;` : '';
  }

  controllerAttached(): void {
    if (this.destroyed) return;

    this.attached = true;
    this.attach?.();
    this.attach = undefined;

    try {
      this.controller.onActive();
    } catch (error) {
      console.warn(`Expo DOM WebView could not activate the renderer: ${error instanceof Error ? error.message : String(error)}`);
    }

    if (this.pendingProps === undefined) this.loadSource();
  }

  private navigate(url?: string): void {
    const gone = this.rendererGone;
    const recovering = this.recovering;
    const document = this.document;

    // Document-start scripts can run before the next onPageBegin callback.
    this.rendererGone = false;
    this.recovering = gone || recovering;

    try {
      if (url === undefined) this.controller.refresh();
      else this.controller.loadUrl(url);
    } catch (error) {
      this.rendererGone = gone;
      this.recovering = recovering;
      throw new ExpoModuleError('ERR_WEBVIEW_LOAD', error instanceof Error ? error.message : String(error));
    }

    if (this.document === document) this.retireDocument();
  }

  private currentUrl(): string {
    if (!this.rendererGone) {
      try {
        return this.controller.getUrl() || this.url;
      } catch (_) {}
    }
    return this.url;
  }

  private reloadPage(): boolean {
    const url = this.currentUrl();

    if (url) this.navigate(this.rendererGone ? url : undefined);
    else if (this.source !== null) this.navigate(this.source);
    else return false;

    return true;
  }

  applyCommittedProps(): void {
    this.completeProps(this.loadSource());
  }

  private completeProps(navigated: boolean): void {
    const finish = this.finishProps;
    this.finishProps = undefined;
    this.pendingProps = undefined;

    finish?.(navigated);
  }

  private loadSource(): boolean {
    if (!this.attached || this.destroyed) return false;

    updateDebugging(this.id, this.debuggable && this.debugging);

    try {
      const scripts = JSON.stringify([this.script, this.endScript, this.bridgeRevision]);
      const scriptsChanged = this.loadedScripts !== undefined && this.loadedScripts !== scripts;
      let navigated = false;

      if (this.source !== null && this.source !== this.loadedSource &&
        (this.rendererGone || this.source !== this.currentUrl())) {
        this.navigate(this.source);
        navigated = true;
      } else if (scriptsChanged) {
        navigated = this.reloadPage();
      }

      this.loadedScripts = scripts;
      this.loadedSource = this.source;

      return navigated;
    } catch (error) {
      // Prop updates run from ArkUI callbacks, with no JS promise to reject.
      console.warn(`Expo DOM WebView could not load the page: ${error instanceof Error ? error.message : String(error)}`);
      return false;
    }
  }

  async reload(): Promise<void> {
    await this.ready;
    // The next ArkUI frame applies new scripts and file access before navigation.
    const navigated = await this.pendingProps;

    if (this.destroyed) return;
    if (!this.attached) throw new ExpoModuleError('ERR_WEBVIEW_NOT_READY', 'The WebView renderer exited before the controller attached.');
    if (this.recovering || navigated) return;

    if (this.source !== null && this.source !== this.loadedSource) {
      this.navigate(this.source);
      this.loadedSource = this.source;
    } else {
      this.reloadPage();
    }
  }

  async injectJavaScript(script: string): Promise<void> {
    await this.ready;
    if (this.destroyed) return;
    if (!this.attached) throw new ExpoModuleError('ERR_WEBVIEW_NOT_READY', 'The WebView renderer exited before the controller attached.');
    if (this.rendererGone) throw new ExpoModuleError('ERR_WEBVIEW_NOT_READY', 'The WebView renderer exited. Reload the page before injecting JavaScript.');

    await this.controller.runJavaScript(script);
  }

  async injectForDocument(id: number, script: string): Promise<void> {
    await this.ready;
    const document = this.document;
    if (this.destroyed || this.rendererGone || !this.bridgeEnabled || document?.id !== id) return;

    // ArkWeb can execute queued JS after navigation. A public route ID cannot identify the document there.
    const marker = JSON.stringify(DOCUMENT_MARKER_PREFIX + document.token);
    await this.controller.runJavaScript(`if (window[${marker}] === true) {\n${script}\n}`);
  }

  async scrollTo(params: Record<string, ESObject>): Promise<void> {
    const x = (params['x'] as number | undefined) ?? 0;
    const y = (params['y'] as number | undefined) ?? 0;
    if (!Number.isFinite(x) || !Number.isFinite(y)) {
      throw new ExpoModuleError('ERR_INVALID_ARGUMENT', 'scrollTo requires finite coordinates.');
    }

    await this.ready;
    if (this.destroyed) return;
    if (!this.attached) throw new ExpoModuleError('ERR_WEBVIEW_NOT_READY', 'The WebView renderer exited before the controller attached.');
    if (this.rendererGone) throw new ExpoModuleError('ERR_WEBVIEW_NOT_READY', 'The WebView renderer exited. Reload the page before scrolling.');

    this.controller.scrollTo(x, y, params['animated'] !== false ? SCROLL_ANIMATION_DURATION_MS : 0);
  }

  dispatchMessage(message: string): void {
    if (this.destroyed || !this.attached || this.rendererGone) return;

    const payload: MessagePayload = { url: this.currentUrl(), title: this.title, data: message };
    try {
      payload.title = this.controller.getTitle();
    } catch (_) {}

    this.sendEvent('onMessage', payload);
  }

  handlePrompt(event: OnPromptEvent): boolean {
    const message = event.message;
    const result = event.result;
    const registering = message.startsWith(`${REGISTER_PROMPT}${this.registrationKey}:`);
    if (!registering && !message.startsWith(EVAL_PROMPT_HEADER)) return false;

    if (this.destroyed || !this.attached || this.rendererGone || !this.bridgeEnabled) {
      this.cancelPrompt(result);
      return true;
    }

    if (registering) {
      if (message !== this.registerPrompt) {
        this.cancelPrompt(result);
        return true;
      }

      // onPageBegin can arrive after document-start scripts; replace the route here.
      this.retireDocument();

      const registration: DocumentRegistration = { id: nextId++, token: util.generateRandomUUID() };
      this.document = registration;
      this.register(registration.id, this);

      if (!this.confirmPrompt(result, JSON.stringify(registration))) this.retireDocument();
      return true;
    }

    const document = this.document;
    const prefix = `${EVAL_PROMPT_HEADER}${document?.token ?? ''}:`;
    if (document === undefined || !message.startsWith(prefix)) {
      this.cancelPrompt(result);
      return true;
    }

    let request: string | undefined;
    // Confirming after the runtime responds avoids a synchronous ArkUI/Hermes deadlock.
    try {
      const args = JSON.parse(message.slice(prefix.length)) as EvalParams;
      if (args === null || typeof args.source !== 'string' || !Number.isSafeInteger(args.deferredId) || args.deferredId < 0) {
        throw new Error('Invalid Expo DOM WebView evaluation parameters.');
      }

      const wrapper = NATIVE_EVAL_WRAPPER_SCRIPT.split('"%%DEFERRED_ID%%"')
        .join(String(args.deferredId))
        .split('"%%WEBVIEW_ID%%"')
        .join(String(document.id))
        .split('"%%SOURCE%%"')
        .join(args.source);
      const source = `
        (function() {
          const documents = globalThis.expo.${NATIVE_DOCUMENTS} ??= new Map();
          let expoDomDocument = documents.get(${document.id});
          if (expoDomDocument === undefined) {
            expoDomDocument = { sharedObjects: new Map(), subscriptions: new Map() };
            documents.set(${document.id}, expoDomDocument);
          }
          return (
            ${wrapper}
          );
        })()
      `;

      const id = `${this.id}:${this.sequence++}`;
      request = id;
      const timer = setTimeout((): void => {
        const pending = this.pending.get(id);
        if (pending === undefined) return;

        this.pending.delete(id);
        this.cancelNativeEval(id);
        this.confirmPrompt(pending.result, JSON.stringify({ error: 'Expo DOM WebView runtime evaluation timed out.' }));
      }, EVAL_TIMEOUT_MS);
      this.pending.set(id, { result, timer });

      this.context.rnComponentContext.rnInstance.postMessageToCpp(EVAL_REQUEST, {
        requestId: id,
        source,
        runtimeEpoch: this.context.moduleContext.runtimeEpoch,
        tag: this.context.tag,
        componentName: this.context.componentName,
      });
    } catch (error) {
      if (request !== undefined) {
        const pending = this.pending.get(request);
        if (pending !== undefined) clearTimeout(pending.timer);
        this.pending.delete(request);
        this.cancelNativeEval(request);
      }

      this.confirmPrompt(result, JSON.stringify({ error: String(error) }));
    }

    return true;
  }

  private confirmPrompt(result: JsResult, value: string): boolean {
    // Navigation can invalidate JsResult before the next document registers.
    try {
      result.handlePromptConfirm(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  private cancelNativeEval(id: string): void {
    try {
      this.context.rnComponentContext.rnInstance.postMessageToCpp(EVAL_CANCEL, { requestId: id });
    } catch (_) {}
  }

  private cancelPending(): void {
    const requests = this.pending;
    this.pending = new Map();

    requests.forEach((pending: PendingEval, id: string): void => {
      clearTimeout(pending.timer);
      this.cancelNativeEval(id);
      this.cancelPrompt(pending.result);
    });
  }

  private cancelPrompt(result: JsResult): void {
    // A navigation or ArkUI detach may already have invalidated JsResult.
    try {
      result.handleCancel();
    } catch (_) {}
  }

  private retireDocument(): void {
    const document = this.document;
    this.document = undefined;
    this.cancelPending();

    if (document === undefined) return;
    this.unregister(document.id);

    const source = `
      (() => {
        const documents = globalThis.expo.${NATIVE_DOCUMENTS};
        const document = documents?.get(${document.id});
        if (!document) return;

        documents.delete(${document.id});
        for (const events of document.subscriptions.values()) {
          for (const subscription of events.values()) {
            try { subscription.remove(); } catch (error) { console.error(error); }
          }
        }
      })()
    `;

    try {
      this.context.rnComponentContext.rnInstance.postMessageToCpp(EVAL_RETIRE, {
        runtimeEpoch: this.context.moduleContext.runtimeEpoch,
        source,
      });
    } catch (_) {
      // The React instance owns the registry and may already have been torn down.
    }
  }

  retireDocumentWithToken(token: string): void {
    if (this.document?.token === token) this.retireDocument();
  }

  pageBegan(url: string): void {
    if (this.rendererGone || this.destroyed) return;

    this.url = url;
    this.title = '';
  }

  titleReceived(title: string): void {
    this.title = title;
  }

  loadFinished(): void {
    this.recovering = false;
  }

  renderExited(reason: RenderExitReason): void {
    if (this.destroyed || this.rendererGone) return;

    if (this.attached) {
      try {
        this.url = this.controller.getUrl() || this.url;
        this.title = this.controller.getTitle() || this.title;
      } catch (_) {}
    }

    this.rendererGone = true;
    this.recovering = false;
    this.attach?.();
    this.attach = undefined;
    this.retireDocument();

    // The controller may already be unavailable; use the last page metadata.
    const payload: RenderProcessGonePayload = {
      url: this.url,
      title: this.title,
      didCrash: reason === RenderExitReason.ProcessCrashed,
    };

    this.sendEvent('onRenderProcessGone', payload);
    this.sendEvent('onContentProcessDidTerminate', { url: this.url, title: this.title });
  }

  destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    this.attach?.();
    this.attach = undefined;
    this.update = undefined;
    this.completeProps(false);

    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.retireDocument();
    updateDebugging(this.id, false);

    if (!this.attached) return;

    try {
      this.controller.deleteJavaScriptRegister(MESSAGE_BRIDGE_NAME);
    } catch (_) {}
    try {
      this.controller.stop();
    } catch (_) {}
    try {
      this.controller.onInactive();
    } catch (_) {}

    this.attached = false;
  }
}

class AfterRender extends FrameCallback {
  private callback?: () => void;

  constructor(callback: () => void) {
    super();
    this.callback = callback;
  }

  onIdle(): void {
    const callback = this.callback;
    this.callback = undefined;
    callback?.();
  }
}

@Component
struct DomWebViewContent {
  @ObjectLink view: DomWebView;
  @State scripts: ScriptItem[] = [];
  @State endScripts: ScriptItem[] = [];
  private revision: number = 0;

  aboutToAppear(): void {
    this.refreshScripts();
    this.view.setContentUpdater((): void => {
      this.refreshScripts();

      // Apply ArkUI's document-start scripts before starting a new navigation.
      const revision = ++this.revision;
      this.getUIContext().postFrameCallback(
        new AfterRender((): void => {
          if (this.revision === revision) this.view.applyCommittedProps();
        }),
      );
    });
  }

  private refreshScripts(): void {
    const start = this.view.documentStartScript();
    const end = this.view.documentEndScript();

    this.scripts = start.length > 0 ? [{ script: start, scriptRules: ['*'] }] : [];
    this.endScripts = end.length > 0 ? [{ script: end, scriptRules: ['*'] }] : [];
  }

  aboutToDisappear(): void {
    this.revision += 1;
    this.view.setContentUpdater();
    this.view.destroy();
  }

  build(): void {
    Web({ src: '', controller: this.view.controller })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(this.view.allowsAppFileAccess)
      .javaScriptProxy({
        object: this.view.bridge,
        name: MESSAGE_BRIDGE_NAME,
        methodList: ['postMessage', 'injectedObjectJson', 'retireExpoDomDocument'],
        controller: this.view.controller,
      })
      .javaScriptOnDocumentStart(this.scripts)
      .javaScriptOnDocumentEnd(this.endScripts)
      .mediaPlayGestureAccess(this.view.mediaPlaybackRequiresUserAction)
      .horizontalScrollBarAccess(this.view.horizontal)
      .verticalScrollBarAccess(this.view.vertical)
      .nestedScroll({
        scrollUp: this.view.nested ? NestedScrollMode.SELF_ONLY : NestedScrollMode.PARENT_FIRST,
        scrollDown: this.view.nested ? NestedScrollMode.SELF_ONLY : NestedScrollMode.PARENT_FIRST,
        scrollLeft: this.view.nested ? NestedScrollMode.SELF_ONLY : NestedScrollMode.PARENT_FIRST,
        scrollRight: this.view.nested ? NestedScrollMode.SELF_ONLY : NestedScrollMode.PARENT_FIRST,
      })
      .onControllerAttached((): void => this.view.controllerAttached())
      .onPrompt((event: OnPromptEvent): boolean => this.view.handlePrompt(event))
      .onPageBegin((event: OnPageBeginEvent): void => this.view.pageBegan(event.url))
      .onPageEnd((): void => this.view.loadFinished())
      .onErrorReceive((event: OnErrorReceiveEvent): void => {
        if (event.request.isMainFrame()) this.view.loadFinished();
      })
      .onTitleReceive((event: OnTitleReceiveEvent): void => this.view.titleReceived(event.title))
      .onRenderExited((event: OnRenderExitedEvent): void => this.view.renderExited(event.renderExitReason));
  }
}
@Builder
export function buildDomWebView(context: ExpoViewContentContext): void {
  DomWebViewContent({ view: context.nativeView as DomWebView });
}
