# @expo-harmony/expo-store-review

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-store-review) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/storereview/)

为 HarmonyOS 上的 React Native 应用提供 Expo StoreReview 的原生实现，与官方 `expo-store-review` 配套使用。

## 安装

本包适配 Expo SDK 57。

最低兼容版本为 API 13（HarmonyOS 5.0.1）。AppGallery 应用内评分弹窗需要 API 20（HarmonyOS 6.0.0）及设备支持。 [华为 AppGallery 评论服务](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/appgallery-comment/)

```bash
npm install @expo-harmony/expo-store-review expo-store-review@~57.0.3
```

## API 对照表

### Methods

#### `StoreReview.hasAction()`

返回 `Promise<boolean>`。应用内评论或评论页链接可用时返回 `true`。应用市场仍会校验该包名的上架情况与用户的评论资格。

#### `StoreReview.isAvailableAsync()`

返回 `Promise<boolean>`。API 20 及以上、设备支持 AppGallery 评论服务且应用有可用界面时返回 `true`。查询不会显示弹窗。

#### `StoreReview.requestReview()`

无参数，返回 `Promise<void>`。应用内评分可用时请求显示 AppGallery 评论弹窗，否则通过系统打开评论页链接。Promise 不返回用户评分或评论结果。AppGallery 拒绝弹窗请求时会返回系统错误。

#### `StoreReview.storeUrl()`

有可用界面时按已安装应用的包名返回 AppGallery 评论页链接。无法取得包名或在无界面运行时调用时返回 `null`。

### Error codes

#### `ERR_STORE_REVIEW_BACKGROUND`

有界面应用在后台调用 `StoreReview.requestReview()` 时以此错误拒绝。

#### `ERR_STORE_REVIEW_UNAVAILABLE`

应用没有可用界面，或应用内评论不可用且无法取得评论页链接时以此错误拒绝。

#### `ERR_STORE_REVIEW_REQUEST_FAILED`

请求 AppGallery 评论弹窗或打开评论页链接失败时优先返回系统错误码，没有系统错误码时以此错误拒绝。

#### AppGallery 评论服务错误码

AppGallery 服务可能在请求失败时返回以下错误码：

| 错误码 | 原因 |
| --- | --- |
| `1021500001` | 系统内部错误。 |
| `1021500002` | 服务请求失败。 |
| `1021500003` | 无法连接 AppGallery。 |
| `1021500004` | 参数写入失败。 |
| `1021500005` | 应用上下文无效。 |
| `1021500006` | 用户尚未登录华为帐号。 |
| `1021500007` | 用户已评价当前版本。 |
| `1021500008` | 评论数量已达到上限。 |
| `1021500009` | 用户已评价，且距上次评价不足一年。 |

### Permissions

不需要额外声明权限。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
