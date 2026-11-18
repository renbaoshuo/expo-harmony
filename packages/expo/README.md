# @expo-harmony/expo

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo)

为 HarmonyOS 上的 React Native 应用提供 Expo 主包的原生实现，与官方同版本的 `expo` 配套使用。

## 安装

```bash
npm install @expo-harmony/expo expo@55.0.31
```

最低支持 HarmonyOS 5.0.2（API 14），宿主应用的 `compatibleSdkVersion` 不能低于这个版本。HAR 已声明 `ohos.permission.INTERNET` 普通权限。

应用继续使用官方 `expo` 和 `expo/fetch` 的 JavaScript API：

```ts
import { reloadAppAsync } from 'expo';
import { fetch } from 'expo/fetch';

const response = await fetch('https://example.com');
await reloadAppAsync();
```

`expo/fetch` 支持流式读取 `http` 和 `https` 响应体（包括 SSE）。API 14–19 使用原生兼容传输，API 20 及以上使用 Remote Communication Kit。`credentials: 'include'` 时保存响应的 Cookie，后续请求自动携带。重定向遵循 fetch 标准，最多跟随 20 次，跨源时移除 `Authorization`、`Cookie` 等请求头。`file://` 地址只支持 `GET` 和 `HEAD` 方法，不能携带请求体，文件不存在时返回 404，且只能读取应用沙箱内或已授权路径下的文件。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
