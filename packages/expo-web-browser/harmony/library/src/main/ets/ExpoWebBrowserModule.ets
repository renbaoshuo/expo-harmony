/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { Want, common } from '@kit.AbilityKit';
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

// The Stage-model SDK does not export constants for these implicit Want values.
const VIEW_DATA_ACTION: string = 'ohos.want.action.viewData';
const BROWSABLE_ENTITY: string = 'entity.system.browsable';
const URI_SCHEME = /^[a-z][a-z0-9+.-]*:/i;
const SCHEME_REDIRECT = /^[a-z][a-z0-9+.-]*:(?:\/\/)?$/i;
const activeBrowserAbilities: WeakSet<common.UIAbilityContext> = new WeakSet();

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
  new ExpoRecordShape().field('browserPackage', ExpoValueTypes.string().optional()),
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
  (fields: Record<string, ESObject>): Record<string, ESObject> => fields,
);

class AuthSession {
  readonly redirect: string | undefined;
  readonly resolve: (result: BrowserResult) => void;
  readonly reject: (error: ExpoModuleError) => void;
  backgrounded: boolean = false;
  launched: boolean = false;
  resultBeforeLaunch?: BrowserResult;

  constructor(redirect: string | undefined, resolve: (result: BrowserResult) => void, reject: (error: ExpoModuleError) => void) {
    this.redirect = redirect;
    this.resolve = resolve;
    this.reject = reject;
  }
}

export class ExpoWebBrowserModule extends ExpoModule {
  private session?: AuthSession;
  private rejectPendingLaunch?: (error: ExpoModuleError) => void;
  private ownedAbility?: common.UIAbilityContext;
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
            (url: string, options: Record<string, ESObject>): Promise<BrowserResult> =>
              this.openBrowser(url, options.browserPackage as string | undefined),
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

          // HarmonyOS delivers the matching Want before bringing the Ability to the foreground.
          this.completeAfterLaunch(session, { type: ResultType.DISMISS });
        })
        .onPrepareForReload(async (): Promise<void> => this.destroy())
        .onAbilityDestroy((): void => this.destroy())
        .onDestroy((): void => this.destroy())
    );
  }

  private async openBrowser(url: string, browserPackage?: string): Promise<BrowserResult> {
    const ability = this.availableAbility();
    if (ability === undefined) return { type: ResultType.LOCKED };

    normalizeURL(url, true);

    await this.launchBrowser(ability, url, browserPackage);
    this.assertHost();

    return { type: ResultType.OPENED };
  }

  private async openAuthSession(url: string, redirect: string | undefined): Promise<BrowserResult> {
    const ability = this.availableAbility();

    if (ability === undefined) {
      throw new ExpoModuleError('ERR_WEB_BROWSER_ALREADY_OPEN', 'A browser session is already open.');
    }

    normalizeURL(url, true);
    const expected = redirect === undefined ? undefined : normalizeURL(redirect, false);

    return new Promise<BrowserResult>((resolve, reject): void => {
      const session = new AuthSession(expected, resolve, reject);
      this.session = session;

      this.launchBrowser(ability, url)
        .then((): void => {
          if (this.session !== session) return;

          this.assertHost();

          session.launched = true;
          const result = session.resultBeforeLaunch;
          if (result !== undefined) {
            this.finishAuthSession(session, result);
          }
        })
        .catch((error: ExpoModuleError): void => {
          if (this.session !== session) return;

          this.session = undefined;
          this.releaseBrowser();

          session.reject(
            error.code === 'ERR_WEB_BROWSER_OPEN_BROWSER'
              ? new ExpoModuleError('ERR_WEB_AUTH_SESSION_FAILED_TO_START', 'The authentication session could not be started.')
              : error,
          );
        });
    });
  }

  private async launchBrowser(ability: common.UIAbilityContext, url: string, browserPackage?: string): Promise<void> {
    activeBrowserAbilities.add(ability);
    this.ownedAbility = ability;

    const cancellation = new Promise<void>((_resolve, reject): void => {
      this.rejectPendingLaunch = reject;
    });

    try {
      const want: Want = { action: VIEW_DATA_ACTION, entities: [BROWSABLE_ENTITY], uri: url };
      if (browserPackage) want.bundleName = browserPackage;

      await Promise.race([ability.startAbility(want), cancellation]);
    } catch (_) {
      this.assertHost();

      // Platform errors may echo the authentication URL; do not expose their cause.
      throw new ExpoModuleError('ERR_WEB_BROWSER_OPEN_BROWSER', 'Unable to open the web browser.');
    } finally {
      this.rejectPendingLaunch = undefined;
      this.releaseBrowser();
    }
  }

  private receiveRedirect(url: string | undefined): void {
    const session = this.session;

    if (session?.redirect === undefined || url === undefined || !matchesRedirect(session.redirect, url)) return;

    this.completeAfterLaunch(session, { type: ResultType.SUCCESS, url });
  }

  private completeAfterLaunch(session: AuthSession, result: BrowserResult): void {
    if (session.launched) this.finishAuthSession(session, result);
    else session.resultBeforeLaunch ??= result;
  }

  private finishAuthSession(session: AuthSession, result: BrowserResult): void {
    if (this.session !== session) return;

    this.session = undefined;
    this.releaseBrowser();
    session.resolve(result);
  }

  private assertHost(): void {
    if (this.destroyed || !this.context.isValid) {
      throw new ExpoModuleError('ERR_WEB_BROWSER_DESTROYED', 'The WebBrowser host has been destroyed.');
    }
  }

  private availableAbility(): common.UIAbilityContext | undefined {
    this.assertHost();

    if (!this.context.isHeadless) {
      const ability = this.context.uiAbilityContext;
      // A launch may background the Ability before a second runtime calls this module.
      if (activeBrowserAbilities.has(ability)) return undefined;
      if (this.context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND) return ability;
    }

    throw new ExpoModuleError('ERR_WEB_BROWSER_UNAVAILABLE', 'Opening a browser requires a foreground UIAbility.');
  }

  private releaseBrowser(): void {
    const ability = this.ownedAbility;
    if (ability === undefined || this.rejectPendingLaunch !== undefined || this.session !== undefined) return;

    activeBrowserAbilities.delete(ability);
    this.ownedAbility = undefined;
  }

  private destroy(): void {
    if (this.destroyed) return;

    this.destroyed = true;

    const session = this.session;
    this.session = undefined;
    this.releaseBrowser();

    session?.reject(new ExpoModuleError('ERR_WEB_BROWSER_DESTROYED', 'The WebBrowser host was destroyed during a browser session.'));
    this.rejectPendingLaunch?.(new ExpoModuleError('ERR_WEB_BROWSER_DESTROYED', 'The WebBrowser host was destroyed during a browser launch.'));
  }
}

function normalizeURL(value: string, requireWeb: boolean): string {
  const scheme = URI_SCHEME.exec(value)?.[0]?.toLowerCase();

  if (scheme === undefined || /[\s\u0000-\u001f\u007f]/.test(value)) {
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'A valid absolute URL is required.');
  }

  const isWeb = scheme === 'http:' || scheme === 'https:';
  if (requireWeb && !isWeb) {
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'The browser URL must use HTTP or HTTPS.');
  }

  // The web URL parser can infer an authority from inputs such as https:example.com.
  if (isWeb && (!/^https?:\/\/[^/\\?#]/i.test(value) || value.includes('\\'))) {
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'An HTTP or HTTPS URL must include a host.');
  }

  try {
    if (isWeb) return url.URL.parseURL(value).href;

    if (!SCHEME_REDIRECT.test(value)) new uri.URI(value);

    return scheme + value.slice(scheme.length);
  } catch (_) {
    // Auth URLs can contain tokens or codes, so omit the platform's raw error.
    throw new ExpoModuleError('ERR_WEB_BROWSER_INVALID_URL', 'A valid absolute URL is required.');
  }
}

function matchesRedirect(expected: string, callback: string): boolean {
  let actual: string;
  try {
    actual = normalizeURL(callback, false);
  } catch (_) {
    return false;
  }

  if (!actual.startsWith(expected)) return false;
  if (actual === expected || SCHEME_REDIRECT.test(expected)) return true;

  // Only allow extra callback parameters or a fragment past the expected endpoint.
  const next = actual.charAt(expected.length);
  const fragment = expected.indexOf('#');

  if (fragment !== -1) return fragment === expected.length - 1 || next === '&';
  if (next === '#') return true;

  const query = expected.indexOf('?');
  return query === -1 ? next === '?' : query === expected.length - 1 || next === '&';
}
