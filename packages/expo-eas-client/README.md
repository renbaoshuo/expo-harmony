# @expo-harmony/expo-eas-client

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/expo-eas-client)

为 HarmonyOS 上的 React Native 应用提供 Expo EAS Client 的原生实现，与官方同版本的 `expo-eas-client` 配套使用。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 13（HarmonyOS 5.0.1）。

```bash
npm install @expo-harmony/expo-eas-client expo-eas-client
```

## API 对照表

### Constants

#### `clientID`

`string`，无参数。EAS 服务的客户端 UUID，在同一应用安装中保持稳定；应用更新或重启后不变，卸载应用或清除应用数据后会重新生成。HarmonyOS 上同一应用中的各个 Ability 读取到相同的 ID。读取或保存失败时会抛出错误。

#### `deterministicUniformValue`

`number`，无参数。由 `clientID` 派生，范围为 `[0, 1)`；同一客户端 ID 始终得到相同值。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
