# @expo-harmony/expo-store-review

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-store-review) | [官方文档](https://docs.expo.dev/versions/v57.0.0/sdk/storereview/)

为 HarmonyOS 上的 React Native 应用提供 Expo StoreReview 的原生实现，与官方同版本的 `expo-store-review` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```bash
npm install @expo-harmony/expo-store-review expo-store-review
```

## API 对照表

### Methods

#### `StoreReview.hasAction()`

返回 `Promise<boolean>`。HarmonyOS 上结果与 `StoreReview.isAvailableAsync()` 相同；`true` 表示设备支持 AppGallery 应用内评论，不保证调用请求时一定会显示弹窗。

#### `StoreReview.isAvailableAsync()`

返回 `Promise<boolean>`。设备支持 AppGallery 评论服务且应用有可用界面时返回 `true`，否则返回 `false`。查询不会显示弹窗。

#### `StoreReview.requestReview()`

无参数，返回 `Promise<void>`，请求显示 AppGallery 应用内评论弹窗。Promise 不返回评分或用户是否提交评价的结果。应用不在前台时以 `ERR_STORE_REVIEW_BACKGROUND` 拒绝；应用无可用界面或 AppGallery 评论服务不可用时以 `ERR_STORE_REVIEW_UNAVAILABLE` 拒绝。AppGallery 也可能因帐号或评论资格问题拒绝请求。

#### `StoreReview.storeUrl()`

返回 `string | null`。

- HarmonyOS 不提供可由此 API 返回的 AppGallery 评论链接，因此返回 `null`。

### Error codes

#### `ERR_STORE_REVIEW_BACKGROUND`

AppGallery 评论服务可用，但应用不在前台时调用 `StoreReview.requestReview()`，Promise 会以此错误拒绝。

#### `ERR_STORE_REVIEW_UNAVAILABLE`

应用没有可用界面或 AppGallery 评论服务不可用时，调用 `StoreReview.requestReview()` 会以此错误拒绝。

#### `ERR_STORE_REVIEW_REQUEST_FAILED`

AppGallery 评论服务请求失败且系统未提供错误码时，Promise 会以此错误拒绝。系统提供错误码时会使用该错误码。

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
