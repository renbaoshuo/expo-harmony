/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import AntDesign from '@expo/vector-icons/AntDesign';
import { useFonts } from 'expo-font';
import { NavigationBar } from 'expo-navigation-bar';
import { DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import * as SystemUI from 'expo-system-ui';
import { useEffect } from 'react';
import { Platform, View } from 'react-native';
import { initialWindowMetrics, SafeAreaProvider } from 'react-native-safe-area-context';

import { readSplashOptions } from '../src/splash-options';
import { palette } from '../src/theme';

void SplashScreen.preventAutoHideAsync().catch(() => false);
void SystemUI.setBackgroundColorAsync(palette.canvas).catch(() => undefined);

export { ErrorBoundary } from 'expo-router';

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts(AntDesign.font);

  useEffect(() => {
    if (fontError) throw new Error(fontError.message, { cause: fontError });
  }, [fontError]);

  useEffect(() => {
    if (!fontsLoaded) return;

    const options = readSplashOptions();
    if (options) {
      try {
        SplashScreen.setOptions(options);
      } catch (error) {
        console.warn('应用启动屏设置失败', error);
      }
    }
    void SplashScreen.hideAsync().catch(() => undefined);
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <View style={{ flex: 1 }}>
      <SafeAreaProvider initialMetrics={initialWindowMetrics}>
        <ThemeProvider value={DefaultTheme}>
          <NavigationBar style="dark" hidden={false} />
          <Stack
            screenOptions={{
              contentStyle: { backgroundColor: palette.canvas },
              headerBackButtonDisplayMode: 'minimal',
              headerShadowVisible: false,
              headerStyle: { backgroundColor: palette.surface },
              headerTintColor: palette.signal,
              headerTitleStyle: { color: palette.text, fontWeight: '700' },
              statusBarBackgroundColor: String(Platform.OS) === 'harmony' ? palette.canvas : undefined,
              statusBarStyle: 'dark',
            }}
          >
            <Stack.Screen name="index" options={{ headerShown: false }} />
            <Stack.Screen name="module/[module]" options={{ title: '模块' }} />
            <Stack.Screen name="router-fixture/[value]" options={{ title: '动态路由' }} />
          </Stack>
        </ThemeProvider>
      </SafeAreaProvider>
    </View>
  );
}
