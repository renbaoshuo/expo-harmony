# @expo-harmony/expo-localization

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-localization) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/localization/)

为 HarmonyOS 上的 React Native 应用提供 Expo Localization 的原生实现，与官方 `expo-localization` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-localization expo-localization@~57.0.2
```

## API 对照表

### Hooks

#### `useLocales()`

返回至少包含一项的 `Locale[]`，按 HarmonyOS 系统偏好语言的顺序排列。系统语言或地区设置变化后，以及应用回到前台时，Hook 会重新读取并更新结果。

#### `useCalendars()`

返回一项 `Calendar[]`。HarmonyOS 系统语言、系统时间或时区变化后，以及应用回到前台时，Hook 会重新读取并更新结果。

### Methods

#### `getLocales()`

参数：无。

返回：至少包含一项的 `Locale[]`，同步读取 HarmonyOS 系统偏好语言列表。语言标签未指定地区时，会使用系统地区补全；系统偏好语言列表为空或无法解析时，返回系统语言对应的条目。

HarmonyOS SDK API 18 及以上读取系统温度单位偏好；系统设为 Kelvin 时该字段为 `null`。API 13–17 根据地区推断温度单位，地区不可用时为 `null`；地区为 `AG`、`BZ`、`VG`、`FM`、`MH`、`MS`、`KN`、`BS`、`CY`、`TC`、`US`、`LR`、`PW` 或 `KY` 时返回 `'fahrenheit'`，其他已知地区返回 `'celsius'`。系统地区不可用时，`regionCode`、`currencyCode`、`currencySymbol` 和 `measurementSystem` 为 `null`。有地区值时，`measurementSystem` 对 `GB` 和 `MM` 返回 `'uk'`，对 `US` 和 `LR` 返回 `'us'`，其他地区返回 `'metric'`。

#### `getCalendars()`

参数：无。

返回：一项 `Calendar[]`，同步读取系统语言对应的历法标识、系统时区和 24 小时制设置。API 18 及以上读取系统的每周起始日偏好；API 13–17 根据系统语言推断。

### Types

#### `Locale`

| 属性 | 类型 | HarmonyOS 上的值 |
| --- | --- | --- |
| `languageTag` | `string` | BCP 47 语言标签；标签未指定地区时使用系统地区补全。 |
| `languageCode` | `string \| null` | 语言代码；语言未确定时为 `null`。 |
| `languageScriptCode` | `string \| null` | 文字代码；无法解析时为 `null`。 |
| `languageRegionCode` | `string \| null` | 该偏好语言的地区代码；未指定时使用系统地区。 |
| `regionCode` | `string \| null` | HarmonyOS 系统地区代码；系统未提供时为 `null`。 |
| `textDirection` | `'ltr' \| 'rtl'` | 该语言的文字方向。 |
| `decimalSeparator` | `string \| null` | 系统数字格式的小数分隔符。 |
| `digitGroupingSeparator` | `string \| null` | 系统数字格式的分组分隔符。 |
| `measurementSystem` | `'metric' \| 'us' \| 'uk' \| null` | 根据系统地区返回计量制；系统地区不可用时为 `null`。 |
| `currencyCode` | `string \| null` | 系统地区的货币代码；地区或货币数据不可用时为 `null`。 |
| `currencySymbol` | `string \| null` | 系统地区的货币符号；地区或货币数据不可用时为 `null`。 |
| `languageCurrencyCode` | `string \| null` | 该偏好语言地区的货币代码。 |
| `languageCurrencySymbol` | `string \| null` | 该偏好语言地区的货币符号。 |
| `temperatureUnit` | `'celsius' \| 'fahrenheit' \| null` | API 18 及以上取系统偏好，API 13–17 按地区推断；Kelvin 或地区不可用时为 `null`。 |

#### `Calendar`

| 属性 | 类型 | HarmonyOS 上的值 |
| --- | --- | --- |
| `calendar` | `CalendarIdentifier \| null` | 系统语言对应的 Unicode 历法标识；无法读取时为 `null`。 |
| `firstWeekday` | `Weekday \| null` | 每周起始日，周日为 `1`，周六为 `7`。 |
| `timeZone` | `string \| null` | HarmonyOS 系统时区标识。 |
| `uses24hourClock` | `boolean \| null` | 系统是否使用 24 小时制。 |

### Enums

#### `CalendarIdentifier`

Unicode 历法标识。HarmonyOS 返回系统语言对应的历法类型；公历标识为 `'gregory'`，无法读取时 `Calendar.calendar` 为 `null`。

| 枚举成员 | 值 |
| --- | --- |
| `BUDDHIST` | `'buddhist'` |
| `CHINESE` | `'chinese'` |
| `COPTIC` | `'coptic'` |
| `DANGI` | `'dangi'` |
| `ETHIOAA` | `'ethioaa'` |
| `ETHIOPIC` | `'ethiopic'` |
| `GREGORY`、`GREGORIAN` | `'gregory'` |
| `HEBREW` | `'hebrew'` |
| `INDIAN` | `'indian'` |
| `ISLAMIC` | `'islamic'` |
| `ISLAMIC_CIVIL` | `'islamic-civil'` |
| `ISLAMIC_RGSA` | `'islamic-rgsa'` |
| `ISLAMIC_TBLA` | `'islamic-tbla'` |
| `ISLAMIC_UMALQURA` | `'islamic-umalqura'` |
| `ISO8601` | `'iso8601'` |
| `JAPANESE` | `'japanese'` |
| `PERSIAN` | `'persian'` |
| `ROC` | `'roc'` |

#### `Weekday`

每周起始日及其编号：`SUNDAY = 1`、`MONDAY = 2`、`TUESDAY = 3`、`WEDNESDAY = 4`、`THURSDAY = 5`、`FRIDAY = 6`、`SATURDAY = 7`。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
