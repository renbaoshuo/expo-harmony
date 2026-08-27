import AntDesign from '@expo/vector-icons/AntDesign';
import { router } from 'expo-router';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { MODULE_CATEGORIES, MODULES } from '../src/catalog';
import { palette } from '../src/theme';

export default function HomeScreen() {
  const insets = useSafeAreaInsets();

  return (
    <ScrollView
      contentContainerStyle={[styles.page, { paddingTop: insets.top + 22, paddingBottom: insets.bottom + 40 }]}
      showsVerticalScrollIndicator={false}
      testID="home-module-list"
    >
      <View style={styles.header}>
        <View style={styles.badge}>
          <Text style={styles.badgeText}>HARMONYOS · SDK 55</Text>
        </View>
        <Text style={styles.title}>模块实验室</Text>
        <Text style={styles.subtitle}>
          选择一个模块包，运行其中的验证卡片，逐项查看每项原生能力的实际结果。
        </Text>
        <Text style={styles.count}>当前分支共收录 {MODULES.length} 个包</Text>
      </View>

      {MODULE_CATEGORIES.map((category) => {
        const modules = MODULES.filter(module => module.category === category);
        return (
          <View key={category} style={styles.section}>
            <Text style={styles.sectionTitle}>{category}</Text>
            <View style={styles.list}>
              {modules.map(module => (
                <Pressable
                  accessibilityHint={`打开 ${module.packageName} 的测试页面`}
                  accessibilityRole="button"
                  key={module.id}
                  onPress={() => router.push(`/module/${module.id}`)}
                  style={({ pressed }) => [styles.item, pressed && styles.itemPressed]}
                  testID={`home-open-${module.id}`}
                >
                  <View style={styles.itemCopy}>
                    <Text style={styles.itemTitle}>{module.title}</Text>
                    <Text numberOfLines={1} style={styles.itemPackage}>{module.packageName}</Text>
                    <Text numberOfLines={2} style={styles.itemSummary}>{module.summary}</Text>
                  </View>
                  <AntDesign color={palette.faint} name="right" size={15} />
                </Pressable>
              ))}
            </View>
          </View>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { backgroundColor: palette.canvas, paddingHorizontal: 16 },
  header: { gap: 9, paddingBottom: 26, paddingHorizontal: 4 },
  badge: { alignSelf: 'flex-start', backgroundColor: palette.signalSoft, borderRadius: 8, paddingHorizontal: 9, paddingVertical: 5 },
  badgeText: { color: palette.signal, fontSize: 10, fontWeight: '800', letterSpacing: 0.5 },
  title: { color: palette.text, fontSize: 34, fontWeight: '800', letterSpacing: -1, lineHeight: 40 },
  subtitle: { color: palette.muted, fontSize: 15, lineHeight: 22, maxWidth: 560 },
  count: { color: palette.faint, fontSize: 12, fontWeight: '600' },
  section: { gap: 9, marginBottom: 24 },
  sectionTitle: { color: palette.muted, fontSize: 13, fontWeight: '700', paddingHorizontal: 4, textTransform: 'uppercase' },
  list: { gap: 10 },
  item: {
    alignItems: 'center',
    backgroundColor: palette.surface,
    borderRadius: 16,
    elevation: 2,
    flexDirection: 'row',
    gap: 14,
    minHeight: 88,
    padding: 16,
    shadowColor: '#000000',
    shadowOffset: { height: 1, width: 0 },
    shadowOpacity: 0.07,
    shadowRadius: 4,
  },
  itemPressed: { opacity: 0.88, transform: [{ scale: 0.96 }] },
  itemCopy: { flex: 1, gap: 3 },
  itemTitle: { color: palette.text, fontSize: 17, fontWeight: '700' },
  itemPackage: { color: palette.signal, fontFamily: 'monospace', fontSize: 10 },
  itemSummary: { color: palette.muted, fontSize: 12, lineHeight: 17, marginTop: 2 },
});
