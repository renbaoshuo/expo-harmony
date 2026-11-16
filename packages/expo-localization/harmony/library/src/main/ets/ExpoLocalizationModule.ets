/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleDefinition } from '@expo-harmony/expo-modules-core';
import { BusinessError, commonEventManager, deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import localization, { LocaleInfo } from 'libexpo_localization.so';

const LOCALE_EVENT = 'onLocaleSettingsChanged';
const CALENDAR_EVENT = 'onCalendarSettingsChanged';
const USER_PREFERENCES_API = 18;
const LOCALE_INSTANCE_API = 20;
const UNDETERMINED_LANGUAGE = 'und';
const I18N_CAPABILITY = 'SystemCapability.Global.I18n';
const COMMON_EVENT_CAPABILITY = 'SystemCapability.Notification.CommonEvent';
const UNSUBSCRIBE_ATTEMPTS = 3;
const SUBSCRIPTION_RETRY_LIMIT = 3;
const SUBSCRIPTION_RETRY_DELAY_MS = 1000;

// CLDR measurementData. Harmony's public ICU subset has no measurement-system lookup.
const US_MEASUREMENT_REGIONS: string[] = ['US', 'LR'];
const UK_MEASUREMENT_REGIONS: string[] = ['GB', 'MM'];
// Expo Android's region fallback for systems without a temperature preference.
const FAHRENHEIT_REGIONS: string[] = ['AG', 'BZ', 'VG', 'FM', 'MH', 'MS', 'KN', 'BS', 'CY', 'TC', 'US', 'LR', 'PW', 'KY'];

interface Locale {
  languageTag: string;
  languageCode: string | null;
  languageScriptCode: string | null;
  languageRegionCode: string | null;
  regionCode: string | null;
  textDirection: string;
  decimalSeparator: string | null;
  digitGroupingSeparator: string | null;
  measurementSystem: string | null;
  currencyCode: string | null;
  currencySymbol: string | null;
  languageCurrencyCode: string | null;
  languageCurrencySymbol: string | null;
  temperatureUnit: string | null;
}

interface Calendar {
  calendar: string | null;
  timeZone: string | null;
  uses24hourClock: boolean | null;
  firstWeekday: number | null;
}

export class ExpoLocalizationModule extends ExpoModule {
  private readonly observedEvents = new Set<string>();
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private release?: Promise<void>;
  private failed: boolean = false;
  private timer?: number;
  private retries: number = 0;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoLocalization')
      .syncFunction('getLocales', (): Locale[] => this.getLocales())
      .syncFunction('getCalendars', (): Calendar[] => this.getCalendars())
      .events([LOCALE_EVENT, CALENDAR_EVENT])
      .onStartObserving((event: string): void => {
        this.observedEvents.add(event);
        this.startObserving();
      })
      .onStopObserving((event: string): void => {
        this.observedEvents.delete(event);
        if (this.observedEvents.size === 0) {
          this.resetRetry();
          this.stopObserving();
        }
      })
      .onForeground((): void => {
        this.resetRetry();
        this.startObserving();
        this.publishSettings();
      })
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => {
        this.destroy();
      });
  }

  private systemRegion(): string | null {
    if (!canIUse(I18N_CAPABILITY)) return null;

    try {
      const region = i18n.System.getSystemRegion();
      return region ? new Intl.Locale(UNDETERMINED_LANGUAGE, { region }).region || null : null;
    } catch {
      return null;
    }
  }

  private systemLocale(region: string | null): string {
    const fallback = region ? `${UNDETERMINED_LANGUAGE}-${region}` : UNDETERMINED_LANGUAGE;
    if (!canIUse(I18N_CAPABILITY)) return fallback;

    try {
      const tag = deviceInfo.sdkApiVersion >= LOCALE_INSTANCE_API ? i18n.System.getSystemLocaleInstance().toString() : i18n.System.getSystemLocale();

      return new Intl.Locale(tag, { region: region ?? undefined }).toString();
    } catch {
      try {
        return new Intl.Locale(i18n.System.getSystemLanguage(), { region: region ?? undefined }).toString();
      } catch {
        return fallback;
      }
    }
  }

  private preferredLanguages(): string[] {
    if (!canIUse(I18N_CAPABILITY)) return [];

    try {
      return i18n.System.getPreferredLanguageList();
    } catch (error) {
      this.context.logger.warn(`Unable to read preferred languages: ${String(error)}`);
      return [];
    }
  }

  private getLocales(): Locale[] {
    const region = this.systemRegion();
    const fallback = this.systemLocale(region);
    const system = localization.getLocaleInfo(fallback);
    const temperature = this.temperatureUnit(region);

    const locales: Locale[] = [];
    this.preferredLanguages().forEach((tag: string): void => {
      try {
        locales.push(this.locale(tag, region, fallback, system, temperature));
      } catch (error) {
        this.context.logger.warn(`Unable to read preferred locale '${tag}': ${String(error)}`);
      }
    });

    if (locales.length === 0) {
      locales.push(this.locale(fallback, region, fallback, system, temperature));
    }

    return locales;
  }

  private locale(tag: string, region: string | null, systemTag: string, system: LocaleInfo, temperature: string | null): Locale {
    const preferred = new Intl.Locale(tag);
    const language = new Intl.Locale(preferred, {
      region: preferred.region || region || undefined,
    });

    const languageTag = language.toString();
    const info = languageTag === systemTag ? system : localization.getLocaleInfo(languageTag);
    const languageCode = language.language;

    return {
      languageTag,
      languageCode: languageCode && languageCode !== UNDETERMINED_LANGUAGE ? languageCode : null,
      languageScriptCode: language.script || null,
      languageRegionCode: language.region || null,
      regionCode: region,
      textDirection: info.isRTL ? 'rtl' : 'ltr',
      decimalSeparator: system.decimalSeparator,
      digitGroupingSeparator: system.digitGroupingSeparator,
      currencyCode: region === null ? null : system.currencyCode,
      currencySymbol: region === null ? null : system.currencySymbol,
      languageCurrencyCode: info.currencyCode,
      languageCurrencySymbol: info.currencySymbol,
      measurementSystem: region === null ? null : UK_MEASUREMENT_REGIONS.includes(region) ? 'uk' : US_MEASUREMENT_REGIONS.includes(region) ? 'us' : 'metric',
      temperatureUnit: temperature,
    };
  }

  private temperatureUnit(region: string | null): string | null {
    if (canIUse(I18N_CAPABILITY) && deviceInfo.sdkApiVersion >= USER_PREFERENCES_API) {
      try {
        const unit = i18n.System.getTemperatureType();

        if (unit === i18n.TemperatureType.CELSIUS) return 'celsius';
        if (unit === i18n.TemperatureType.FAHRENHEIT) return 'fahrenheit';

        // Expo's public type has no Kelvin value.
        return null;
      } catch (error) {
        this.context.logger.warn(`Unable to read the system temperature unit: ${String(error)}`);
      }
    }

    return region === null ? null : FAHRENHEIT_REGIONS.includes(region) ? 'fahrenheit' : 'celsius';
  }

  private getCalendars(): Calendar[] {
    const tag = this.systemLocale(this.systemRegion());
    const info = localization.getCalendarInfo(tag);
    let timeZone: string | null = null;
    let uses24hourClock: boolean | null = null;
    let firstWeekday = info.firstWeekday;

    if (canIUse(I18N_CAPABILITY)) {
      timeZone = i18n.getTimeZone().getID() || null;
      uses24hourClock = i18n.System.is24HourClock();

      if (deviceInfo.sdkApiVersion >= USER_PREFERENCES_API) {
        const weekday = i18n.System.getFirstDayOfWeek();
        if (weekday >= i18n.WeekDay.MON && weekday <= i18n.WeekDay.SUN) {
          // System.WeekDay starts on Monday. ICU starts on Sunday.
          firstWeekday = weekday === i18n.WeekDay.SUN ? 1 : weekday + 1;
        }
      }
    }

    return [
      {
        calendar: info.calendar,
        timeZone,
        uses24hourClock,
        firstWeekday,
      },
    ];
  }

  private startObserving(): void {
    if (this.destroyed || this.observedEvents.size === 0 || this.release !== undefined || !canIUse(COMMON_EVENT_CAPABILITY)) return;

    if (this.subscriber !== undefined) {
      if (this.failed) this.stopObserving();
      return;
    }

    try {
      const subscriber = commonEventManager.createSubscriberSync({
        events: [
          commonEventManager.Support.COMMON_EVENT_LOCALE_CHANGED,
          commonEventManager.Support.COMMON_EVENT_TIME_CHANGED,
          commonEventManager.Support.COMMON_EVENT_TIMEZONE_CHANGED,
        ],
      });

      this.subscriber = subscriber;
      this.failed = false;

      commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (this.destroyed || this.release !== undefined || this.failed || this.subscriber !== subscriber) return;

        if (error) {
          console.warn(`ExpoLocalization: unable to observe changes: ${String(error)}`);
          this.failed = true;
          this.stopObserving();
          this.scheduleRecovery();

          return;
        }

        this.resetRetry();

        if (data.event === commonEventManager.Support.COMMON_EVENT_LOCALE_CHANGED) {
          this.publishSettings();
        } else if (
          data.event === commonEventManager.Support.COMMON_EVENT_TIME_CHANGED ||
          data.event === commonEventManager.Support.COMMON_EVENT_TIMEZONE_CHANGED
        ) {
          this.publish(CALENDAR_EVENT);
        }
      });
    } catch (error) {
      console.warn(`ExpoLocalization: unable to subscribe to changes: ${String(error)}`);
      this.subscriber = undefined;
      this.failed = true;
      this.scheduleRecovery();
    }
  }

  private scheduleRecovery(): void {
    if (this.destroyed || this.observedEvents.size === 0 || this.timer !== undefined || this.retries >= SUBSCRIPTION_RETRY_LIMIT) return;

    this.retries++;

    this.timer = setTimeout((): void => {
      this.timer = undefined;
      this.startObserving();

      this.publishSettings();
    }, SUBSCRIPTION_RETRY_DELAY_MS);
  }

  private resetRetry(): void {
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
    this.retries = 0;
  }

  private stopObserving(): Promise<void> {
    if (this.release !== undefined) return this.release;

    const subscriber = this.subscriber;
    if (subscriber === undefined) return Promise.resolve();

    this.release = this.unsubscribe(subscriber).then((success: boolean): void => {
      if (success) this.subscriber = undefined;
      this.release = undefined;

      if (this.failed) this.scheduleRecovery();
      else this.startObserving();
    });

    return this.release;
  }

  private async unsubscribe(subscriber: commonEventManager.CommonEventSubscriber): Promise<boolean> {
    for (let attempt = 1; attempt <= UNSUBSCRIBE_ATTEMPTS; attempt++) {
      try {
        await new Promise<void>((resolve, reject): void => {
          commonEventManager.unsubscribe(subscriber, (error: BusinessError): void => {
            if (error) reject(error);
            else resolve();
          });
        });

        return true;
      } catch (error) {
        // The runtime can already be invalid here, so do not access its logger.
        console.warn(`ExpoLocalization: unsubscribe attempt ${attempt} failed: ${String(error)}`);
      }
    }

    // Keep a failed handle to avoid accumulating duplicate native subscriptions.
    this.failed = true;

    return false;
  }

  private publish(event: string): void {
    if (!this.destroyed && this.observedEvents.has(event) && this.context.isValid) this.sendEvent(event);
  }

  private publishSettings(): void {
    this.publish(LOCALE_EVENT);
    this.publish(CALENDAR_EVENT);
  }

  private destroy(): Promise<void> {
    this.destroyed = true;
    this.observedEvents.clear();
    this.resetRetry();

    return this.stopObserving();
  }
}
