/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import * as Localization from 'expo-localization';

import { json } from '../format';
import { DataRow, Panel } from '../ui';
import { SystemApiActions } from './system-api-actions';

export function LocalizationDemo() {
  const locales = Localization.useLocales();
  const calendars = Localization.useCalendars();

  return (
    <>
      <Panel title="语言与地区">
        <SystemApiActions
          actions={[
            ['读取语言与地区', Localization.getLocales, 'localization-read-locales'],
          ]}
        />
      </Panel>

      <Panel title="useLocales">
        {locales.map((locale, index) => (
          <DataRow key={index} label={locale.languageTag} value={json(locale)} />
        ))}
      </Panel>

      <Panel title="日历设置">
        <SystemApiActions
          actions={[
            ['读取日历设置', Localization.getCalendars, 'localization-read-calendars'],
          ]}
        />
      </Panel>

      <Panel title="useCalendars">
        {calendars.map((calendar, index) => (
          <DataRow key={index} label={calendar.calendar ?? '日历'} value={json(calendar)} />
        ))}
      </Panel>
    </>
  );
}
