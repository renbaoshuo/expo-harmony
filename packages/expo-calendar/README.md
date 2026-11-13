# @expo-harmony/expo-calendar

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-calendar) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/calendar/)

为 HarmonyOS 上的 React Native 应用提供 Expo Calendar 的原生实现，与官方 `expo-calendar` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 18（HarmonyOS 5.1.0）。

```bash
npm install @expo-harmony/expo-calendar expo-calendar@~57.0.6
```

## 使用

在应用代码中使用 `expo-calendar`：

```ts
import * as Calendar from 'expo-calendar';

const permission = await Calendar.requestCalendarPermissionsAsync();
if (permission.granted) {
  const calendars = await Calendar.getCalendars(Calendar.EntityTypes.EVENT);
  const events = await calendars[0]?.listEvents(new Date(), new Date(Date.now() + 86400000));
}
```

## API 对照表

### Hooks

#### `useCalendarPermissions(options?)`

返回 `[PermissionResponse | null, request, get]`，用于读取或申请日历读写权限。`options.writeOnly` 不改变 HarmonyOS 上同时申请读写权限的行为。

#### `useRemindersPermissions(options?)`

返回固定的拒绝状态：`status` 为 `denied`，`granted` 为 `false`，`canAskAgain` 为 `false`，`expires` 为 `'never'`。HarmonyOS 不提供提醒事项权限。

### Methods

旧版异步接口从 `expo-calendar/legacy` 导入。

#### `Calendar.isAvailableAsync()`

返回 `Promise<boolean>`，表示设备是否支持日历功能，不检查权限。返回 `false` 时，日历和日程 API 不可用。

#### `Calendar.getCalendarPermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询日历读写权限。读写权限都已授予时 `granted` 为 `true`；`expires` 始终为 `'never'`。API 20 及以上可读取系统当前状态；API 18–19 无法识别应用以外途径的拒绝或系统设置重置后的状态。

#### `Calendar.requestCalendarPermissionsAsync()`

返回 `Promise<PermissionResponse>`，同时申请日历读权限和写权限。并发调用共用一次申请。系统不再允许申请或要求到设置中开启时，`canAskAgain` 为 `false`。

#### `Calendar.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，行为与 `requestCalendarPermissionsAsync()` 相同。

#### `Calendar.getCalendarsAsync(entityType?)`

返回 `Promise<Calendar[]>`。`entityType` 可省略或传 `EntityTypes.EVENT`；传 `EntityTypes.REMINDER` 会报错。普通权限下，结果限于系统默认日历和当前应用创建的日历账户；默认日历的 `isPrimary` 为 `true`。

#### `Calendar.getDefaultCalendarAsync()`

返回 `Promise<Calendar>`，提供系统默认日历。

#### `Calendar.createCalendarAsync(details?)`

返回新日历的 ID（`Promise<string>`）。`details.title` 必填；日历类型可由 `details.source.type` 或 `details.type` 指定，省略时为 `local`。创建时支持 `local`、`email`、`birthdays`、`caldav` 和 `subscribed`。颜色可传颜色字符串或数值。`sourceId`、`timeZone`、`isVisible` 和 `isSynced` 不支持。

#### `Calendar.updateCalendarAsync(id, details?)`

返回更新后日历的 ID（`Promise<string>`）。仅支持修改 `color`；`title`、`name` 只能保持原值。传入非空 `source` 或 `type`，或传入 `sourceId`、`timeZone`、`isVisible`、`isSynced`，会报 `ERR_CALENDAR_UNSUPPORTED`。

#### `Calendar.deleteCalendarAsync(id)`

返回 `Promise<void>`，删除指定日历。日历不存在时会报 `ERR_CALENDAR_NOT_FOUND`。

#### `Calendar.getEventsAsync(calendarIds, startDate, endDate)`

返回 `Promise<Event[]>`，按开始时间排序，查询指定日历在日期范围内的日程。重复日程按该范围内的实例返回；每个实例的 `id` 是系列 ID，`startDate` 和 `endDate` 是实例时间。`calendarIds` 不能为空；结束时间早于开始时间时会报 `ERR_CALENDAR_INVALID_DATE_RANGE`。

#### `Calendar.getEventAsync(id, recurringEventOptions?)`

返回 `Promise<Event>`。重复日程按 ID 查询时返回系列信息，`recurringEventOptions` 不生效。日程不存在时会报 `ERR_CALENDAR_EVENT_NOT_FOUND`。

#### `Calendar.createEventAsync(calendarId, eventData?)`

返回新日程的 ID（`Promise<string>`）。`startDate` 和 `endDate` 必填，结束时间不能早于开始时间。支持 `title`、`location`、`startDate`、`endDate`、`timeZone`、`allDay`、`notes`、`alarms` 和 `recurrenceRule`。提醒只接受整数分钟的 `relativeOffset`，`method` 只接受 `alert` 和 `default`；提醒不支持 `absoluteDate` 和 `structuredLocation`。`availability` 只接受 `notSupported`，`status` 只接受 `none`。日历不存在时报 `ERR_CALENDAR_NOT_FOUND`。

- 日程字段 `url`、`endTimeZone`、`creationDate`、`lastModifiedDate`、`originalStartDate`、`isDetached`、`organizer`、`organizerEmail`、`accessLevel`、`guestsCanModify`、`guestsCanInviteOthers`、`guestsCanSeeGuests`、`originalId` 和 `instanceId` 传入非空值时不支持。

#### `Calendar.updateEventAsync(id, details?, recurringEventOptions?)`

返回日程 ID（`Promise<string>`）。仅更新明确传入的字段；`null` 可清空 `title`、`location`、`notes`、`timeZone` 和 `alarms`，并将 `allDay` 设为 `false`。只更改全天标记而未传 `alarms` 时，已有提醒随日期基准调整，偏移量保持不变。更新重复规则会替换原规则并保留排除日期。

- `instanceStartDate` 和 `futureEvents: true` 不支持，不能单独修改重复日程的某个实例或后续实例。
- 已有重复规则不能清除；传入 `recurrenceRule: null` 会报 `ERR_CALENDAR_UNSUPPORTED`。
- 不能将日程移至其他日历。
- 提醒对象只接受整数分钟的 `relativeOffset` 和 `alert` 或 `default` 方法；`absoluteDate`、`structuredLocation` 不支持。
- 日程字段 `url`、`endTimeZone`、`creationDate`、`lastModifiedDate`、`originalStartDate`、`isDetached`、`organizer`、`organizerEmail`、`accessLevel`、`guestsCanModify`、`guestsCanInviteOthers`、`guestsCanSeeGuests`、`originalId` 和 `instanceId` 传入非空值时不支持。

#### `Calendar.deleteEventAsync(id, recurringEventOptions?)`

返回 `Promise<void>`。对重复日程执行时会删除整个系列；`instanceStartDate` 和 `futureEvents: true` 不支持。日程不存在时报 `ERR_CALENDAR_EVENT_NOT_FOUND`。

#### `Calendar.getAttendeesForEventAsync(id, recurringEventOptions?)`

返回 `Promise<Attendee[]>`，读取日程参与者。`recurringEventOptions` 不生效；本地新建的日程返回空数组。

#### `Calendar.createEventInCalendarAsync(eventData?, presentationOptions?)`

返回 `Promise<DialogEventResult>`，打开系统新建日程页面，不要求日历权限。支持 `title`、`location`、`startDate`、`endDate`、`allDay`、`notes`、`alarms` 和 `recurrenceRule`。保存时 `action` 为 `saved` 且 `id` 为新日程 ID；取消时 `action` 为 `canceled` 且 `id` 为 `null`。省略日期时从当前时间开始，默认持续一小时。页面自行选择日历，传入 `calendarId`、非空 `timeZone` 或不支持的日程字段会报错；`presentationOptions` 不生效。保存的日程若不在当前权限范围内，之后可能无法通过日历查询 API 读取。已有页面尚未关闭时再次调用会报 `ERR_CALENDAR_DIALOG_PENDING`。

#### `Calendar.openEventInCalendar(id)`

- HarmonyOS 没有打开已有日程的系统查看页面，此方法不执行操作。

#### `Calendar.openEventInCalendarAsync(params, presentationOptions?)`

- HarmonyOS 没有打开已有日程的系统查看页面；调用不可用。

#### `Calendar.editEventInCalendarAsync(params, presentationOptions?)`

- HarmonyOS 暂不提供打开已有日程的系统编辑页面；调用不可用。

#### `Calendar.createAttendeeAsync(eventId, details?)`

- HarmonyOS 只提供参与者读取，不支持创建参与者。

#### `Calendar.updateAttendeeAsync(id, details?)`

- HarmonyOS 只提供参与者读取，不支持更新参与者。

#### `Calendar.deleteAttendeeAsync(id)`

- HarmonyOS 只提供参与者读取，不支持删除参与者。

#### `Calendar.getRemindersAsync(calendarIds, status, startDate, endDate)`

- HarmonyOS 日历不提供提醒事项数据。

#### `Calendar.getReminderAsync(id)`

- HarmonyOS 日历不提供提醒事项数据。

#### `Calendar.createReminderAsync(calendarId, reminderData?)`

- HarmonyOS 日历不提供提醒事项数据。

#### `Calendar.updateReminderAsync(id, details?)`

- HarmonyOS 日历不提供提醒事项数据。

#### `Calendar.deleteReminderAsync(id)`

- HarmonyOS 日历不提供提醒事项数据。

#### `Calendar.getRemindersPermissionsAsync()`

- HarmonyOS 不提供提醒事项权限。

#### `Calendar.requestRemindersPermissionsAsync()`

- HarmonyOS 不提供提醒事项权限。

#### `Calendar.getSourcesAsync()`

- 日历来源信息随日历返回，不能单独查询。

#### `Calendar.getSourceAsync(id)`

- 日历来源信息随日历返回，不能单独查询。

#### `Calendar.getDefaultCalendarSync()`

- HarmonyOS 只提供异步日历查询。

#### `Calendar.getSourcesSync()`

- 日历来源信息随日历返回，不能单独同步查询。

#### `Calendar.presentPicker()`

- HarmonyOS 不提供系统日历选择器。

#### `getCalendarPermissions(writeOnly?)`

返回 `Promise<PermissionResponse>`，查询日历读写权限。`writeOnly` 不改变同时查询读写权限的行为。

#### `requestCalendarPermissions(writeOnly?)`

返回 `Promise<PermissionResponse>`，同时申请日历读写权限。`writeOnly` 不改变申请范围。

#### `getRemindersPermissions()`

- HarmonyOS 不提供提醒事项权限。

#### `requestRemindersPermissions()`

- HarmonyOS 不提供提醒事项权限。

#### `getCalendars(entityType?)`

返回 `Promise<ExpoCalendar[]>`。`entityType` 可省略或为 `EntityTypes.EVENT`；提醒事项日历不支持。普通权限下仅返回系统默认日历和当前应用创建的日历账户。

#### `createCalendar(details?)`

返回新建的 `ExpoCalendar` 对象（`Promise<ExpoCalendar>`）。`title` 必填；创建类型、颜色和不支持字段的规则与 `Calendar.createCalendarAsync()` 相同。

#### `listEvents(calendars, startDate, endDate)`

返回 `Promise<ExpoCalendarEvent[]>`，按开始时间排序查询指定日历的日程。`calendars` 可包含日历 ID 或 `ExpoCalendar` 对象。重复日程按日期范围展开为实例；日期范围无效或未指定日历时会报错。

#### `ExpoCalendar.get(calendarId)`

返回指定 ID 的 `ExpoCalendar` 对象。ID 不存在时报 `ERR_CALENDAR_NOT_FOUND`。

#### `ExpoCalendar.createEvent(details)`

在该日历中新建日程并返回 `Promise<ExpoCalendarEvent>`。`startDate`、`endDate` 必填；支持的字段与 `Calendar.createEventAsync()` 相同。

#### `ExpoCalendar.listEvents(startDate, endDate)`

返回该日历在日期范围内的 `ExpoCalendarEvent[]`。开始和结束日期必填；重复日程按范围展开。

#### `ExpoCalendar.update(details)`

返回 `Promise<void>`，只支持修改 `color`。`title` 只能保持原值。

#### `ExpoCalendar.delete()`

返回 `Promise<void>`，删除该日历。

#### `ExpoCalendar.addEventWithForm(options?)`

- HarmonyOS 暂不提供该对象方法。系统新建日程页面可通过 `Calendar.createEventInCalendarAsync()` 打开。

#### `ExpoCalendar.listReminders(...)`

- HarmonyOS 日历不提供提醒事项数据。

#### `ExpoCalendar.createReminder(details?)`

- HarmonyOS 日历不提供提醒事项数据。

#### `ExpoCalendarEvent.get(eventId)`

返回指定 ID 的 `ExpoCalendarEvent` 对象。ID 不存在时报 `ERR_CALENDAR_EVENT_NOT_FOUND`。

#### `ExpoCalendarEvent.getOccurrenceSync(recurringEventOptions?)`

无选项时返回该日程对象本身。

- HarmonyOS 不支持按 `instanceStartDate` 获取某个重复实例，也不支持传入 `futureEvents: true`。

#### `ExpoCalendarEvent.getAttendees()`

返回 `Promise<ExpoCalendarAttendee[]>`，读取参与者。

#### `ExpoCalendarEvent.update(details)`

返回 `Promise<void>`。更新规则与 `Calendar.updateEventAsync()` 相同；可清空的字段为 `title`、`location`、`notes`、`timeZone` 和 `alarms`。

#### `ExpoCalendarEvent.delete()`

返回 `Promise<void>`，删除整个日程系列。

#### `ExpoCalendarEvent.createAttendee(attendee)`

- HarmonyOS 只提供参与者读取，不支持创建参与者。

#### `ExpoCalendarEvent.openInCalendar(params?)`

- HarmonyOS 没有打开已有日程的系统查看页面；调用不可用。

#### `ExpoCalendarEvent.editInCalendar(params?)`

- HarmonyOS 暂不提供打开已有日程的系统编辑页面；调用不可用。

#### `ExpoCalendarAttendee.update(details)`

- HarmonyOS 只提供参与者读取，不支持更新参与者。

#### `ExpoCalendarAttendee.delete()`

- HarmonyOS 只提供参与者读取，不支持删除参与者。

#### `ExpoCalendarReminder.get(reminderId)`

- HarmonyOS 日历不提供提醒事项数据。

#### `ExpoCalendarReminder.update(details)`

- HarmonyOS 日历不提供提醒事项数据。

#### `ExpoCalendarReminder.delete()`

- HarmonyOS 日历不提供提醒事项数据。

### Types

#### `Alarm`

`relativeOffset` 为整数分钟，负数表示提前，全天日程以当天午夜为基准。写入时 `method` 只接受 `alert` 和 `default`；读取时 `method` 为 `alert`。`absoluteDate` 和 `structuredLocation` 不支持。

#### `AlarmLocation`

- HarmonyOS 不支持基于位置的提醒。

#### `Attendee`

读取时包含 `name`、`role`、`status`、`type` 和 `email`。`role` 为 `organizer`、`attendee` 或 `unknown`；`status` 为 `accepted`、`declined`、`tentative`、`pending` 或 `unknown`；`type` 为 `required`、`optional`、`resource` 或 `unknown`。不返回 `id`、`isCurrentUser` 和 `url`。

#### `Calendar`

返回字段包括 `id`、`title`、`name`、`source`、`type`、`color`、`entityType`、`allowsModifications`、`allowedAvailabilities`、`isPrimary` 和 `ownerAccount`。颜色为不含透明度的 `#RRGGBB`。`entityType` 为 `event`，`allowsModifications` 为 `true`，`allowedAvailabilities` 为空数组。`sourceId`、`timeZone`、`isVisible`、`isSynced`、`accessLevel`、`allowedReminders` 和 `allowedAttendeeTypes` 不返回。

#### `CalendarDialogParams`

- HarmonyOS 不提供打开已有日程的系统页面。

#### `DaysOfTheWeek`

`dayOfTheWeek` 从 `1`（周日）到 `7`（周六）。`weekNumber` 可为 `1` 到 `5`；省略或传 `0` 表示不限定周次，负数不支持。

#### `DialogEventResult`

`action` 为 `saved` 或 `canceled`。保存时 `id` 是新日程 ID，取消时为 `null`。

#### `Event`

读取字段包括 `id`、`calendarId`、`title`、`location`、`timeZone`、`notes`、`alarms`、`startDate`、`endDate`、`allDay`、`availability` 和 `status`。日期为 ISO 字符串，空 `location` 为 `null`。`availability` 始终为 `notSupported`，`status` 始终为 `none`。非重复日程的 `recurrenceRule` 为 `null`；无法表示的系统重复规则为 `undefined`。系统提供组织者邮箱时返回 `organizerEmail`。不返回 `creationDate`、`lastModifiedDate`、`originalStartDate`、`isDetached`、`organizer`、`originalId`、`instanceId`、`accessLevel`、`guestsCanModify`、`guestsCanInviteOthers`、`guestsCanSeeGuests`、`url` 和 `endTimeZone`。

#### `ModifiableCalendarProperties`

新对象 API 可修改的日历字段类型。HarmonyOS 仅支持 `color`；修改 `title` 只有在值未变化时才被接受。

#### `ModifiableEventProperties`

新对象 API 可修改的日程字段类型。实际支持 `title`、`location`、`timeZone`、`notes`、`alarms`、`recurrenceRule`、`startDate`、`endDate` 和 `allDay`；`availability` 只接受 `notSupported`。

#### `ModifiableReminderProperties`

- HarmonyOS 日历不提供提醒事项数据。

#### `OpenEventDialogResult`

- HarmonyOS 不提供打开已有日程的系统页面。

#### `OpenEventPresentationOptions`

- HarmonyOS 不提供打开已有日程的系统页面。

#### `Organizer`

不返回 `Organizer` 对象；如系统提供组织者信息，只返回日程的 `organizerEmail`。

#### `PermissionExpiration`

类型为 `'never' | number`；HarmonyOS 上始终为 `'never'`。

#### `PermissionHookOptions`

权限钩子的可选项。`writeOnly` 不改变 HarmonyOS 上读写权限同时查询或申请的行为。

#### `PermissionResponse`

包含 `status`、`granted`、`canAskAgain` 和 `expires`。`status` 为 `granted`、`denied` 或 `undetermined`；`expires` 始终为 `'never'`。

#### `PresentationOptions`

`startNewActivityTask` 在 HarmonyOS 上不生效。

#### `RecurrenceRule`

`frequency` 必填，支持 `daily`、`weekly`、`monthly` 和 `yearly`。非正整数 `interval` 按 `1` 处理；非正整数 `occurrence` 表示无限重复；`endDate` 优先于 `occurrence`，且必须晚于 Unix 纪元。

支持按天、周、月和年重复。`daysOfTheWeek` 的 `weekNumber` 为 `1` 到 `5`，省略或传 `0` 表示不限定周次。可查询农历日程及其重复实例，但无法用 Expo 重复规则修改农历日程。部分复杂选择条件、`setPositions`、负序号及混合带周次和不带周次的星期条件不支持。只更新其他字段时会保留现有重复规则。

#### `RecurringEventOptions`

`instanceStartDate` 和 `futureEvents: true` 不支持；不能单独获取、修改或删除重复日程中的某次或后续实例。

#### `Reminder`

- HarmonyOS 日历不提供提醒事项数据。

#### `Source`

日历返回的 `source` 包含 `name`、`type` 和 `isLocalAccount`；不返回 `id`。邮件账户的来源 `type` 为 `email`，日历的 `type` 则为 `unknown`。

#### `AddEventWithFormOptions`

新对象日历表单参数包含 `title`、`startDate`、`endDate`、`allDay`、`notes`、`location`、`url`、`alarms`、`recurrenceRule` 和 `PresentationOptions`。HarmonyOS 暂不提供 `ExpoCalendar.addEventWithForm()`。

### Enums

#### `AlarmMethod`

成员有 `ALARM`、`ALERT`、`EMAIL`、`SMS` 和 `DEFAULT`。写入提醒时仅接受 `ALERT` 和 `DEFAULT`；读取时始终为 `ALERT`。

#### `AttendeeRole`

成员有 `ATTENDEE`、`CHAIR`、`NONE`、`NON_PARTICIPANT`、`OPTIONAL`、`ORGANIZER`、`PERFORMER`、`REQUIRED`、`SPEAKER` 和 `UNKNOWN`。读取时可能为 `ORGANIZER`、`ATTENDEE` 或 `UNKNOWN`。

#### `AttendeeStatus`

成员有 `ACCEPTED`、`COMPLETED`、`DECLINED`、`DELEGATED`、`IN_PROCESS`、`INVITED`、`NONE`、`PENDING`、`TENTATIVE` 和 `UNKNOWN`。读取时可能为 `ACCEPTED`、`DECLINED`、`TENTATIVE`、`PENDING` 或 `UNKNOWN`。

#### `AttendeeType`

成员有 `GROUP`、`NONE`、`OPTIONAL`、`PERSON`、`REQUIRED`、`RESOURCE`、`ROOM` 和 `UNKNOWN`。读取时可能为 `REQUIRED`、`OPTIONAL`、`RESOURCE` 或 `UNKNOWN`。

#### `Availability`

成员有 `BUSY`、`FREE`、`NOT_SUPPORTED`、`TENTATIVE` 和 `UNAVAILABLE`。`availability` 始终为 `NOT_SUPPORTED`；写入时只接受该值。

#### `CalendarAccessLevel`

- 枚举成员为 `CONTRIBUTOR`、`EDITOR`、`FREEBUSY`、`OVERRIDE`、`OWNER`、`READ`、`RESPOND`、`ROOT` 和 `NONE`。HarmonyOS 不返回日历访问级别。

#### `CalendarDialogResultActions`

成员为 `done`、`canceled`、`deleted`、`responded` 和 `saved`。HarmonyOS 新建日程页面只返回 `saved` 或 `canceled`。

#### `CalendarType`

成员有 `BIRTHDAYS`、`CALDAV`、`EXCHANGE`、`LOCAL`、`SUBSCRIBED` 和 `UNKNOWN`。创建日历时接受 `LOCAL`、`CALDAV`、`BIRTHDAYS` 和 `SUBSCRIBED`；邮件账户需用字符串 `email`，读取日历 `type` 时显示为 `UNKNOWN`。不支持创建 `EXCHANGE` 日历。

#### `DayOfTheWeek`

成员依次为 `Sunday`（`1`）、`Monday`（`2`）、`Tuesday`（`3`）、`Wednesday`（`4`）、`Thursday`（`5`）、`Friday`（`6`）和 `Saturday`（`7`）。

#### `EntityTypes`

成员为 `EVENT` 和 `REMINDER`。HarmonyOS 只支持 `EVENT`。

#### `EventAccessLevel`

- 成员为 `CONFIDENTIAL`、`PRIVATE`、`PUBLIC` 和 `DEFAULT`。HarmonyOS 不返回日程访问级别。

#### `EventStatus`

成员为 `CANCELED`、`CONFIRMED`、`NONE` 和 `TENTATIVE`。`status` 始终为 `NONE`；写入时只接受该值。

#### `Frequency`

成员为 `DAILY`、`WEEKLY`、`MONTHLY` 和 `YEARLY`，均支持。

#### `MonthOfTheYear`

成员依次为 `January`（`1`）、`February`（`2`）、`March`（`3`）、`April`（`4`）、`May`（`5`）、`June`（`6`）、`July`（`7`）、`August`（`8`）、`September`（`9`）、`October`（`10`）、`November`（`11`）和 `December`（`12`）。

#### `ReminderStatus`

成员为 `COMPLETED` 和 `INCOMPLETE`；HarmonyOS 日历不提供提醒事项数据。

#### `SourceType`

成员有 `BIRTHDAYS`、`CALDAV`、`EXCHANGE`、`LOCAL`、`MOBILEME` 和 `SUBSCRIBED`。创建日历来源时接受 `LOCAL`、`CALDAV`、`BIRTHDAYS` 和 `SUBSCRIBED`；邮件来源使用字符串 `email`。不支持 `EXCHANGE` 和 `MOBILEME`。

### Error codes

#### `E_MISSING_PERMISSIONS`

调用需要的日历读权限或写权限尚未授予。

#### `ERR_CALENDAR_DIALOG_PENDING`

系统新建日程页面尚未关闭时再次调用 `createEventInCalendarAsync()`。

#### `ERR_CALENDAR_EVENT_NOT_FOUND`

指定日程不存在或当前权限范围内不可访问。

#### `ERR_CALENDAR_INVALID_ALARM`

提醒时间不是有效的整数分钟或超出可用范围。

#### `ERR_CALENDAR_INVALID_ALARMS`

`alarms` 不是数组。

#### `ERR_CALENDAR_INVALID_ARGUMENT`

参数类型或必需参数不符合要求。

#### `ERR_CALENDAR_INVALID_ID`

日历或日程 ID 不是有效的数字字符串。

#### `ERR_CALENDAR_INVALID_DATE`

日期不是有效的 ISO 8601 字符串或时间戳。

#### `ERR_CALENDAR_INVALID_COLOR`

颜色不是可接受的颜色字符串或数值。

#### `ERR_CALENDAR_INVALID_DATE_RANGE`

结束时间早于开始时间。

#### `ERR_CALENDAR_INVALID_ENTITY`

`entityType` 不是支持的日历实体类型。

#### `ERR_CALENDAR_INVALID_RECURRENCE`

重复规则中包含无效频率、日期、星期、间隔或次数。

#### `ERR_CALENDAR_INVALID_SOURCE`

创建日历时传入的来源类型不受支持。

#### `ERR_CALENDAR_MISSING_DATE`

新建日程缺少 `startDate` 或 `endDate`。

#### `ERR_CALENDAR_NOT_FOUND`

日历不存在或当前权限范围内不可访问。

#### `ERR_CALENDAR_NOT_SAVED`

创建日历失败。

#### `ERR_EVENT_NOT_SAVED`

创建日程失败。

#### `ERR_CALENDAR_PERMISSION_REQUEST`

系统无法完成权限申请；检查应用声明的日历权限。

#### `ERR_CALENDAR_UNSUPPORTED`

操作或参数不受 HarmonyOS 日历能力支持，例如编辑重复日程单个实例、写入只读字段或请求提醒事项。

#### `ERR_UNAVAILABLE`

设备不支持日历功能，或调用了 HarmonyOS 不提供的日历页面或同步 API。

### Permissions

#### `ohos.permission.READ_CALENDAR`

读取日历和日程需要此权限。

#### `ohos.permission.WRITE_CALENDAR`

创建、修改或删除日历和日程需要此权限。

#### `ohos.permission.READ_WHOLE_CALENDAR`

API 21 及以上可声明此受限权限以读取其他应用创建的日程；需先获得 HarmonyOS 权限批准。

#### `ohos.permission.WRITE_WHOLE_CALENDAR`

API 21 及以上可声明此受限权限以修改其他应用创建的日程；需先获得 HarmonyOS 权限批准。

## 权限

读取日历和日程需要 `ohos.permission.READ_CALENDAR`，创建、修改或删除日历和日程还需要 `ohos.permission.WRITE_CALENDAR`。缺少操作所需的权限时，相应 API 调用会失败。应用可以通过下方配置插件自定义权限用途说明。

普通权限可以读取系统默认日历和当前应用创建的日历账户，但只能读写这些账户中由当前应用创建的日程。访问其他应用创建的日程需要单独申请全量日历权限，具体声明方式见项目配置。

在 [Calendar Kit API 21 及以上](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-calendarmanager/) 上，调用 `requestCalendarPermissionsAsync()` 时会优先请求宿主应用已声明的全量权限。若用户只授予普通权限，应用仍可访问普通权限范围内的日历和日程。

### 全量日历权限

确实需要读取或修改其他应用创建的日程时，应用应按华为的 [受限权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions) 自行向 AGC 申请所需权限，取得批准后再在应用中声明。以下是仅需全量读取时的配置：

```json
{
  "name": "ohos.permission.READ_WHOLE_CALENDAR",
  "reason": "$string:expo_calendar_read_permission_reason",
  "usedScene": { "when": "inuse" }
}
```

将此项添加到 `app.json` 的 `expo.harmony.permissions` 数组后重新 prebuild 和构建。bare 工程可写入入口 `module.json5` 的 `requestPermissions`。确实需要全量写入时，同样单独申请和声明 `ohos.permission.WRITE_WHOLE_CALENDAR`，可使用 `$string:expo_calendar_write_permission_reason`。签名使用包含获批权限的 Profile。应用包和配置插件默认只声明普通权限。

### 自定义权限用途说明

需要自定义 HarmonyOS 日历权限的用途说明时，在应用配置中添加：

```json
{
  "expo": {
    "plugins": [
      [
        "@expo-harmony/expo-calendar",
        {
          "readCalendarPermission": "用于显示您的日历和日程",
          "writeCalendarPermission": "用于保存您创建和编辑的日程"
        }
      ]
    ]
  }
}
```

`calendarPermission` 可以一次设置读写的用途说明，`readCalendarPermission` 和 `writeCalendarPermission` 分别优先于它。选项只接受非空字符串，不支持用 `false` 关闭权限。未配置时沿用默认文案「用于读取日历和日程」和「用于创建、更新和删除日历及日程」。修改配置后需要重新 prebuild 并构建应用。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
