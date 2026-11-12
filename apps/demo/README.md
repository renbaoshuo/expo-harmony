# demo

这是 Expo Harmony 的示例应用。各模块页面可调用 API、调整参数并查看返回值或事件。联系人、日历、媒体库和文件系统页面也提供相应 API 示例。

HarmonyOS 版本直接打开示例应用。开发版可查看 LogBox 日志和 React Native DevTools 网络请求。

[查阅接入指南 >>](../../docs/QuickStart.md)

---

如果要在已有的 React Native 工程中使用 Expo Harmony，请[查阅接入指南 >>](../../docs/BareInstallation.md)。

示例默认使用系统粘贴按钮、媒体和联系人选择器，并在保存图片前请求用户确认。程序化读取剪贴板、批量访问通讯录或图库、持久化文件访问以及读取或写入完整日历，需要应用声明相应权限并按系统要求申请授权。详见[华为受限开放权限说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/restricted-permissions)。

通知页面可发送即时通知。定时通知需要代理提醒权益、相应的权限声明和获批的签名文件。详见[华为代理提醒接入说明](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-powered-reminder/)。

Tracking Transparency 页面会在用户授权后读取 OAID；应用需要声明 OAID 权限及用途。Age Range 页面可读取系统提供的年龄段。在开启未成年人模式的设备上，监护人可按系统提示批准本次使用。详见[华为未成年人模式接入指南](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/account-overview-minorsprotection/)。
