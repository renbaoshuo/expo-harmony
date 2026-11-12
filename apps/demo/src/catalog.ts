/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

export const MODULE_CATEGORIES = [
  '核心运行时',
  '应用',
  '设备与媒体',
  '后台任务',
] as const;

export type ModuleCategory = typeof MODULE_CATEGORIES[number];

export const MODULES = [
  { id: 'expo', title: 'Expo 宿主', packageName: '@expo-harmony/expo', category: '核心运行时' },
  { id: 'expo-modules-core', title: 'Expo Modules Core', packageName: '@expo-harmony/expo-modules-core', category: '核心运行时' },
  { id: 'devtools', title: '开发工具 DevTools', packageName: '@expo-harmony/expo', category: '核心运行时' },
  { id: 'dev-menu', title: '开发菜单', packageName: '@expo-harmony/expo-dev-menu', category: '核心运行时' },
  { id: 'dom-webview', title: 'DOM WebView', packageName: '@expo-harmony/expo__dom-webview', category: '核心运行时' },
  { id: 'log-box', title: 'Expo LogBox', packageName: '@expo-harmony/expo__log-box', category: '核心运行时' },
  { id: 'eas-client', title: 'EAS 客户端', packageName: '@expo-harmony/expo-eas-client', category: '核心运行时' },
  { id: 'manifests', title: '更新清单', packageName: '@expo-harmony/expo-manifests', category: '核心运行时' },
  { id: 'json-utils', title: 'JSON 字段读取', packageName: '@expo-harmony/expo-json-utils', category: '核心运行时' },
  { id: 'structured-headers', title: '结构化响应头', packageName: '@expo-harmony/expo-structured-headers', category: '核心运行时' },
  { id: 'updates-interface', title: 'Updates 原生接口', packageName: '@expo-harmony/expo-updates-interface', category: '核心运行时' },
  { id: 'updates', title: '应用更新', packageName: '@expo-harmony/expo-updates', category: '核心运行时' },
  { id: 'expo-module-showcase', title: 'Expo 原生模块', packageName: 'modules/expo-module-showcase', category: '核心运行时' },
  { id: 'expo-router', title: 'Expo Router', packageName: 'expo-router', category: '核心运行时' },
  { id: 'expo-task-manager', title: '任务管理器', packageName: '@expo-harmony/expo-task-manager', category: '核心运行时' },

  { id: 'screen-orientation', title: '屏幕方向', packageName: '@expo-harmony/expo-screen-orientation', category: '应用' },
  { id: 'screen-capture', title: '截屏保护', packageName: '@expo-harmony/expo-screen-capture', category: '应用' },
  { id: 'sqlite', title: 'SQLite 数据库', packageName: '@expo-harmony/expo-sqlite', category: '应用' },
  { id: 'secure-store', title: '安全存储', packageName: '@expo-harmony/expo-secure-store', category: '应用' },
  { id: 'app-integrity', title: '应用完整性', packageName: '@expo-harmony/expo-app-integrity', category: '应用' },
  { id: 'local-authentication', title: '本地身份认证', packageName: '@expo-harmony/expo-local-authentication', category: '应用' },
  { id: 'age-range', title: '年龄范围', packageName: '@expo-harmony/expo-age-range', category: '应用' },
  { id: 'tracking-transparency', title: '跟踪透明度', packageName: '@expo-harmony/expo-tracking-transparency', category: '应用' },
  { id: 'store-review', title: '商店评价', packageName: '@expo-harmony/expo-store-review', category: '应用' },
  { id: 'app-metrics', title: '应用指标', packageName: '@expo-harmony/expo-app-metrics', category: '应用' },
  { id: 'application', title: '应用信息', packageName: '@expo-harmony/expo-application', category: '应用' },
  { id: 'asset', title: '资源', packageName: '@expo-harmony/expo-asset', category: '应用' },
  { id: 'image', title: '图片', packageName: '@expo-harmony/expo-image', category: '设备与媒体' },
  { id: 'image-loader', title: '图片加载服务', packageName: '@expo-harmony/expo-image-loader', category: '设备与媒体' },
  { id: 'image-manipulator', title: '图片处理', packageName: '@expo-harmony/expo-image-manipulator', category: '设备与媒体' },
  { id: 'video', title: '视频', packageName: '@expo-harmony/expo-video', category: '设备与媒体' },
  { id: 'video-thumbnails', title: '视频缩略图', packageName: '@expo-harmony/expo-video-thumbnails', category: '设备与媒体' },
  { id: 'image-picker', title: '图片选择器', packageName: '@expo-harmony/expo-image-picker', category: '设备与媒体' },
  { id: 'blob', title: '二进制数据', packageName: '@expo-harmony/expo-blob', category: '应用' },
  { id: 'constants', title: '常量', packageName: '@expo-harmony/expo-constants', category: '应用' },
  { id: 'font', title: '字体', packageName: '@expo-harmony/expo-font', category: '应用' },
  { id: 'intent-launcher', title: 'Intent 启动器', packageName: '@expo-harmony/expo-intent-launcher', category: '应用' },
  { id: 'splash-screen', title: '启动屏', packageName: '@expo-harmony/expo-splash-screen', category: '应用' },
  { id: 'status-bar', title: '状态栏', packageName: '@expo-harmony/expo-status-bar', category: '应用' },
  { id: 'system-ui', title: '系统 UI', packageName: '@expo-harmony/expo-system-ui', category: '应用' },
  { id: 'notifications', title: '通知', packageName: '@expo-harmony/expo-notifications', category: '应用' },
  { id: 'localization', title: '语言与地区', packageName: '@expo-harmony/expo-localization', category: '应用' },

  { id: 'audio', title: '音频', packageName: '@expo-harmony/expo-audio', category: '设备与媒体' },
  { id: 'speech', title: '语音合成', packageName: '@expo-harmony/expo-speech', category: '设备与媒体' },
  { id: 'battery', title: '电池', packageName: '@expo-harmony/expo-battery', category: '设备与媒体' },
  { id: 'blur', title: '模糊', packageName: '@expo-harmony/expo-blur', category: '设备与媒体' },
  { id: 'brightness', title: '亮度', packageName: '@expo-harmony/expo-brightness', category: '设备与媒体' },
  { id: 'calendar', title: '日历', packageName: '@expo-harmony/expo-calendar', category: '设备与媒体' },
  { id: 'camera', title: '相机', packageName: '@expo-harmony/expo-camera', category: '设备与媒体' },
  { id: 'cellular', title: '蜂窝网络', packageName: '@expo-harmony/expo-cellular', category: '设备与媒体' },
  { id: 'clipboard', title: '剪贴板', packageName: '@expo-harmony/expo-clipboard', category: '设备与媒体' },
  { id: 'crypto', title: '加密', packageName: '@expo-harmony/expo-crypto', category: '设备与媒体' },
  { id: 'contacts', title: '联系人', packageName: '@expo-harmony/expo-contacts', category: '设备与媒体' },
  { id: 'device', title: '设备信息', packageName: '@expo-harmony/expo-device', category: '设备与媒体' },
  { id: 'document-picker', title: '文档选择器', packageName: '@expo-harmony/expo-document-picker', category: '设备与媒体' },
  { id: 'fetch', title: '网络请求', packageName: '@expo-harmony/expo', category: '设备与媒体' },
  { id: 'file-system', title: '文件系统', packageName: '@expo-harmony/expo-file-system', category: '设备与媒体' },
  { id: 'sensors', title: '传感器', packageName: '@expo-harmony/expo-sensors', category: '设备与媒体' },
  { id: 'haptics', title: '触感反馈', packageName: '@expo-harmony/expo-haptics', category: '设备与媒体' },
  { id: 'keep-awake', title: '保持唤醒', packageName: '@expo-harmony/expo-keep-awake', category: '设备与媒体' },
  { id: 'linear-gradient', title: '线性渐变', packageName: '@expo-harmony/expo-linear-gradient', category: '设备与媒体' },
  { id: 'mesh-gradient', title: '网格渐变', packageName: '@expo-harmony/expo-mesh-gradient', category: '设备与媒体' },
  { id: 'symbols', title: '系统图标', packageName: '@expo-harmony/expo-symbols', category: '设备与媒体' },
  { id: 'linking', title: '链接', packageName: '@expo-harmony/expo-linking', category: '设备与媒体' },
  { id: 'web-browser', title: '网页浏览器', packageName: '@expo-harmony/expo-web-browser', category: '设备与媒体' },
  { id: 'live-photo', title: '实况照片', packageName: '@expo-harmony/expo-live-photo', category: '设备与媒体' },
  { id: 'location', title: '定位', packageName: '@expo-harmony/expo-location', category: '设备与媒体' },
  { id: 'media-library', title: '媒体库', packageName: '@expo-harmony/expo-media-library', category: '设备与媒体' },
  { id: 'navigation-bar', title: '导航栏', packageName: '@expo-harmony/expo-navigation-bar', category: '设备与媒体' },
  { id: 'network', title: '网络', packageName: '@expo-harmony/expo-network', category: '设备与媒体' },
  { id: 'print', title: '打印', packageName: '@expo-harmony/expo-print', category: '设备与媒体' },
  { id: 'sharing', title: '分享', packageName: '@expo-harmony/expo-sharing', category: '设备与媒体' },
  { id: 'sms', title: '短信', packageName: '@expo-harmony/expo-sms', category: '设备与媒体' },
  { id: 'mail-composer', title: '邮件', packageName: '@expo-harmony/expo-mail-composer', category: '设备与媒体' },

  { id: 'background-fetch', title: '后台拉取', packageName: '@expo-harmony/expo-background-fetch', category: '后台任务' },
  { id: 'background-task', title: '后台任务', packageName: '@expo-harmony/expo-background-task', category: '后台任务' },
] as const satisfies readonly {
  id: string;
  title: string;
  packageName: string;
  category: ModuleCategory;
}[];

export type ModuleId = typeof MODULES[number]['id'];
export type ModuleDefinition = typeof MODULES[number];

export function findModule(value: string | string[] | undefined): ModuleDefinition | undefined {
  const id = Array.isArray(value) ? value[0] : value;
  return MODULES.find(module => module.id === id);
}
