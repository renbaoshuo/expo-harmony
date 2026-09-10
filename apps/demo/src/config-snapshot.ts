import Constants from 'expo-constants';

export function configSnapshot() {
  const config = Constants.expoConfig as (typeof Constants.expoConfig & {
    harmony?: Record<string, unknown>;
    plugins?: unknown[];
  }) | null;
  if (!config?.harmony) throw new Error('缺少内嵌的 Harmony 配置。');
  return config;
}
