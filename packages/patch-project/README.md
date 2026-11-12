# @expo-harmony/patch-project

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/patch-project) | [Expo patch-project 文档](https://docs.expo.dev/config-plugins/patch-project/)

本包会保存 HarmonyOS 原生工程中的手动修改，并在后续生成工程时重新应用这些修改。

## 安装

本包适配 Expo SDK 57。

```sh
npm install @expo-harmony/patch-project
```

## 注册插件

在 `app.json` 的 `plugins` 中加入本包。HarmonyOS 工程还需要注册 `@expo-harmony/prebuild-config`，并设置应用的 `bundleName`：

```json
{
  "expo": {
    "name": "Example",
    "slug": "example",
    "platforms": ["harmony"],
    "experiments": {
      "outOfTreePlatforms": true
    },
    "plugins": [
      "@expo-harmony/prebuild-config",
      "@expo-harmony/patch-project"
    ],
    "harmony": {
      "bundleName": "com.example.app"
    }
  }
}
```

## 保存原生工程修改

先生成 HarmonyOS 工程：

```sh
npx expo-harmony prebuild
```

手动修改项目根目录下的 `harmony/` 后，运行补丁命令：

```sh
npx @expo-harmony/patch-project
```

命令会把修改保存在 `cng-patches/`。将该目录和应用配置一并提交到版本控制。

保存补丁后，如果不需要保留当前的 `harmony/`，可以运行 `npx @expo-harmony/patch-project --clean`。下次运行 `expo-harmony prebuild` 时会重新生成工程并应用补丁。

命令只保存未被 `harmony/.gitignore` 排除的文件。若需要包含被忽略的文件，可在 `harmony/.gitignore` 中添加对应的否定规则。

## 应用补丁

之后运行 `expo-harmony prebuild` 时，插件会查找适用于当前 HarmonyOS 工程的补丁并应用。没有匹配的补丁时，工程仍会生成，命令会提示检查补丁。需要从头生成工程时，也可以运行：

```sh
npx expo-harmony prebuild --clean
```

## 调整插件选项

默认情况下，插件会从项目根目录的 `cng-patches/` 查找补丁。需要更换查找目录时，可以设置 `patchRoot`；补丁生成命令仍写入 `cng-patches/`，因此需要把生成的补丁移到自定义目录。

`changedLinesLimit` 用于调整大补丁的提示阈值，默认值为 `300` 行。超过阈值时插件会发出提示，但仍会应用补丁：

```json
{
  "expo": {
    "platforms": ["harmony"],
    "experiments": {
      "outOfTreePlatforms": true
    },
    "harmony": {
      "bundleName": "com.example.app"
    },
    "plugins": [
      "@expo-harmony/prebuild-config",
      [
        "@expo-harmony/patch-project",
        {
          "changedLinesLimit": 300
        }
      ]
    ]
  }
}
```

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
