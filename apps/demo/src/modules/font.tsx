import AntDesign from '@expo/vector-icons/AntDesign';
import * as Font from 'expo-font';
import { useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { antDesignFontAsset, DYNAMIC_FONT_FAMILY } from '../fixtures';
import { palette } from '../theme';
import { ActionButton, ActionRow, DataRow, Panel, ResultPanel, Tag, useAsyncResult } from '../ui';

export function FontDemo() {
  const action = useAsyncResult();
  const [revision, setRevision] = useState(0);
  const loaded = Font.getLoadedFonts();
  const glyphValue = AntDesign.glyphMap.experiment;
  const glyph = typeof glyphValue === 'number' ? String.fromCodePoint(glyphValue) : glyphValue;

  const refresh = async (operation: () => Promise<void>, message: string) => {
    await operation();
    setRevision(value => value + 1);
    return `${message}\n\n已加载的字体系列：\n${Font.getLoadedFonts().join('\n')}`;
  };

  return (
    <>
      <Panel eyebrow="CNG 资源" title="应用启动时的内置字体">
        <View style={styles.fontSpecimen}>
          <AntDesign color={palette.signal} name="experiment" size={42} />
          <View style={styles.specimenCopy}>
            <Text style={styles.specimenTitle}>AntDesign</Text>
            <Text style={styles.specimenCaption}>已在 JavaScript 运行前完成注册</Text>
          </View>
          <Tag tone={Font.isLoaded('AntDesign') ? 'success' : 'danger'}>
            {Font.isLoaded('AntDesign') ? '已加载' : '未加载'}
          </Tag>
        </View>
      </Panel>

      <Panel eyebrow="运行时注册" title="加载与卸载字体系列别名">
        <View key={revision} style={styles.dynamicSpecimen}>
          <Text style={[styles.dynamicGlyph, { fontFamily: DYNAMIC_FONT_FAMILY }]}>{glyph}</Text>
          <Text style={styles.specimenCaption}>{DYNAMIC_FONT_FAMILY}</Text>
        </View>
        <ActionRow>
          <ActionButton
            disabled={action.state.phase === 'running'}
            label="加载别名"
            onPress={() => void action.run(() => refresh(
              () => Font.loadAsync(DYNAMIC_FONT_FAMILY, antDesignFontAsset()),
              '动态字体系列已注册。'
            ))}
          />
          <ActionButton
            disabled={action.state.phase === 'running' || !Font.isLoaded(DYNAMIC_FONT_FAMILY)}
            label="卸载别名"
            onPress={() => void action.run(() => refresh(
              () => Font.unloadAsync(DYNAMIC_FONT_FAMILY),
              '动态字体系列已注销。'
            ))}
            tone="secondary"
          />
        </ActionRow>
        <DataRow label="已加载字体系列数" value={String(loaded.length)} />
        <ResultPanel state={action.state} />
      </Panel>
    </>
  );
}

const styles = StyleSheet.create({
  fontSpecimen: { alignItems: 'center', flexDirection: 'row', gap: 14 },
  specimenCopy: { flex: 1, gap: 3 },
  specimenTitle: { color: palette.text, fontSize: 18, fontWeight: '700' },
  specimenCaption: { color: palette.muted, fontSize: 12, lineHeight: 17 },
  dynamicSpecimen: { alignItems: 'center', backgroundColor: palette.canvas, borderColor: palette.line, borderRadius: 4, borderWidth: 1, gap: 8, minHeight: 118, justifyContent: 'center' },
  dynamicGlyph: { color: palette.cyan, fontSize: 44 },
});
