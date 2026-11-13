# @expo-harmony/expo-mail-composer

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-mail-composer) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/mail-composer/)

为 HarmonyOS 上的 React Native 应用提供 Expo Mail Composer 的原生实现，与官方 `expo-mail-composer` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo-mail-composer expo-mail-composer@~57.0.2
```

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 21（HarmonyOS 6.0.1）。

## API 对照表

### Methods

#### `MailComposer.getClients()`

返回 `MailClient[]`。

- HarmonyOS 不提供可供应用读取的邮件客户端清单，因此始终返回空数组。

#### `MailComposer.isAvailableAsync()`

返回 `Promise<boolean>`。查询设备是否有应用可处理 `mailto` 链接；没有时返回 `false`。调用前需在应用配置的 `harmony.querySchemes` 中声明 `mailto`。查询失败时以 `ERR_MAIL_COMPOSER_AVAILABILITY` 拒绝。

#### `MailComposer.composeAsync(options)`

返回 `Promise<MailComposerResult>`，打开系统邮件选择界面并将选项中的内容交给用户选择的邮件客户端。系统报告用户取消选择时返回 `{ status: 'cancelled' }`；客户端启动成功或系统只返回通用结果时返回 `{ status: 'undetermined' }`。结果不代表邮件已发送或保存。设备没有可用邮件客户端时，系统可能提示用户，但 Promise 可能一直等待系统回调。

应用必须处于前台才能调用。上一个请求未结束时再次调用会以 `ERR_MAIL_COMPOSER_IN_PROGRESS` 拒绝；应用在请求完成前重载或销毁时会以 `ERR_MAIL_COMPOSER_DESTROYED` 拒绝。启动客户端失败时以 `ERR_MAIL_COMPOSER_COMPOSE` 拒绝。

### Types

#### `MailClient`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `label` | `string` | 邮件客户端的显示名称。 |
| `packageName` | `string?` | 客户端的应用包名。 |
| `url` | `string?` | 客户端的 URL scheme。 |

#### `MailComposerOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `recipients` | `string[]?` | 收件人地址，支持多个。 |
| `ccRecipients` | `string[]?` | 抄送地址，支持多个。 |
| `bccRecipients` | `string[]?` | 密送地址，支持多个。 |
| `subject` | `string?` | 邮件主题。 |
| `body` | `string?` | 纯文本正文，支持 Unicode 和换行。 |
| `isHtml` | `boolean?` | 是否将正文作为 HTML；默认 `false`。 |
| `attachments` | `string[]?` | 附件的文件 URI 或绝对路径，支持多个。 |

所有选项均可省略；地址和附件可传空数组。附件必须是可读取的普通文件，并位于应用的文件、缓存、临时或分布式文件目录中。系统文件选择器提供的文件需先复制到应用目录。用户选择邮件客户端后，附件会获得临时读取权限；应用需在客户端完成读取前保留文件。

- HarmonyOS 仅支持纯文本正文；`isHtml: true` 会以 `ERR_MAIL_COMPOSER_HTML_UNSUPPORTED` 拒绝。
- 无法读取或不在应用上述目录中的附件会以 `ERR_MAIL_COMPOSER_ATTACHMENT` 拒绝。

#### `MailComposerResult`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `status` | `MailComposerStatus` | 系统报告的选择结果；不表示邮件是否已发送或保存。 |

### Enums

#### `MailComposerStatus`

| 成员 | 值 | 说明 |
| --- | --- | --- |
| `CANCELLED` | `'cancelled'` | 系统报告用户取消选择邮件客户端。 |
| `UNDETERMINED` | `'undetermined'` | 邮件处理结果未知。 |

- HarmonyOS 不会返回 `SENT` 或 `SAVED`，因为邮件客户端不会报告邮件是否已发送或保存。

### Error codes

#### `ERR_MAIL_COMPOSER_AVAILABILITY`

查询设备上的邮件应用失败。请确认应用配置的 `harmony.querySchemes` 已声明 `mailto`。

#### `ERR_MAIL_COMPOSER_ATTACHMENT`

附件无法读取，或不是应用文件、缓存、临时或分布式文件目录中的普通文件。

#### `ERR_MAIL_COMPOSER_BACKGROUND`

应用不在前台时调用 `composeAsync()`。

#### `ERR_MAIL_COMPOSER_COMPOSE`

系统无法启动邮件客户端或处理邮件请求。

#### `ERR_MAIL_COMPOSER_DESTROYED`

邮件请求尚未完成时应用重载或销毁。

#### `ERR_MAIL_COMPOSER_HTML_UNSUPPORTED`

`MailComposerOptions.isHtml` 设为 `true`；HarmonyOS 邮件撰写仅支持纯文本。

#### `ERR_MAIL_COMPOSER_IN_PROGRESS`

前一个 `composeAsync()` 请求尚未完成时再次调用。

#### `ERR_MAIL_COMPOSER_UNAVAILABLE`

设备不支持系统邮件撰写能力。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
