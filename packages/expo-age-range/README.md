# @expo-harmony/expo-age-range

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-age-range) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/age-range/)

为 HarmonyOS 上的 React Native 应用提供 Expo AgeRange 的原生实现，与官方 `expo-age-range` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-age-range expo-age-range@~57.0.5
```

如果宿主应用接入系统未成年人模式并按年龄段提供适龄内容，需要由应用在入口模块的 `module.json5` 中将 `{ "name": "minors_mode", "value": "1" }` 添加到 `module.metadata`。该声明会影响系统未成年人模式下能否打开应用。（[华为未成年人模式接入规范](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/account-overview-minorsprotection/)）

## API 对照表

### Methods

#### `AgeRange.requestAgeRangeAsync(options)`

参数 `options` 的类型为 `AgeRangeRequest`，返回 `Promise<AgeRangeResponse>`。读取系统未成年人模式提供的年龄段，不会弹出系统界面或改变模式开关。`threshold1`、`threshold2` 和 `threshold3` 会被接受但不影响结果，年龄段由系统提供。

未成年人模式开启且系统提供年龄段时，返回包含式的整数年龄边界。以下是当前系统的分组。

| 系统年龄段 | `lowerBound` | `upperBound` |
| --- | --- | --- |
| 不满 3 周岁 | `0` | `2` |
| 3 周岁及以上、不满 8 周岁 | `3` | `7` |
| 8 周岁及以上、不满 12 周岁 | `8` | `11` |
| 12 周岁及以上、不满 16 周岁 | `12` | `15` |
| 16 周岁及以上、不满 18 周岁 | `16` | `17` |

模式关闭或系统未提供年龄段时，`lowerBound` 和 `upperBound` 均为 `null`，表示年龄未知。年龄段来自设备的未成年人模式，可能对应临时使用者。其来源和验证方式由系统管理。 [华为未成年人模式 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/account-api-minorsprotection)

#### `AgeRange.isEligibleForAgeFeaturesAsync()`

- 返回 `Promise<boolean | null>`。HarmonyOS 始终返回 `null`，因为系统不提供当前用户是否适用年龄相关监管规则的信息。

#### `AgeRange.showSignificantUpdateAcknowledgmentAsync(updateDescription)`

- 参数 `updateDescription` 的类型为 `string`，返回 `Promise<void>`。HarmonyOS 不提供重大更新确认功能；调用立即完成。

#### `AgeRange.getRequiredRegulatoryFeaturesAsync()`

- 返回 `Promise<AgeRangeRegulatoryFeature[] | null>`。HarmonyOS 始终返回 `null`，因为系统不提供适用的监管功能列表。

#### `AgeRange.requestAgeSignalsAccessAsync()`

- 返回 `Promise<AgeSignalsStatus | null>`。HarmonyOS 始终返回 `null`，因为系统不提供单独的年龄信号共享状态。

#### `AgeRange.setFakeAgeSignals(fake)`

- 参数 `fake` 的类型为 `FakeAgeSignals | null`，返回 `void`。HarmonyOS 不支持替换年龄信号，因此此方法不执行操作。

### Types

#### `AgeRangeRequest`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `threshold1` | `number` | 必填；接受但忽略，年龄范围由系统提供 |
| `threshold2` | `number` | 可选；接受但忽略 |
| `threshold3` | `number` | 可选；接受但忽略 |

#### `AgeRangeResponse`

| 属性 | 类型 | HarmonyOS 行为 |
| --- | --- | --- |
| `lowerBound` | `number \| null` | 年龄范围的包含式下限；系统未提供时为 `null` |
| `upperBound` | `number \| null` | 年龄范围的包含式上限；系统未提供时为 `null` |

- `ageRangeDeclaration`、`activeParentalControls`、`installId`、`ageRangeSource`、`significantChangeStatus`、`significantChangeApprovalDate`、`mostRecentApprovalDate`：HarmonyOS 响应不包含这些字段，因为系统未成年人模式不提供对应信息。

#### `FakeAgeSignals`

供 `AgeRange.setFakeAgeSignals()` 使用的输入类型。HarmonyOS 上该方法不执行操作，因此不会读取此类型的值。

### Enums

#### `AgeRangeRegulatoryFeature`

取值为 `'declaredAgeRangeRequired'`、`'significantAppChangeRequiresAdultNotification'` 或 `'significantAppChangeRequiresParentalConsent'`。

- HarmonyOS 不会返回这些值；`getRequiredRegulatoryFeaturesAsync()` 始终返回 `null`。

#### `AgeSignalsStatus`

取值为 `'SHARED'`、`'NOT_SHARED'` 或 `'VERIFICATION_REQUIRED'`。

- HarmonyOS 不会返回这些值；`requestAgeSignalsAccessAsync()` 始终返回 `null`。

### Error codes

#### `ERR_INVALID_ARGUMENT_TYPE`

向 `requestAgeRangeAsync()` 传入 `null` 或 `undefined` 时，Promise 以此错误码拒绝。

#### `ERR_AGE_RANGE_NOT_AVAILABLE`

系统未提供未成年人模式能力，或 Account Kit 判定不支持时，Promise 以此错误码拒绝。中国大陆以外注册的华为账号和设备隐私空间均属于系统不支持的场景。 [华为未成年人模式 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/account-api-minorsprotection/)

#### `ERR_AGE_RANGE_UNKNOWN_RESPONSE`

系统返回无效的未成年人模式状态或年龄边界时，Promise 以此错误码拒绝。

#### 系统错误码

年龄范围查询失败且系统提供错误码时，Promise 以该系统错误码和错误信息拒绝。

#### `ERR_AGE_RANGE_REQUEST_FAILED`

年龄范围查询失败且系统未提供错误码时，Promise 以此错误码拒绝。

#### `ERR_AGE_RANGE_USER_DECLINED`、`ERR_AGE_RANGE_INVALID_REQUEST`

- HarmonyOS 不会产生这些错误码：调用不弹出确认界面，也不校验阈值参数。

### Permissions

#### `requestAgeRangeAsync()`

读取年龄范围无需申请权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
