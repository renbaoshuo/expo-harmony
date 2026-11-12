/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

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
        <Text style={styles.title}>Expo 模块演示</Text>
      </View>

      {MODULE_CATEGORIES.map((category) => {
        const modules = MODULES.filter(module => module.category === category);
        return (
          <View key={category} style={styles.section}>
            <Text style={styles.sectionTitle}>{category}</Text>
            <View style={styles.list}>
              {modules.map(module => (
                <Pressable
                  accessibilityLabel={`${module.title}，${module.packageName}`}
                  accessibilityRole="button"
                  key={module.id}
                  onPress={() => router.push(`/module/${module.id}`)}
                  style={({ pressed }) => [styles.item, pressed && styles.itemPressed]}
                  testID={`home-open-${module.id}`}
                >
                  <View style={styles.itemCopy}>
                    <Text style={styles.itemTitle}>{module.title}</Text>
                    <Text style={styles.itemPackage}>{module.packageName}</Text>
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
  header: { paddingBottom: 26, paddingHorizontal: 4 },
  title: { color: palette.text, fontSize: 34, fontWeight: '800', letterSpacing: -1, lineHeight: 40 },
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
    minHeight: 56,
    padding: 16,
    shadowColor: '#000000',
    shadowOffset: { height: 1, width: 0 },
    shadowOpacity: 0.07,
    shadowRadius: 4,
  },
  itemPressed: { opacity: 0.88, transform: [{ scale: 0.96 }] },
  itemCopy: { flex: 1, gap: 3 },
  itemTitle: { color: palette.text, fontSize: 17, fontWeight: '700' },
  itemPackage: { color: palette.muted, fontFamily: 'monospace', fontSize: 12, lineHeight: 16 },
});
