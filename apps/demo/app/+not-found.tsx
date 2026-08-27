import { Link, Stack } from 'expo-router';
import { StyleSheet, Text, View } from 'react-native';

import { palette } from '../src/theme';

export default function NotFoundScreen() {
  return (
    <>
      <Stack.Screen options={{ title: '页面不存在' }} />
      <View style={styles.page}>
        <Text style={styles.title}>您访问的页面不存在。</Text>
        <Link href="/" style={styles.link}>返回模块列表</Link>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  page: { alignItems: 'center', backgroundColor: palette.canvas, flex: 1, gap: 16, justifyContent: 'center', padding: 24 },
  title: { color: palette.text, fontSize: 20, fontWeight: '700' },
  link: { color: palette.signal, fontSize: 16, fontWeight: '600' },
});
