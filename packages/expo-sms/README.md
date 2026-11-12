# @expo-harmony/expo-sms

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-sms) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/sms/)

为 HarmonyOS 上的 React Native 应用提供 Expo SMS 的原生实现，与官方同版本的 `expo-sms` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-sms expo-sms
```

## API 对照表

### Methods

#### `SMS.isAvailableAsync()`

返回 `Promise<boolean>`。设备具备短信能力时返回 `true`，否则返回 `false`。此结果不检查 SIM 卡或运营商网络；返回 `true` 不代表短信一定能发出。

#### `SMS.sendSMSAsync(addresses, message, options?)`

返回 `Promise<SMSResponse>`，打开系统短信编辑页并预填收件人和正文，由用户决定是否发送。`addresses` 为单个号码字符串或字符串数组；空数组表示不预填收件人，号码中的前导零和国际区号会保留。`message` 为短信正文字符串，`options` 为可选的 `SMSOptions`。应用需处于前台，且同时只能有一个未完成的请求。编辑页打开后，应用恢复前台时 Promise 以 `{ result: 'unknown' }` 完成；若应用没有转入后台，Promise 会继续等待。HarmonyOS 不提供短信发送或取消状态。发送操作由用户在系统编辑页中完成，无需短信权限。

### Types

#### `SMSResponse`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `result` | `'unknown' \| 'sent' \| 'cancelled'` | HarmonyOS 上始终为 `'unknown'`，不能据此判断短信是否已发送。 |

#### `SMSAttachment`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `uri` | `string` | 附件 URI。 |
| `mimeType` | `string` | 附件的 MIME 类型。 |
| `filename` | `string` | 附件文件名。 |

#### `SMSOptions`

| 属性 | 类型 | 说明 |
| --- | --- | --- |
| `attachments` | `SMSAttachment \| SMSAttachment[]` | 可省略，或传入一个附件或附件数组。 |

- 附件预填尚未实现：传入单个附件或非空数组会以 `ERR_SMS_ATTACHMENTS_UNSUPPORTED` 拒绝，因为系统短信编辑页不接受附件预填。用户可以在编辑页自行添加附件。

### Error codes

#### `ERR_SMS_UNAVAILABLE`

设备不具备短信能力时，`SMS.sendSMSAsync()` 会以此错误拒绝。

#### `ERR_SMS_BACKGROUND`

应用不在前台时调用 `SMS.sendSMSAsync()`，会以此错误拒绝。

#### `ERR_SMS_PENDING`

已有短信编辑请求尚未完成时再次调用 `SMS.sendSMSAsync()`，会以此错误拒绝。

#### `ERR_SMS_ATTACHMENTS_UNSUPPORTED`

`SMSOptions.attachments` 不为空时，`SMS.sendSMSAsync()` 会以此错误拒绝。

#### `ERR_SMS_SENDING`

系统短信编辑页无法打开时，`SMS.sendSMSAsync()` 会以此错误拒绝。

#### `ERR_SMS_DESTROYED`

应用重载或销毁时仍有未完成的请求，Promise 会以此错误拒绝。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
