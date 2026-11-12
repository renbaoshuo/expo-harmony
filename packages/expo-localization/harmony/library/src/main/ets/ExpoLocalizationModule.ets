/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModule, ExpoModuleDefinition } from '@expo-harmony/expo-modules-core';
import { BusinessError, commonEventManager, deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import localization, { NumericInfo } from 'libexpo_localization.so';

const LOCALE_EVENT = 'onLocaleSettingsChanged';
const CALENDAR_EVENT = 'onCalendarSettingsChanged';
const USER_PREFERENCES_API = 18;
const LOCALE_INSTANCE_API = 20;
const UNDETERMINED_LANGUAGE = 'und';
const UNSUBSCRIBE_ATTEMPTS = 3;
const SUBSCRIPTION_RETRY_LIMIT = 3;
const SUBSCRIPTION_RETRY_DELAY_MS = 1000;

// Harmony's public ICU does not expose the CLDR measurement lookup.
const US_MEASUREMENT_REGIONS: string[] = ['US', 'LR'];
const UK_MEASUREMENT_REGIONS: string[] = ['GB', 'MM'];
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
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private release?: Promise<void>;
  private failed: boolean = false;
  private recovering: boolean = false;
  private timer?: number;
  private retries: number = 0;
  private destroyed: boolean = false;

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoLocalization')
      .syncFunction('getLocales', (): Locale[] => this.getLocales())
      .syncFunction('getCalendars', (): Calendar[] => this.getCalendars())
      .events([LOCALE_EVENT, CALENDAR_EVENT])
      .onCreate((): void => this.startObserving())
      .onForeground((): void => {
        this.clearRetry();
        this.retries = 0;

        if (this.failed) {
          this.recoverSubscription();
        } else {
          this.startObserving();
          this.publishSettings();
        }
      })
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onDestroy((): void => {
        this.destroy();
      });
  }

  private systemRegion(): string | null {
    try {
      const region = i18n.System.getSystemRegion();
      return region ? new Intl.Locale(UNDETERMINED_LANGUAGE, { region }).region || null : null;
    } catch {
      return null;
    }
  }

  private systemLocale(region: string | null): string {
    try {
      const tag = deviceInfo.sdkApiVersion >= LOCALE_INSTANCE_API ? i18n.System.getSystemLocaleInstance().toString() : i18n.System.getSystemLocale();
      return new Intl.Locale(tag, { region: region ?? undefined }).toString();
    } catch {
      try {
        return new Intl.Locale(i18n.System.getSystemLanguage(), { region: region ?? undefined }).toString();
      } catch {
        return region ? `${UNDETERMINED_LANGUAGE}-${region}` : UNDETERMINED_LANGUAGE;
      }
    }
  }

  private getLocales(): Locale[] {
    const region = this.systemRegion();
    const fallback = this.systemLocale(region);
    const system = localization.getNumericInfo(fallback);
    const temperature = this.temperatureUnit(region);
    const languages = i18n.System.getPreferredLanguageList();

    const locales: Locale[] = [];
    languages.forEach((tag: string): void => {
      try {
        locales.push(this.locale(tag, region, system, temperature));
      } catch (error) {
        this.context.logger.warn(`Unable to read preferred locale '${tag}': ${String(error)}`);
      }
    });

    if (locales.length === 0) {
      locales.push(this.locale(fallback, region, system, temperature));
    }

    return locales;
  }

  private locale(tag: string, region: string | null, system: NumericInfo, temperature: string | null): Locale {
    const preferred = new Intl.Locale(tag);
    const language = new Intl.Locale(preferred, {
      region: preferred.region || region || undefined,
    });

    const numeric = localization.getNumericInfo(language.toString());
    const languageCode = language.language;

    return {
      languageTag: language.toString(),
      languageCode: languageCode && languageCode !== UNDETERMINED_LANGUAGE ? languageCode : null,
      languageScriptCode: language.script || null,
      languageRegionCode: language.region || null,
      regionCode: region,
      textDirection: i18n.isRTL(language.toString()) ? 'rtl' : 'ltr',
      decimalSeparator: system.decimalSeparator,
      digitGroupingSeparator: system.digitGroupingSeparator,
      currencyCode: region === null ? null : system.currencyCode,
      currencySymbol: region === null ? null : system.currencySymbol,
      languageCurrencyCode: numeric.currencyCode,
      languageCurrencySymbol: numeric.currencySymbol,
      measurementSystem: region === null ? null : UK_MEASUREMENT_REGIONS.includes(region) ? 'uk' : US_MEASUREMENT_REGIONS.includes(region) ? 'us' : 'metric',
      temperatureUnit: temperature,
    };
  }

  private temperatureUnit(region: string | null): string | null {
    if (deviceInfo.sdkApiVersion >= USER_PREFERENCES_API) {
      const unit = i18n.System.getTemperatureType();

      if (unit === i18n.TemperatureType.CELSIUS) return 'celsius';
      if (unit === i18n.TemperatureType.FAHRENHEIT) return 'fahrenheit';

      // Expo's public type has no Kelvin value.
      return null;
    }

    return region === null ? null : FAHRENHEIT_REGIONS.includes(region) ? 'fahrenheit' : 'celsius';
  }

  private getCalendars(): Calendar[] {
    const tag = this.systemLocale(this.systemRegion());

    // i18n.Calendar and Expo both use Sunday=1. System.WeekDay uses Monday=1.
    let weekday: number;
    if (deviceInfo.sdkApiVersion >= USER_PREFERENCES_API) {
      weekday = (i18n.System.getFirstDayOfWeek() % 7) + 1;
    } else {
      weekday = i18n.getCalendar(tag).getFirstDayOfWeek();
    }

    return [
      {
        calendar: localization.getCalendarType(tag),
        timeZone: i18n.getTimeZone().getID() || null,
        uses24hourClock: i18n.System.is24HourClock(),
        firstWeekday: weekday,
      },
    ];
  }

  private startObserving(): void {
    if (this.destroyed || this.subscriber !== undefined || this.release !== undefined) return;

    try {
      const subscriber = commonEventManager.createSubscriberSync({
        events: [
          commonEventManager.Support.COMMON_EVENT_LOCALE_CHANGED,
          commonEventManager.Support.COMMON_EVENT_TIME_CHANGED,
          commonEventManager.Support.COMMON_EVENT_TIMEZONE_CHANGED,
        ],
      });

      commonEventManager.subscribe(subscriber, (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (this.destroyed || this.release !== undefined || this.failed || this.subscriber !== subscriber) return;

        if (error) {
          console.warn(`ExpoLocalization: unable to observe changes: ${String(error)}`);
          this.failed = true;
          this.stopObserving();
          this.scheduleRecovery();

          return;
        }

        this.retries = 0;

        if (data.event === commonEventManager.Support.COMMON_EVENT_LOCALE_CHANGED) {
          this.publishSettings();
        } else if (
          data.event === commonEventManager.Support.COMMON_EVENT_TIME_CHANGED ||
          data.event === commonEventManager.Support.COMMON_EVENT_TIMEZONE_CHANGED
        ) {
          this.publish(CALENDAR_EVENT);
        }
      });

      this.subscriber = subscriber;
      this.failed = false;
    } catch (error) {
      console.warn(`ExpoLocalization: unable to subscribe to changes: ${String(error)}`);
      this.failed = true;
      this.scheduleRecovery();
    }
  }

  private scheduleRecovery(): void {
    if (this.destroyed || this.timer !== undefined || this.retries >= SUBSCRIPTION_RETRY_LIMIT) return;

    this.retries++;

    this.timer = setTimeout((): void => {
      this.timer = undefined;
      this.recoverSubscription();
    }, SUBSCRIPTION_RETRY_DELAY_MS);
  }

  private recoverSubscription(): void {
    if (this.destroyed || this.recovering) return;

    this.recovering = true;
    this.stopObserving().then((): void => {
      this.recovering = false;

      if (this.destroyed) return;

      this.startObserving();
      if (this.failed) this.scheduleRecovery();

      this.publishSettings();
    });
  }

  private clearRetry(): void {
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
  }

  private stopObserving(): Promise<void> {
    if (this.release !== undefined) return this.release;

    const subscriber = this.subscriber;
    if (subscriber === undefined) return Promise.resolve();

    this.release = this.unsubscribe(subscriber).then((success: boolean): void => {
      if (success) this.subscriber = undefined;
      this.release = undefined;
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
    if (!this.destroyed && this.context.isValid) this.sendEvent(event);
  }

  private publishSettings(): void {
    this.publish(LOCALE_EVENT);
    this.publish(CALENDAR_EVENT);
  }

  private destroy(): Promise<void> {
    this.destroyed = true;
    this.clearRetry();

    return this.stopObserving();
  }
}
