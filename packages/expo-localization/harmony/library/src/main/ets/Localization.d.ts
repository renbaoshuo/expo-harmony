/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

declare module 'libexpo_localization.so' {
  export interface LocaleInfo {
    decimalSeparator: string | null;
    digitGroupingSeparator: string | null;
    currencyCode: string | null;
    currencySymbol: string | null;
    isRTL: boolean;
  }

  export interface CalendarInfo {
    calendar: string | null;
    firstWeekday: number | null;
  }

  const localization: {
    getLocaleInfo(languageTag: string): LocaleInfo;
    getCalendarInfo(languageTag: string): CalendarInfo;
  };

  export default localization;
}
