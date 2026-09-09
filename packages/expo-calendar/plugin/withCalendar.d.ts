import type { ConfigPlugin } from '@expo/config-plugins';

declare const withHarmonyCalendar: ConfigPlugin<{
  calendarPermission?: string;
  readCalendarPermission?: string;
  writeCalendarPermission?: string;
} | void>;

export = withHarmonyCalendar;
