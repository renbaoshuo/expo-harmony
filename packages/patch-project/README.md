# @expo-harmony/patch-project

[**GitHub 仓库**](https://github.com/renbaoshuo/expo-harmony/tree/master/packages/patch-project)

这个包把 `harmony/` 里的手动修改保存为 Git 补丁，在 prebuild 时自动应用回去。它提供生成补丁的命令和负责应用补丁的 config plugin，流程对应 Expo 官方的 [patch-project](https://docs.expo.dev/config-plugins/patch-project/)。

## 安装

```sh
npm install @expo-harmony/patch-project
```

在 app config 的 `plugins` 里注册插件：

```json
{
  "expo": {
    "plugins": ["@expo-harmony/patch-project"]
  }
}
```

## 生成补丁

先跑一次 prebuild 得到 `harmony/`，手动改完后执行：

```sh
npx @expo-harmony/patch-project
# 指定项目目录
npx @expo-harmony/patch-project ./my-app
```

命令把当前原生工程和 prebuild 生成的默认工程做比较，将差异存储成一个 patch。patch 会存放在 `cng-patches/harmony+<templateChecksum>.patch`，把 `cng-patches/` 提交到仓库即可。

## 应用补丁

跑 `expo-harmony prebuild` 或 `expo-harmony prebuild --clean`，插件查找并应用与当前模板匹配的补丁。没有补丁就照常生成；只有其他模板的补丁时发出警告并跳过，提示重新审查和生成。有多份补丁时只应用校验和匹配的那一份。

补丁在常规 Mods、自定义文件 Mods 和 autolinking 之后应用。补丁新增的文件纳入 CNG 文件管理，改补丁或移除插件时会清掉不再声明的新增文件。既有文件上的修改不会自动撤销，要完整重建就用 `prebuild --clean`。

## 选项

命令参数：

| 参数                    | 作用                                                     |
| ----------------------- | -------------------------------------------------------- |
| `--clean`               | 补丁保存成功后删除原生目录，下次 prebuild 重新生成再应用 |
| `-p, --platform <name>` | `harmony` 或 `all`，默认 `harmony`，两者都只处理 Harmony |
| `-h, --help`            | 显示帮助                                                 |

插件选项：

| 选项                | 默认值        | 说明                                   |
| ------------------- | ------------- | -------------------------------------- |
| `patchRoot`         | `cng-patches` | 查找补丁的目录，相对项目根目录         |
| `changedLinesLimit` | `300`         | 补丁改动行数超过该值时警告，不阻止应用 |

```json
[
  "@expo-harmony/patch-project",
  {
    "patchRoot": "cng-patches",
    "changedLinesLimit": 300
  }
]
```

`patchRoot` 必须是非空路径，`changedLinesLimit` 必须是非负数。

注意生成 patch 的命令只往 `cng-patches/` 写补丁，插件配置使用别的目录查找 patch 时，需要自己把 patch 文件移过去。

## 支持的修改

支持文本和二进制文件、新增和删除，以及可执行权限等修改，还有指向 Harmony 工程内部的相对符号链接。

文件是否进入补丁遵循 `harmony/.gitignore` 及其子目录中的 Git 忽略规则。默认的 prebuild 模板已忽略常见的依赖目录和构建产物，需要保留其中的文件时，可以用 `!` 规则显式包含。

补丁路径和符号链接不能越出 Harmony 工程，也不能修改 `.git` 元数据。

## 升级

SDK、模板或其他插件升级后补丁可能对不上，要重新审查并生成。改动量大、长期维护的配置更适合写成静态 Mod。

## Author

**expo-harmony** © [Baoshuo](https://github.com/renbaoshuo), Released under the MIT License.<br>
Authored and maintained by Baoshuo with help from [contributors](https://github.com/renbaoshuo/expo-harmony/contributors).

> [Personal Website](https://baoshuo.ren) · [Blog](https://blog.baoshuo.ren) · GitHub [@renbaoshuo](https://github.com/renbaoshuo) · Twitter [@renbaoshuo](https://twitter.com/renbaoshuo)
