# @expo-harmony/expo-notifications

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-notifications) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/notifications/)

为 HarmonyOS 上的 React Native 应用提供 Expo Notifications 的原生实现，与官方同版本的 `expo-notifications` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 23（HarmonyOS 6.1.0）。

```bash
npm install @expo-harmony/expo-notifications expo-notifications
```

## API 对照表

### Hooks

#### `useLastNotificationResponse()`

返回最近一次 `NotificationResponse`；应用启动后尚未收到响应时为 `null`。调用 `clearLastNotificationResponse()` 后，Hook 返回 `null`。

### Constants

#### `Notifications.DEFAULT_ACTION_IDENTIFIER`

用户点击通知主体时，响应中的 `actionIdentifier` 为此常量。点击通知操作按钮时，`actionIdentifier` 为对应操作的 `identifier`。

### Methods

#### `getBadgeCountAsync()`

返回 `Promise<number>`，读取应用角标数。设备不支持角标时返回 `0`。

#### `setBadgeCountAsync(badgeCount, options?)`

返回 `Promise<boolean>`。`badgeCount` 必须是 0 到 2147483647 之间的整数；传入 `0` 可清除角标。未获通知授权或系统关闭角标时返回 `false`。API 26 及以上会读取系统角标开关；API 23 到 API 25 无法查询此开关，返回 `true` 表示设置成功，是否显示由桌面决定。其他系统错误会使 Promise 拒绝。

#### `setNotificationHandler(handler)`

设置应用前台收到通知时的展示策略。`handler.handleNotification` 需要在 3 秒内返回 `NotificationBehavior`；超时或未设置 handler 时通知不展示。成功后调用 `handleSuccess`，处理失败或超时后调用 `handleError`。

`shouldShowBanner` 控制横幅，`shouldShowList` 控制通知中心条目，`shouldPlaySound` 控制声音，`shouldSetBadge` 控制是否应用通知内容中的 `badge`。只显示横幅而不在通知中心保留条目会被拒绝；只在通知中心保留条目而不显示横幅可以使用。已废弃的 `shouldShowAlert` 同时设置横幅和通知中心条目。

- `NotificationBehavior.priority`：HarmonyOS 不支持此字段，传入后会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `scheduleNotificationAsync(request)`

返回 `Promise<string>`，其值是通知标识符；未传 `identifier` 时会生成标识符。`trigger: null` 表示立即发送。前台收到的即时通知交由 `setNotificationHandler()` 决定是否展示；应用不在前台时由系统直接展示。

即时通知内容支持 `title`、`body`、`subtitle`、`data`、`badge`、`autoDismiss`、`categoryIdentifier` 和默认声音。`subtitle` 显示为通知附加文本；声音支持默认声音或静音（`sound: false` 或 `null`）。

日期、间隔、每日、每周、每月和每年触发器可用于定时提醒。定时提醒由系统投递，应用退出后仍可触发；不经过前台 handler，也不会逐次触发 `addNotificationReceivedListener`。提醒支持 `title`、`body`、`autoDismiss` 和默认声音。重复提醒每次触发时，点击响应中的 `date` 仍为初次计划的时间。

重复使用同一标识符调度待触发提醒会更新该提醒；若旧提醒已展示且仍有后续触发，会先发布新提醒再取消旧提醒。通知数量和频率受系统配额限制。

- `calendar` 触发器：HarmonyOS 不支持此触发方式，调用会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。
- `timeInterval` 触发器的 `repeats: true`：HarmonyOS 不支持间隔重复，调用会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。
- 触发器上的 `channelId`：HarmonyOS 不支持通知渠道，调用会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。
- 自定义声音，以及内容中的 `sticky: true`、`launchImageName`、`attachments`、`vibrate`、`color`、`priority`、`interruptionLevel`：HarmonyOS 不支持这些字段，传入后会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。
- 定时提醒中的 `badge`、`subtitle`、`categoryIdentifier`、静音声音和 `sticky: true`：HarmonyOS 的定时提醒不支持这些字段，传入后会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `getNextTriggerDateAsync(trigger)`

返回 `Promise<number | null>`。有下一次触发时间时返回 Unix 毫秒时间戳；一次性日期已过时返回 `null`。该方法只计算时间，不会注册提醒。

#### `getAllScheduledNotificationsAsync()`

返回 `Promise<NotificationRequest[]>`，列出仍有后续触发的定时提醒。

#### `cancelScheduledNotificationAsync(identifier)`

取消指定标识符且仍有后续触发的定时提醒。重复取消不报错；已展示的一次性通知可用 `dismissNotificationAsync()` 清除。

#### `cancelAllScheduledNotificationsAsync()`

取消全部仍有后续触发的定时提醒，不清除已经展示的通知。

#### `getPresentedNotificationsAsync()`

返回 `Promise<Notification[]>`，列出当前显示在通知中心的通知。本包发布的通知会返回完整的 `request` 和 `data`。Push Kit 远程通知只返回标题、正文和标识符；`data` 为空对象，`date` 为系统送达时间。

#### `dismissNotificationAsync(identifier)`

清除指定的已展示通知。清除重复定时提醒当前显示的通知卡片后，不会取消该提醒后续的触发。

#### `dismissAllNotificationsAsync()`

清除当前应用已展示的全部通知，不影响仍有后续触发的定时提醒。

#### `setNotificationCategoryAsync(identifier, actions, options?)`

保存通知类别并返回 `Promise<NotificationCategory>`。每个类别最多包含两个操作按钮；每个按钮必须提供唯一的 `identifier` 和 `buttonTitle`。点击按钮会拉起应用，并在响应中返回对应的 `actionIdentifier`。类别用于即时本地通知。

- 操作按钮的 `textInput`、`options.opensAppToForeground: false`、`options.isAuthenticationRequired: true` 和 `options.isDestructive: true`：HarmonyOS 不支持文本输入、后台执行、解锁验证或破坏性标记，传入后会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。
- `NotificationCategoryOptions` 中定义的选项：HarmonyOS 不支持，传入非空选项后会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `getNotificationCategoriesAsync()`

返回 `Promise<NotificationCategory[]>`，列出已保存的通知类别。

#### `deleteNotificationCategoryAsync(identifier)`

返回 `Promise<boolean>`。删除成功为 `true`，类别不存在为 `false`；删除类别不会改变已展示通知。

#### `getLastNotificationResponse()`

返回最近一次 `NotificationResponse`，没有响应时返回 `null`。响应只在应用当前运行期间保留。

#### `getLastNotificationResponseAsync()`

返回最近一次 `NotificationResponse`，没有响应时返回 `null`。此异步方法已废弃。

#### `clearLastNotificationResponse()`

清除最近一次响应，并将 `useLastNotificationResponse()` 的值更新为 `null`。

#### `clearLastNotificationResponseAsync()`

清除最近一次响应，并将 `useLastNotificationResponse()` 的值更新为 `null`。此异步方法已废弃。

#### `getDevicePushTokenAsync()`

返回 `Promise<DevicePushToken>`；`type` 为 `'harmony'`，`data` 为 Huawei Push Kit 设备令牌。调用不会请求通知授权。获取令牌需要在 AppGallery Connect 开通 HarmonyOS Push Kit，并配置应用标识、签名和所需推送权益；配置不完整时 Promise 会以系统错误码拒绝，可再次调用重试。[华为 Push Kit 开发准备指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/push-preparations)

#### `unregisterForNotificationsAsync()`

返回 `Promise<void>`，注销应用的 Push Kit 令牌。注销后应用回到前台不会自动刷新令牌；再次调用 `getDevicePushTokenAsync()` 会恢复令牌刷新。系统删除令牌失败时 Promise 会拒绝，可以重试。

#### `getExpoPushTokenAsync(options?)`

- HarmonyOS 不提供 Expo Push Service，此方法会以 `ERR_NOTIFICATIONS_EXPO_PUSH_SERVICE_UNSUPPORTED` 拒绝。远程推送需使用 `getDevicePushTokenAsync()` 返回的 Huawei Push Kit 令牌。

#### `setAutoServerRegistrationEnabledAsync(enabled)`

- HarmonyOS 不提供 Expo Push Service 自动注册，此方法会以 `ERR_NOTIFICATIONS_EXPO_PUSH_SERVICE_UNSUPPORTED` 拒绝。

#### `registerTaskAsync(taskName)`

- HarmonyOS 不支持应用在后台收到推送时运行 JavaScript 任务，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `unregisterTaskAsync(taskName)`

- HarmonyOS 不支持后台通知任务，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `getNotificationChannelAsync(channelId)`

- HarmonyOS 不提供通知渠道，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `getNotificationChannelsAsync()`

- HarmonyOS 不提供通知渠道，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `setNotificationChannelAsync(channelId, channel)`

- HarmonyOS 使用通知分类控制通知样式，不提供通知渠道；此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `deleteNotificationChannelAsync(channelId)`

- HarmonyOS 不提供通知渠道，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `getNotificationChannelGroupAsync(groupId)`

- HarmonyOS 不提供通知渠道组，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `getNotificationChannelGroupsAsync()`

- HarmonyOS 不提供通知渠道组，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `setNotificationChannelGroupAsync(groupId, group)`

- HarmonyOS 不提供通知渠道组，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `deleteNotificationChannelGroupAsync(groupId)`

- HarmonyOS 不提供通知渠道组，此方法会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `subscribeToTopicAsync(topic)`

- HarmonyOS 不支持推送主题订阅，此方法会因接口不可用而拒绝。

#### `unsubscribeFromTopicAsync(topic)`

- HarmonyOS 不支持推送主题订阅，此方法会因接口不可用而拒绝。

### Event subscriptions

#### `addNotificationReceivedListener(listener)`

应用前台运行期间收到即时通知或远程通知时触发，返回可调用 `remove()` 的订阅对象。由 Push Kit 直接展示的远程通知不会进入此监听器；只有送达 JS 的远程通知才会触发。

#### `addNotificationResponseReceivedListener(listener)`

用户点击通知主体或操作按钮时触发，冷启动和热启动均可收到，返回可调用 `remove()` 的订阅对象。即时本地通知的响应包含完整 `request` 和 `actionIdentifier`。远程通知的响应中标题和正文为 `null`，`date` 为点击时间，`identifier` 为生成的 UUID；`data` 包含 Push Kit 展开的 `clickAction.data` 和应用传入的启动参数，不包含系统参数，无法区分这些数据的来源。订阅时若最近一次响应尚未投递，会补发该响应。

#### `addPushTokenListener(listener)`

Push Kit 令牌发生变化时触发，返回可调用 `remove()` 的订阅对象。调用 `getDevicePushTokenAsync()` 后令牌有变化会通知监听器；已订阅时，应用回到前台也会重新获取令牌并比较是否变化。

#### `addNotificationsDroppedListener(listener)`

- HarmonyOS 不提供推送丢弃事件；订阅成功返回对象，但监听器不会触发。

### Types

#### `NotificationPermissionsStatus`

权限状态中的 `status` 为 `granted`、`denied` 或 `undetermined`；`granted` 表示通知总开关已开启。`expires` 为 `'never'`。`harmony` 包含 HarmonyOS 返回的通知设置，例如声音、振动和角标开关。

#### `NotificationHandler`

`handleNotification(notification)` 返回 `Promise<NotificationBehavior>`；可选的 `handleSuccess(notificationId)` 和 `handleError(notificationId, error)` 分别接收处理结果和错误。前台 handler 超时时，`handleError` 收到 `ERR_NOTIFICATION_TIMEOUT` 错误。

#### `NotificationBehavior`

HarmonyOS 字段为 `shouldShowBanner`、`shouldShowList`、`shouldPlaySound`、`shouldSetBadge` 和已废弃的 `shouldShowAlert`。`shouldShowBanner: true` 且 `shouldShowList: false` 不受支持。

#### `NotificationRequestInput`

调度输入由 `content`、`trigger` 和可选的 `identifier` 组成。`trigger` 必须显式传入 `null` 表示立即通知，或传入受支持的日期、间隔、每日、每周、每月或每年触发器。

#### `NotificationContentInput`

HarmonyOS 支持 `title`、`body`、`subtitle`、`data`、`badge`、`sound`、`autoDismiss` 和 `categoryIdentifier`。`data` 须为对象；`badge` 须为 0 到 2147483647 之间的整数；`sound` 支持 `true`、`'default'` 表示默认声音，`false` 或 `null` 表示静音。定时提醒仅支持 `title`、`body`、`autoDismiss` 和默认声音。

- 自定义声音、`launchImageName`、`vibrate`、`priority`、`color`、`sticky: true`、`attachments` 和 `interruptionLevel`：HarmonyOS 不支持这些字段，调度时会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。
- `subtitle`、`badge`、`categoryIdentifier` 和静音声音：定时提醒不支持这些字段，调度时会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `NotificationContent`

读取通知时返回的内容类型。通知标题、正文和附加文本可能为 `null`；本包通知保留原始 `data`，Push Kit 远程通知的 `data` 为空对象。

#### `NotificationTriggerInput`

支持 `null`、`date`、`timeInterval`、`daily`、`weekly`、`monthly` 和 `yearly`。`date` 使用未来的 Unix 毫秒时间戳；`timeInterval.seconds` 是从调用时起算的正整数秒；`daily` 使用 `hour` 和 `minute`；`weekly` 另需 `weekday`（1 为周日）；`monthly` 另需 `day`；`yearly` 另需 `month`（0 为一月）和 `day`。日期规则按设备本地日历和时区计算，月份中不存在的日期会跳过该月；`yearly` 的月日组合无效时会拒绝。

以日期规则创建的代理提醒按秒触发，触发时间向上取整至整秒，不会提前投递。`date` 触发器取整后的时间会同时用于实际触发、`getAllScheduledNotificationsAsync()` 的返回值和点击响应中的 `date`。

- `calendar`、`timeInterval.repeats: true` 和 `channelId`：HarmonyOS 不支持这些触发器选项，调用会以 `ERR_NOTIFICATIONS_UNSUPPORTED` 拒绝。

#### `Notification`

包含送达时间 `date` 和 `request`。

#### `NotificationRequest`

包含通知标识符 `identifier`、`content` 和 `trigger`。

#### `NotificationResponse`

包含 `notification` 和用户操作对应的 `actionIdentifier`。点击通知主体时，`actionIdentifier` 为 `Notifications.DEFAULT_ACTION_IDENTIFIER`。

#### `NotificationCategory`

包含 `identifier`、`actions` 和可选 `options`。

#### `NotificationAction`

每个操作需包含唯一的 `identifier` 和 `buttonTitle`；HarmonyOS 每个类别最多支持两个操作按钮，点击后会打开应用。

- `NotificationAction.textInput`、`options.opensAppToForeground: false`、`options.isAuthenticationRequired: true` 和 `options.isDestructive: true`：HarmonyOS 不支持这些选项。

#### `NotificationCategoryOptions`

- `NotificationCategoryOptions` 中的选项：HarmonyOS 不支持。

#### `DevicePushToken`

HarmonyOS 设备令牌的 `type` 为 `'harmony'`，`data` 为 Huawei Push Kit 令牌，可用于向该设备发送远程推送。

### Enums

#### `SchedulableTriggerInputTypes`

HarmonyOS 支持 `DATE`、`TIME_INTERVAL`、`DAILY`、`WEEKLY`、`MONTHLY` 和 `YEARLY`。

- `CALENDAR`：HarmonyOS 不支持日历匹配触发器。

### Error codes

#### `ERR_NOTIFICATIONS_INVALID_ARGUMENT`

标识符、角标值、触发器日期或类别操作参数无效时返回。

#### `ERR_NOTIFICATIONS_UNSUPPORTED`

传入 HarmonyOS 不支持的通知字段或选项，或调用不支持的后台任务、通知渠道接口时返回。

#### `ERR_NOTIFICATIONS_REMINDER_PERMISSION`

未声明代理提醒权限时，调度定时提醒会返回此错误。

#### `ERR_NOTIFICATIONS_EXPO_PUSH_SERVICE_UNSUPPORTED`

调用 Expo Push Service 令牌或自动注册接口时返回。

#### `ERR_NOTIFICATIONS_PUSH_TOKEN` / `ERR_NOTIFICATIONS_PERMISSION` / `ERR_NOTIFICATIONS_BADGE`

分别表示获取 Push Kit 令牌、请求通知权限或读写角标时发生系统错误。若系统提供错误码，调用会返回该系统错误码。

#### `ERR_NOTIFICATIONS_SCHEDULE` / `ERR_NOTIFICATIONS_DISMISS`

分别表示调度定时提醒或清除已展示通知时发生系统错误。若系统提供错误码，调用会返回该系统错误码。

#### `ERR_NOTIFICATION_TIMEOUT` / `ERR_NOTIFICATION_HANDLED`

`ERR_NOTIFICATION_TIMEOUT` 表示前台通知 handler 超过 3 秒未返回；`ERR_NOTIFICATION_HANDLED` 表示对应通知已超时或已完成处理后仍尝试提交展示策略。

#### `1700002`

HarmonyOS 拒绝创建代理提醒时可能返回此系统错误码，表示代理提醒权益未开通或系统配额已用完。[代理提醒错误码](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/errorcode-reminderagentmanager/)

### Permissions

#### `getPermissionsAsync()`

返回 `Promise<NotificationPermissionsStatus>`，查询系统通知总开关，不会显示授权对话框。HarmonyOS 不提供细分的通知授权选项。若应用尚未请求授权且系统未授权，`status` 为 `undetermined`；用户拒绝后为 `denied`，此时 `canAskAgain` 为 `false`。

#### `requestPermissionsAsync(permissions?)`

返回 `Promise<NotificationPermissionsStatus>`。未授权时请求开启系统通知；系统已授权时直接返回当前状态。HarmonyOS 只有通知总开关，`permissions` 中细分的授权选项不会改变请求内容。用户拒绝后，系统不再弹出请求对话框，应用需引导用户到系统设置开启通知。

#### `ohos.permission.PUBLISH_AGENT_REMINDER`

调度定时提醒前，需在应用权限声明中加入此权限，并按[华为代理提醒开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder/)申请开通代理提醒权益并使用获批的签名。该权限在安装时授予，无需申请 ACL；即时通知和推送令牌不需要此权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
