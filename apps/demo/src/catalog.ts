export const MODULE_CATEGORIES = [
  '核心运行时',
  '应用',
  '设备与媒体',
  '后台任务',
  '构建工具链',
] as const;

export type ModuleCategory = typeof MODULE_CATEGORIES[number];

export const MODULES = [
  { id: 'expo-modules-core', title: 'Expo Modules Core', packageName: '@expo-harmony/expo-modules-core', category: '核心运行时', summary: '原生模块注册表、事件发射器与 Expo 运行时桥接。' },
  { id: 'expo-module-showcase', title: 'Expo Modules 测试', packageName: 'modules/expo-module-showcase', category: '核心运行时', summary: '使用本地模块测试原生调用、事件、共享对象、原生组件与页面，覆盖 Android、iOS 和 HarmonyOS。' },
  { id: 'expo-router', title: 'Expo Router', packageName: 'expo-router', category: '核心运行时', summary: '基于文件的路由、类型化参数、堆栈导航与深链接。' },
  { id: 'expo-task-manager', title: '任务管理器', packageName: '@expo-harmony/expo-task-manager', category: '核心运行时', summary: '全局任务定义与持久化的原生注册。' },

  { id: 'app-metrics', title: '应用指标', packageName: '@expo-harmony/expo-app-metrics', category: '应用', summary: '启动耗时、会话、诊断信息与持久化指标。' },
  { id: 'application', title: '应用信息', packageName: '@expo-harmony/expo-application', category: '应用', summary: '应用包标识、版本号、显示名称与安装时间。' },
  { id: 'asset', title: '资源', packageName: '@expo-harmony/expo-asset', category: '应用', summary: '内置资源、本地 URI 与远程缓存行为。' },
  { id: 'constants', title: '常量', packageName: '@expo-harmony/expo-constants', category: '应用', summary: '内嵌的应用配置、设备信息与运行时标识。' },
  { id: 'font', title: '字体', packageName: '@expo-harmony/expo-font', category: '应用', summary: '内置字体资源与运行时注册。' },
  { id: 'splash-screen', title: '启动屏', packageName: '@expo-harmony/expo-splash-screen', category: '应用', summary: '启动过程接管与幂等的内容就绪交接。' },
  { id: 'system-ui', title: '系统 UI', packageName: '@expo-harmony/expo-system-ui', category: '应用', summary: '根窗口背景与界面样式配置。' },

  { id: 'audio', title: '音频', packageName: '@expo-harmony/expo-audio', category: '设备与媒体', summary: '播放、预加载、播放列表状态与后台音频。' },
  { id: 'battery', title: '电池', packageName: '@expo-harmony/expo-battery', category: '设备与媒体', summary: '电源状态快照、Hook 与原生状态事件。' },
  { id: 'blur', title: '模糊', packageName: '@expo-harmony/expo-blur', category: '设备与媒体', summary: '原生模糊视图、色调变体与强度更新。' },
  { id: 'camera', title: '相机', packageName: '@expo-harmony/expo-camera', category: '设备与媒体', summary: '权限申请、预览、拍照与镜头能力。' },
  { id: 'crypto', title: '加密', packageName: '@expo-harmony/expo-crypto', category: '设备与媒体', summary: '摘要、随机字节、UUID 与 AES-GCM 往返校验。' },
  { id: 'fetch', title: '网络请求', packageName: '@expo-harmony/expo-fetch', category: '设备与媒体', summary: '通过 Expo fetch 实现的流式 HTTP 与本地文件响应。' },
  { id: 'file-system', title: '文件系统', packageName: '@expo-harmony/expo-file-system', category: '设备与媒体', summary: '文件、目录、原始句柄与系统选择器。' },
  { id: 'haptics', title: '触感反馈', packageName: '@expo-harmony/expo-haptics', category: '设备与媒体', summary: '官方反馈样式与参数校验。' },
  { id: 'keep-awake', title: '保持唤醒', packageName: '@expo-harmony/expo-keep-awake', category: '设备与媒体', summary: '带标签的屏幕常亮与 React 生命周期处理。' },
  { id: 'linear-gradient', title: '线性渐变', packageName: '@expo-harmony/expo-linear-gradient', category: '设备与媒体', summary: '多色渐变、端点控制与圆角裁剪。' },
  { id: 'linking', title: '链接', packageName: '@expo-harmony/expo-linking', category: '设备与媒体', summary: 'URL 构造、解析、初始状态与前台链接。' },
  { id: 'navigation-bar', title: '导航栏', packageName: '@expo-harmony/expo-navigation-bar', category: '设备与媒体', summary: '系统导航栏颜色、按键与可见性。' },
  { id: 'network', title: '网络', packageName: '@expo-harmony/expo-network', category: '设备与媒体', summary: '连接类型、可达性、IP 地址与状态事件。' },
  { id: 'sharing', title: '分享', packageName: '@expo-harmony/expo-sharing', category: '设备与媒体', summary: '通过 Harmony 系统面板分享本地文件。' },

  { id: 'background-fetch', title: '后台拉取', packageName: '@expo-harmony/expo-background-fetch', category: '后台任务', summary: 'WorkScheduler 注册与 JavaScript 回调。' },
  { id: 'background-task', title: '后台任务', packageName: '@expo-harmony/expo-background-task', category: '后台任务', summary: '新一代后台任务与调试触发行为。' },

  { id: 'cli', title: 'CLI', packageName: '@expo-harmony/cli', category: '构建工具链', summary: '用于准备、导出和运行 Harmony 应用的公开命令契约。' },
  { id: 'config-plugins', title: '配置插件', packageName: '@expo-harmony/config-plugins', category: '构建工具链', summary: 'Harmony 应用配置与受管理的原生修改。' },
  { id: 'expo-modules-autolinking', title: '模块自动链接', packageName: '@expo-harmony/expo-modules-autolinking', category: '构建工具链', summary: 'Harmony Expo 模块的自动发现与注册。' },
  { id: 'metro-config', title: 'Metro 配置', packageName: '@expo-harmony/metro-config', category: '构建工具链', summary: '面向 Harmony 的模块解析、资源处理与打包目标。' },
  { id: 'prebuild-config', title: 'Prebuild 配置', packageName: '@expo-harmony/prebuild-config', category: '构建工具链', summary: '生成的原生工程、描述文件与 CNG 清单。' },
  { id: 'template', title: '模板', packageName: '@expo-harmony/template', category: '构建工具链', summary: 'Harmony 应用的基线依赖与运行时契约。' },
] as const satisfies readonly {
  id: string;
  title: string;
  packageName: string;
  category: ModuleCategory;
  summary: string;
}[];

export type ModuleId = typeof MODULES[number]['id'];
export type ModuleDefinition = typeof MODULES[number];

export function findModule(value: string | string[] | undefined): ModuleDefinition | undefined {
  const id = Array.isArray(value) ? value[0] : value;
  return MODULES.find(module => module.id === id);
}
