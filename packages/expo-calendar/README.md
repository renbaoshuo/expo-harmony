# @expo-harmony/expo-calendar

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-calendar) | [官方文档](https://docs.expo.dev/versions/v55.0.0/sdk/calendar/)

为 HarmonyOS 上的 React Native 应用提供 Expo Calendar 的原生实现，与官方同版本的 `expo-calendar` 配套使用。支持日历和日程读写、重复日程查询、提醒、参与者读取，以及系统新建日程页面。

## 安装

```bash
npm install @expo-harmony/expo-calendar expo-calendar@55.0.15
```

鸿蒙适配会通过 Autolinking 自动接入，使用默认权限说明时无需额外配置。最低支持 HarmonyOS 5.1.0（API 18），宿主的 `compatibleSdkVersion` 也需满足此要求。

读写日历和日程需要 `ohos.permission.READ_CALENDAR` 和 `ohos.permission.WRITE_CALENDAR`，本包已经声明并配置好默认用途说明，可通过下方的配置插件自定义文本，无需再次声明权限。权限声明挂在 `EntryAbility` 名下，宿主入口 Ability 如果叫别的名字，需要改成自己的 Ability 名称。这两个都是普通权限，只能访问系统默认日历和当前应用创建的日历及日程，读不到设备中的全部日程。日历和日程的读写接口要求两个权限均已授予，否则抛出 `E_MISSING_PERMISSIONS`。

业务代码依旧使用官方包：

```ts
import * as Calendar from 'expo-calendar';

const permission = await Calendar.requestCalendarPermissionsAsync();
if (permission.granted) {
  const calendars = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
}
```

## Config Plugin

`readCalendarPermission`、`writeCalendarPermission` 和 `calendarPermission` 是 HarmonyOS 的构建期配置扩展，需要自定义读写权限的用途说明时，在应用配置中添加：

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

## API 对照表

### System dialogs

#### `Calendar.createEventInCalendarAsync(eventData?, presentationOptions?)`

返回 `Promise<DialogEventResult>`，打开系统新建日程页面。不需要日历权限。用户保存时 `action` 为 `saved`、`id` 为新日程的 ID，取消时 `action` 为 `canceled`、`id` 为 `null`。

页面自行选择日历，`calendarId` 和 `timeZone` 不支持，传入时拒绝。省略日期时默认从当前时间开始、持续一小时。`presentationOptions` 不生效。已有对话框未关闭时再次调用抛出 `ERR_CALENDAR_DIALOG_PENDING`。系统页面保存的日程可能不在本应用的普通读权限范围内。

> **未实现的内容**
>
> - `openEventInCalendar(id)`、`openEventInCalendarAsync(params, presentationOptions?)`、`editEventInCalendarAsync(params, presentationOptions?)`：Calendar Kit 没有打开已有日程的查看或编辑页面的接口，调用抛出 `UnavailabilityError`。

### Hooks

#### `useCalendarPermissions(options?)`

返回 `[PermissionResponse | null, request, get]`，读取或申请日历权限，取值与 `getCalendarPermissionsAsync()`、`requestCalendarPermissionsAsync()` 一致。`options` 见 `PermissionHookOptions`。

> **未实现的内容**
>
> - `useRemindersPermissions(options?)`：HarmonyOS 上没有提醒事项权限，调用抛出 `UnavailabilityError`。

### Methods

#### `Calendar.isAvailableAsync()`

返回 `Promise<boolean>`，设备是否具备日历数据能力。不检查权限。返回 `false` 时日历和日程接口都没有注册，调用抛出 `UnavailabilityError`。

#### `Calendar.getCalendarPermissionsAsync()`

返回 `Promise<PermissionResponse>`，查询日历读写权限。两个权限都授予时 `granted` 为 `true`，`expires` 恒为 `'never'`。

API 20 及以上直接读取系统权限状态，未决定返回 `undetermined`，拒绝返回 `denied`；API 18–19 只能识别本应用申请时被明确拒绝的情况，其他途径的拒绝和系统设置重置读不到。明确拒绝后 `canAskAgain` 为 `false`。

#### `Calendar.requestCalendarPermissionsAsync()`

返回 `Promise<PermissionResponse>`，同时申请读权限和写权限。并发调用复用同一次申请，不会重复弹窗。权限未在 `module.json5` 中声明时抛出 `ERR_CALENDAR_PERMISSION_REQUEST`。系统不再允许申请或只能在设置页开启时 `canAskAgain` 为 `false`。

#### `Calendar.requestPermissionsAsync()`

返回 `Promise<PermissionResponse>`，官方已标记废弃，行为与 `requestCalendarPermissionsAsync()` 相同。

#### `Calendar.getCalendarsAsync(entityType?)`

返回 `Promise<Calendar[]>`，读取可访问的日历。`entityType` 只接受 `EntityTypes.EVENT`，传 `REMINDER` 时抛出 `ERR_CALENDAR_UNSUPPORTED`。普通权限下只返回系统默认日历和当前应用创建的日历，不代表设备中的全部日历。默认日历的 `isPrimary` 为 `true`。

#### `Calendar.getDefaultCalendarAsync()`

返回 `Promise<Calendar>`，系统默认日历。官方标记为 iOS 专属，HarmonyOS 上可用。

#### `Calendar.createCalendarAsync(details?)`

返回 `Promise<string>`，新建日历并返回其 ID。`title` 必填。

`source.type` 或顶层 `type` 决定日历类型，支持 `local`、`email`、`birthdays`、`caldav`、`subscribed`，省略时为 `local`。`color` 接受颜色字符串或数值。`sourceId`、`timeZone`、`isVisible`、`isSynced` 不支持，传入时拒绝。

#### `Calendar.updateCalendarAsync(id, details?)`

返回 `Promise<string>`，更新已有日历并返回其 ID。只支持修改颜色。`title`、`name` 只在值与当前不同时拒绝，`source` 和 `type` 传入任何非空值都拒绝，错误码为 `ERR_CALENDAR_UNSUPPORTED`。`sourceId`、`timeZone`、`isVisible`、`isSynced` 不支持。

#### `Calendar.deleteCalendarAsync(id)`

返回 `Promise<void>`，删除日历。ID 不存在时抛出 `ERR_CALENDAR_NOT_FOUND`。

#### `Calendar.getEventsAsync(calendarIds, startDate, endDate)`

返回 `Promise<Event[]>`，查询指定日历在时间区间内的日程，按开始时间排序。重复日程按实例展开，每个实例的 `id` 是系列的 ID，`startDate` 和 `endDate` 是本次实例的时间。

`calendarIds` 不能为空，`endDate` 早于 `startDate` 时抛出 `ERR_CALENDAR_INVALID_DATE_RANGE`。

#### `Calendar.getEventAsync(id, recurringEventOptions?)`

返回 `Promise<Event>`，按 ID 查询单个日程。重复日程返回整个系列，`recurringEventOptions` 不生效。ID 不存在时抛出 `ERR_CALENDAR_EVENT_NOT_FOUND`。

#### `Calendar.createEventAsync(calendarId, eventData?)`

返回 `Promise<string>`，在指定日历中新建日程并返回其 ID。`startDate` 和 `endDate` 必填，`endDate` 不能早于 `startDate`。日历不存在时抛出 `ERR_CALENDAR_NOT_FOUND`。

支持 `title`、`location`、`startDate`、`endDate`、`timeZone`、`allDay`、`notes`、`alarms` 和 `recurrenceRule`。`alarms` 只接受整数分钟的 `relativeOffset`，`absoluteDate` 和 `structuredLocation` 不支持。`url`、`endTimeZone`、`creationDate`、`lastModifiedDate`、`originalStartDate`、`isDetached`、`organizer`、`organizerEmail`、`accessLevel`、`guestsCanModify`、`guestsCanInviteOthers`、`guestsCanSeeGuests`、`originalId`、`instanceId` 传入非空值时拒绝。`availability` 和 `status` 只接受 `notSupported` 和 `none`。

#### `Calendar.updateEventAsync(id, details?, recurringEventOptions?)`

返回 `Promise<string>`，更新日程并返回其 ID。只修改明确传入的字段，未传入的字段保持原值。`null` 可以清空 `title`、`location`、`notes`、`timeZone` 和 `alarms`，并把 `allDay` 设为 `false`。并发调用按顺序执行。

只改全天标记、不传 `alarms` 时，已有提醒会按新的基准自动平移，相对偏移保持不变。修改重复规则会替换原有规则，排除日期保留。

`instanceStartDate` 和 `futureEvents: true` 不支持，单次或未来重复实例无法单独修改，抛出 `ERR_CALENDAR_UNSUPPORTED`。已有重复规则无法清除，`recurrenceRule: null` 会被拒绝。日程不能移动到其他日历。

#### `Calendar.deleteEventAsync(id, recurringEventOptions?)`

返回 `Promise<void>`，删除日程。重复日程删除整个系列，`instanceStartDate` 和 `futureEvents: true` 不支持。ID 不存在时抛出 `ERR_CALENDAR_EVENT_NOT_FOUND`。

#### `Calendar.getAttendeesForEventAsync(id, recurringEventOptions?)`

返回 `Promise<Attendee[]>`，读取日程的参与者，只读。`recurringEventOptions` 不生效。本地新建的日程返回空数组。

> **未实现的内容**
>
> - `createAttendeeAsync()`、`updateAttendeeAsync()`、`deleteAttendeeAsync()`：Calendar Kit 只提供参与者读取，没有增删改接口，调用抛出 `UnavailabilityError`。
> - `getRemindersAsync()`、`getReminderAsync()`、`createReminderAsync()`、`updateReminderAsync()`、`deleteReminderAsync()`：提醒事项在 HarmonyOS 上没有对应的数据，调用抛出 `UnavailabilityError`。
> - `getRemindersPermissionsAsync()`、`requestRemindersPermissionsAsync()`：提醒事项权限不存在，调用抛出 `UnavailabilityError`。
> - `getSourcesAsync()`、`getSourceAsync()`：日历来源只能随日历一起读取，没有独立的查询接口，调用抛出 `UnavailabilityError`。

### Types

#### `Alarm`

`relativeOffset?: number`，整数分钟，负数表示提前。写入时 `method` 只接受 `alert` 和 `default`，读取时恒为 `alert`。`absoluteDate` 和 `structuredLocation` 不支持。全天日程的提醒按 Expo 的午夜基准换算。

#### `Attendee`

`name`、`role`、`status`、`type`、`email` 返回。`role` 为 `organizer`、`attendee` 或 `unknown`，`status` 为 `accepted`、`declined`、`tentative`、`pending` 或 `unknown`，`type` 为 `required`、`optional`、`resource` 或 `unknown`。`id`、`isCurrentUser`、`url` 不返回。

#### `Calendar`

`id`、`title`、`name`、`source`、`type`、`color`、`entityType`、`allowsModifications`、`allowedAvailabilities`、`isPrimary`、`ownerAccount` 返回。`color` 为 `#RRGGBB`，省略透明度。`entityType` 恒为 `event`，`allowsModifications` 恒为 `true`，`allowedAvailabilities` 恒为空数组。`sourceId`、`timeZone`、`isVisible`、`isSynced`、`accessLevel`、`allowedReminders`、`allowedAttendeeTypes` 不返回。

#### `DaysOfTheWeek`

`dayOfTheWeek` 为 1（周日）到 7（周六）。`weekNumber` 取 1 到 5，省略或传 `0` 表示不带周次，负序号不支持。

#### `DialogEventResult`

`action` 为 `saved` 或 `canceled`，`id` 在保存时为日程 ID，取消时为 `null`。

#### `Event`

`id`、`calendarId`、`title`、`location`、`timeZone`、`notes`、`alarms`、`recurrenceRule`、`startDate`、`endDate`、`allDay`、`availability`、`status` 返回。`startDate` 和 `endDate` 为 ISO 字符串，`location` 为空时返回 `null`。`availability` 恒为 `notSupported`，`status` 恒为 `none`。`creationDate`、`lastModifiedDate`、`originalStartDate`、`isDetached`、`organizer`、`organizerEmail`、`originalId`、`instanceId`、`accessLevel`、`guestsCanModify`、`guestsCanInviteOthers`、`guestsCanSeeGuests`、`url`、`endTimeZone` 不返回。

#### `PermissionExpiration`

`'never' | number`，HarmonyOS 上恒为 `never`。

#### `PermissionHookOptions`

权限钩子的可选项，`options` 可省略。

#### `PermissionResponse`

`status`、`granted`、`canAskAgain`、`expires`。`expires` 恒为 `never`。

#### `PresentationOptions`

`startNewActivityTask` 在 HarmonyOS 上不生效。

#### `RecurrenceRule`

`frequency` 必填，支持 `daily`、`weekly`、`monthly`、`yearly`。`interval` 为非正整数时按 `1` 处理，`occurrence` 为非正整数时表示无限重复，`endDate` 优先于 `occurrence` 且必须晚于 Unix 纪元。

支持的选择器：每周按星期；每月按日期或带周次的星期；每年按年内日期、年内周次加星期、月份加日期，或月份加带周次的星期。不支持负序号、`setPositions`、混合带周次和不带周次的星期，以及 Calendar Kit 会忽略或覆盖的组合。农历重复日程不支持，读取或修改时拒绝。

#### `RecurringEventOptions`

`instanceStartDate` 和 `futureEvents` 在 HarmonyOS 上不支持，单次或未来重复实例无法单独修改。

#### `Source`

`name`、`type`、`isLocalAccount` 返回。`type` 取系统日历账户类型，生日来源为 `birthdays`，邮件账户为 `email`。`id` 不返回。

> **未实现的内容**
>
> - `AlarmLocation`：位置提醒不支持，没有数据来源。
> - `CalendarDialogParams`、`OpenEventDialogResult`、`OpenEventPresentationOptions`：只在打开已有日程的系统页面时使用，该功能在 HarmonyOS 上不可用。
> - `Organizer`：日程不返回组织者信息。
> - `Reminder`：提醒事项在 HarmonyOS 上没有对应的数据。

### Enums

#### `AlarmMethod`

| 成员      | 值          |
| --------- | ----------- |
| `ALARM`   | `'alarm'`   |
| `ALERT`   | `'alert'`   |
| `DEFAULT` | `'default'` |
| `EMAIL`   | `'email'`   |
| `SMS`     | `'sms'`     |

写入提醒时只接受 `ALERT` 和 `DEFAULT`，其他值拒绝。

#### `AttendeeRole`

| 成员              | 值                |
| ----------------- | ----------------- |
| `ATTENDEE`        | `'attendee'`      |
| `CHAIR`           | `'chair'`         |
| `NONE`            | `'none'`          |
| `NON_PARTICIPANT` | `'nonParticipant'` |
| `OPTIONAL`        | `'optional'`      |
| `ORGANIZER`       | `'organizer'`     |
| `PERFORMER`       | `'performer'`     |
| `REQUIRED`        | `'required'`      |
| `SPEAKER`         | `'speaker'`       |
| `UNKNOWN`         | `'unknown'`       |

读取只返回 `ORGANIZER`、`ATTENDEE` 和 `UNKNOWN`。

#### `AttendeeStatus`

| 成员         | 值             |
| ------------ | -------------- |
| `ACCEPTED`   | `'accepted'`   |
| `COMPLETED`  | `'completed'`  |
| `DECLINED`   | `'declined'`   |
| `DELEGATED`  | `'delegated'`  |
| `IN_PROCESS` | `'inProcess'`  |
| `INVITED`    | `'invited'`    |
| `NONE`       | `'none'`       |
| `PENDING`    | `'pending'`    |
| `TENTATIVE`  | `'tentative'`  |
| `UNKNOWN`    | `'unknown'`    |

读取只返回 `ACCEPTED`、`DECLINED`、`TENTATIVE`、`PENDING` 和 `UNKNOWN`。

#### `AttendeeType`

| 成员       | 值           |
| ---------- | ------------ |
| `GROUP`    | `'group'`    |
| `NONE`     | `'none'`     |
| `OPTIONAL` | `'optional'` |
| `PERSON`   | `'person'`   |
| `REQUIRED` | `'required'` |
| `RESOURCE` | `'resource'` |
| `ROOM`     | `'room'`     |
| `UNKNOWN`  | `'unknown'`  |

读取只返回 `REQUIRED`、`OPTIONAL`、`RESOURCE` 和 `UNKNOWN`。

#### `Availability`

| 成员            | 值                |
| --------------- | ----------------- |
| `BUSY`          | `'busy'`          |
| `FREE`          | `'free'`          |
| `NOT_SUPPORTED` | `'notSupported'`  |
| `TENTATIVE`     | `'tentative'`     |
| `UNAVAILABLE`   | `'unavailable'`   |

`availability` 恒为 `NOT_SUPPORTED`，写入其他值时拒绝。

#### `CalendarDialogResultActions`

| 成员        | 值            |
| ----------- | ------------- |
| `canceled`  | `'canceled'`  |
| `deleted`   | `'deleted'`   |
| `done`      | `'done'`      |
| `responded` | `'responded'` |
| `saved`     | `'saved'`     |

系统新建页面只返回 `saved` 和 `canceled`。

#### `CalendarType`

| 成员         | 值             |
| ------------ | -------------- |
| `BIRTHDAYS`  | `'birthdays'`  |
| `CALDAV`     | `'caldav'`     |
| `EXCHANGE`   | `'exchange'`   |
| `LOCAL`      | `'local'`      |
| `SUBSCRIBED` | `'subscribed'` |
| `UNKNOWN`    | `'unknown'`    |

对应系统日历账户类型，`EXCHANGE` 不会出现，写入时拒绝；系统邮件账户读取为 `UNKNOWN`。

#### `DayOfTheWeek`

| 成员        | 值  |
| ----------- | --- |
| `Sunday`    | `1` |
| `Monday`    | `2` |
| `Tuesday`   | `3` |
| `Wednesday` | `4` |
| `Thursday`  | `5` |
| `Friday`    | `6` |
| `Saturday`  | `7` |

#### `EntityTypes`

| 成员       | 值          |
| ---------- | ----------- |
| `EVENT`    | `'event'`   |
| `REMINDER` | `'reminder'` |

只支持 `EVENT`。

#### `EventStatus`

| 成员        | 值            |
| ----------- | ------------- |
| `CANCELED`  | `'canceled'`  |
| `CONFIRMED` | `'confirmed'` |
| `NONE`      | `'none'`      |
| `TENTATIVE` | `'tentative'` |

`status` 恒为 `NONE`，写入其他值时拒绝。

#### `Frequency`

| 成员      | 值          |
| --------- | ----------- |
| `DAILY`   | `'daily'`   |
| `MONTHLY` | `'monthly'` |
| `WEEKLY`  | `'weekly'`  |
| `YEARLY`  | `'yearly'`  |

四种频率都支持。

#### `MonthOfTheYear`

| 成员        | 值   |
| ----------- | ---- |
| `January`   | `1`  |
| `February`  | `2`  |
| `March`     | `3`  |
| `April`     | `4`  |
| `May`       | `5`  |
| `June`      | `6`  |
| `July`      | `7`  |
| `August`    | `8`  |
| `September` | `9`  |
| `October`   | `10` |
| `November`  | `11` |
| `December`  | `12` |

#### `PermissionStatus`

| 成员           | 值               |
| -------------- | ---------------- |
| `DENIED`       | `'denied'`       |
| `GRANTED`      | `'granted'`      |
| `UNDETERMINED` | `'undetermined'` |

#### `SourceType`

| 成员         | 值             |
| ------------ | -------------- |
| `BIRTHDAYS`  | `'birthdays'`  |
| `CALDAV`     | `'caldav'`     |
| `EXCHANGE`   | `'exchange'`   |
| `LOCAL`      | `'local'`      |
| `MOBILEME`   | `'mobileme'`   |
| `SUBSCRIBED` | `'subscribed'` |

写入日历来源时 `type` 接受 `local`、`email`、`birthdays`、`caldav`、`subscribed`，`exchange` 和 `mobileme` 拒绝。邮件账户读取为 `email`，该值不在枚举内。

> **未实现的内容**
>
> - `CalendarAccessLevel`：Android 专属枚举，写入被忽略，读取不返回。
> - `EventAccessLevel`：Android 专属枚举，写入非空值时拒绝，读取不返回。
> - `ReminderStatus`：提醒事项在 HarmonyOS 上没有对应的数据。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
