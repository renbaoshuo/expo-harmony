import AntDesign from '@expo/vector-icons/AntDesign';
import { DefaultTheme, ThemeProvider } from '@react-navigation/native';
import { useFonts } from 'expo-font';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import * as SystemUI from 'expo-system-ui';
import { useEffect } from 'react';
import { Platform } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { initialWindowMetrics, SafeAreaProvider } from 'react-native-safe-area-context';

import '../src/backgroundFetch';
import '../src/backgroundTask';
import { palette } from '../src/theme';

void SplashScreen.preventAutoHideAsync().catch(() => false);
void SystemUI.setBackgroundColorAsync(palette.canvas).catch(() => undefined);

export { ErrorBoundary } from 'expo-router';

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts(AntDesign.font);

  useEffect(() => {
    if (fontError) throw fontError;
  }, [fontError]);

  useEffect(() => {
    if (fontsLoaded) void SplashScreen.hideAsync().catch(() => undefined);
  }, [fontsLoaded]);

  if (!fontsLoaded) return null;

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider initialMetrics={initialWindowMetrics}>
        <ThemeProvider value={DefaultTheme}>
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
            <Stack.Screen name="router-fixture/[value]" options={{ title: '路由测试' }} />
          </Stack>
        </ThemeProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
