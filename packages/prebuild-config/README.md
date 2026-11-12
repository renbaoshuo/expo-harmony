# @expo-harmony/prebuild-config

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/prebuild-config) | [Expo 配置插件文档](https://docs.expo.dev/config-plugins/introduction/)

本包读取 Expo 项目配置，并在运行 `expo-harmony prebuild` 时生成 HarmonyOS 原生工程。

## 安装

本包适配 Expo SDK 57。

引入本包前，需要确保应用使用的 HarmonyOS SDK 至少为 API 20（HarmonyOS 6.0.0）。

```sh
npm install @expo-harmony/prebuild-config
```

## 配置项目

在 `app.json` 中注册配置插件，并在 `harmony` 字段设置应用的 `bundleName`：

```json
{
  "expo": {
    "name": "Example",
    "slug": "example",
    "platforms": ["harmony"],
    "experiments": {
      "outOfTreePlatforms": true
    },
    "plugins": ["@expo-harmony/prebuild-config"],
    "harmony": {
      "bundleName": "com.example.app"
    }
  }
}
```

`bundleName` 必填，至少由三段以点分隔的标识符组成，例如 `com.example.app`。`versionCode` 默认为 `1`，`deviceTypes` 默认为 `phone` 和 `tablet`。

## 生成 HarmonyOS 工程

配置完成后，在项目目录运行：

```sh
npx expo-harmony prebuild
```

工程会生成在项目根目录的 `harmony/` 下。修改了应用配置后，再次运行该命令以更新工程；需要先清理现有工程时，可使用 `npx expo-harmony prebuild --clean`。

## 设置应用图标和权限

可以在 `harmony` 字段中指定应用图标和需要声明的权限：

```json
{
  "icon": "./assets/app-icon.png",
  "permissions": [
    {
      "name": "ohos.permission.CAMERA",
      "usedScene": {
        "abilities": ["EntryAbility"],
        "when": "inuse"
      }
    }
  ]
}
```

将这些选项放在前面示例的 `harmony` 字段中。需要填写权限用途说明时，可以通过 `reason` 引用字符串资源，例如 `$string:camera_permission_reason`，并提供对应资源。申请受限权限前，请先按[华为文档](https://developer.huawei.com/consumer/cn/doc/app/agc-help-apply-acl-0000002394212138/)提交申请，并在获批后声明。

`harmony.icon` 支持 PNG、JPG、SVG 和 WebP；省略时使用 Expo 配置中的 `icon`。

## 选择原生模块构建类型

如果需要选择原生模块的构建类型，将 `plugins` 配置写成下面的形式：

```json
{
  "plugins": [
    [
      "@expo-harmony/prebuild-config",
      {
        "buildType": "release"
      }
    ]
  ]
}
```

`buildType` 可设为 `debug` 或 `release`。省略时读取 `EXPO_HARMONY_BUILD_TYPE`；该环境变量未设置时使用 `debug`。HarmonyOS 工程使用 Hermes，通常不需要设置 `harmony.jsEngine`。

## 配置签名

需要签名时，将 JSON5 文件路径加入前面 `app.json` 的 `expo.harmony` 对象，例如：

```json
{
  "expo": {
    "name": "Example",
    "slug": "example",
    "platforms": ["harmony"],
    "experiments": {
      "outOfTreePlatforms": true
    },
    "plugins": ["@expo-harmony/prebuild-config"],
    "harmony": {
      "bundleName": "com.example.app",
      "signingConfigFile": "./signing/harmony-signing.json5"
    }
  }
}
```

签名文件可以包含一个签名配置对象：

```json5
{
  name: 'default',
  type: 'HarmonyOS',
  material: {
    certpath: './app.cer',
    storePassword: '...',
    keyAlias: '...',
    keyPassword: '...',
    profile: './app.p7b',
    signAlg: 'SHA256withECDSA',
    storeFile: './app.p12',
  },
}
```

`material` 中的字段都需要填写，`signAlg` 使用 `SHA256withECDSA`。`certpath`、`profile` 和 `storeFile` 相对于签名文件所在目录解析。签名文件及证书应放在 `harmony/` 目录之外，以免运行 `prebuild --clean` 时被删除。

## 读取项目配置

`getPrebuildConfigAsync` 会读取项目的 Expo 配置，并返回处理后的 HarmonyOS 预构建配置。它不会生成 `harmony/` 工程：

```ts
import { getPrebuildConfigAsync } from '@expo-harmony/prebuild-config';

async function main() {
  const project = await getPrebuildConfigAsync(process.cwd());
  console.log(project.exp.harmony);
}

main();
```

需要读取 development 或 production 配置时，可以将 `'development'` 或 `'production'` 作为第二个参数传入。

## 与其他配置插件组合

如果其他配置插件也会修改 HarmonyOS 配置，可根据需要调整插件顺序。希望本包的设置最后生效时，将 `@expo-harmony/prebuild-config` 放在 `plugins` 列表末尾。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
