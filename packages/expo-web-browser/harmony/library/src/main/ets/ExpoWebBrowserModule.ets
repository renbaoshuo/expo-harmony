/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { Want } from '@kit.AbilityKit';
import { uri, url } from '@kit.ArkTS';
import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoRecordShape,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';

// Stage-model Want does not expose the legacy Action and Entity enums.
const VIEW_DATA_ACTION: string = 'ohos.want.action.viewData';
const BROWSABLE_ENTITY: string = 'entity.system.browsable';

enum ResultType {
  OPENED = 'opened',
  LOCKED = 'locked',
  DISMISS = 'dismiss',
  SUCCESS = 'success',
}

interface BrowserResult {
  type: ResultType;
  url?: string;
}

interface CustomTabsBrowsers {
  browserPackages: string[];
  servicePackages: string[];
}

const BROWSER_OPTIONS = ExpoValueTypes.shapedRecord<Record<string, ESObject>>(
  'WebBrowserOptions',
  new ExpoRecordShape(),
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
);

class AuthSession {
  readonly redirect: string | undefined;
  readonly resolve: (result: BrowserResult) => void;
  readonly reject: (error: ExpoModuleError) => void;
  backgrounded: boolean = false;
  returned: boolean = false;
  launched: boolean = false;
  pendingRedirect?: string;

  constructor(redirect: string | undefined, resolve: (result: BrowserResult) => void, reject: (error: ExpoModuleError) => void) {
    this.redirect = redirect;
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class ExpoWebBrowserModule extends ExpoModule {
  private session?: AuthSession;
  private launching: boolean = false;
  private cancel?: (error: ExpoModuleError) => void;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return (
      new ExpoModuleDefinition()
        .name('ExpoWebBrowser')
        .asyncFunction(
          'openBrowserAsync',
          ExpoFunction.typed2(
            ExpoValueTypes.string(),
            BROWSER_OPTIONS,
            (url: string, _options: Record<string, ESObject>): Promise<BrowserResult> => this.openBrowser(url),
          ),
        )
        .asyncFunction(
          'openAuthSessionAsync',
          ExpoFunction.typed2(
            ExpoValueTypes.string(),
            ExpoValueTypes.string().optional(),
            (url: string, redirect: string | undefined): Promise<BrowserResult> => this.openAuthSession(url, redirect),
          ),
        )
        .syncFunction('dismissAuthSession', (): void => {
          const session = this.session;
          if (session !== undefined) this.finishAuthSession(session, { type: ResultType.DISMISS });
        })
        .asyncFunction('dismissBrowser', async (): Promise<void> => {
          throw new ExpoModuleError('ERR_WEB_BROWSER_DISMISS_UNAVAILABLE', 'HarmonyOS cannot close an external browser from this application.');
        })
        // Upstream checks native availability before taking its non-Android no-op path.
        .asyncFunction('warmUpAsync', async (): Promise<Record<string, string>> => ({}))
        .asyncFunction('coolDownAsync', async (): Promise<Record<string, string>> => ({}))
        .asyncFunction('mayInitWithUrlAsync', async (): Promise<Record<string, string>> => ({}))
        .asyncFunction(
          'getCustomTabsSupportingBrowsersAsync',
          async (): Promise<CustomTabsBrowsers> => ({
            browserPackages: [],
            servicePackages: [],
          }),
        )
        .onNewWant((want: Want): void => this.receiveRedirect(want.uri))
        .onBackground((): void => {
          if (this.session !== undefined) this.session.backgrounded = true;
        })
        .onForeground((): void => {
          const session = this.session;
          if (session === undefined || !session.backgrounded) return;

          session.returned = true;
          // A link delivers onNewWant before onForeground; an unmatched return dismisses.
          if (session.launched) this.finishAuthSession(session, { type: ResultType.DISMISS });
        })
        .onPrepareForReload(async (): Promise<void> => this.destroy())
        .onAbilityDestroy((): void => this.destroy())
        .onDestroy((): void => this.destroy())
    );
  }

  private async openBrowser(url: string): Promise<BrowserResult> {
    if (!this.canLaunchBrowser()) return { type: ResultType.LOCKED };
    validateURL(url, true);

    await this.launchBrowser(url);
    this.assertHost();

    return { type: ResultType.OPENED };
  }

  private async openAuthSession(url: string, redirect: string | undefined): Promise<BrowserResult> {
    if (!this.canLaunchBrowser()) {
      throw new ExpoModuleError('ERR_WEB_BROWSER_ALREADY_OPEN', 'A browser session is already open.');
    }

    validateURL(url, true);
    if (redirect !== undefined) validateURL(redirect, false);

    return new Promise<BrowserResult>((resolve, reject): void => {
      const session = new AuthSession(redirect, resolve, reject);
      this.session = session;

      this.launchBrowser(url)
        .then((): void => {
          if (this.session !== session) return;
          this.assertHost();

          session.launched = true;
          if (session.pendingRedirect !== undefined) {
            this.finishAuthSession(session, { type: ResultType.SUCCESS, url: session.pendingRedirect });
          } else if (session.returned) {
            this.finishAuthSession(session, { type: ResultType.DISMISS });
          }
        })
        .catch((error: ExpoModuleError): void => {
          if (this.session !== session) return;

          this.session = undefined;
          // Match SDK 57's auth-start failure contract while preserving host errors.
          session.reject(
            error.code === 'ERR_WEB_BROWSER_OPEN_BROWSER'
              ? new ExpoModuleError('ERR_WEB_AUTH_SESSION_FAILED_TO_START', 'The authentication session could not be started.')
              : error,
          );
        });
    });
  }

  private async launchBrowser(url: string): Promise<void> {
    this.launching = true;
    const cancellation = new Promise<void>((_resolve, reject): void => {
      this.cancel = reject;
    });

    try {
      await Promise.race([
        this.context.uiAbilityContext.startAbility({
          action: VIEW_DATA_ACTION,
          entities: [BROWSABLE_ENTITY],
          uri: url,
        }),
        cancellation,
      ]);
    } catch (_) {
      this.assertHost();

      // Platform errors may echo the authentication URL; do not expose their cause.
      throw new ExpoModuleError('ERR_WEB_BROWSER_OPEN_BROWSER', 'Unable to open the web browser.');
    } finally {
      this.launching = false;
      this.cancel = undefined;
    }
  }

  private receiveRedirect(url: string | undefined): void {
    const session = this.session;

    if (session !== undefined && session.redirect && url?.startsWith(session.redirect)) {
      if (session.launched) {
        this.finishAuthSession(session, { type: ResultType.SUCCESS, url });
      } else if (session.pendingRedirect === undefined) {
        // Keep the first redirect until the system confirms the launch.
        session.pendingRedirect = url;
      }
    }
  }

  private finishAuthSession(session: AuthSession, result: BrowserResult): void {
    if (this.session !== session) return;

    this.session = undefined;
    session.resolve(result);
  }

  private assertHost(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_WEB_BROWSER_DESTROYED', 'The WebBrowser host has been destroyed.');
    }
  }

  private canLaunchBrowser(): boolean {
    this.assertHost();

    // The first launch may background the host before an overlapping call arrives.
    if (this.launching || this.session !== undefined) return false;

    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoModuleError('ERR_WEB_BROWSER_UNAVAILABLE', 'Opening a browser requires a foreground UIAbility.');
    }

    return true;
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;
    const session = this.session;
    this.session = undefined;

    session?.reject(new ExpoModuleError('ERR_WEB_BROWSER_DESTROYED', 'The WebBrowser host was destroyed during a browser session.'));
    this.cancel?.(new ExpoModuleError('ERR_WEB_BROWSER_DESTROYED', 'The WebBrowser host was destroyed during a browser launch.'));
  }
}

function validateURL(value: string, requireWeb: boolean): void {
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(value)?.[1]?.toLowerCase();

  if (scheme === undefined || /[\s\u0000-\u001f\u007f]/.test(value)) {
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'A valid absolute URL is required.');
  }

  const isWeb = scheme === 'http' || scheme === 'https';
  if (requireWeb && !isWeb) {
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'The browser URL must use HTTP or HTTPS.');
  }

  // The web URL parser can infer an authority from inputs such as https:example.com.
  if (isWeb && !/^https?:\/\/[^/\\?#]/i.test(value)) {
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'An HTTP or HTTPS URL must include a host.');
  }

  try {
    if (isWeb) {
      url.URL.parseURL(value);
    } else {
      new uri.URI(value);
    }
  } catch (_) {
    // Auth URLs can contain tokens or codes, so omit the platform's raw error.
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'A valid absolute URL is required.');
  }
}
