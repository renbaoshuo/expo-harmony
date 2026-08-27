import React, { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StatusBar,
  StyleProp,
  StyleSheet,
  Text,
  TextInput,
  TextInputProps,
  View,
  ViewStyle,
} from 'react-native';

import { palette, spacing } from './theme';

export type AsyncResultState = {
  phase: 'idle' | 'running' | 'success' | 'error';
  output?: string;
};

export function formatError(error: unknown): string {
  if (error instanceof Error) return error.stack || error.message;
  return String(error);
}

export function useAsyncResult() {
  const [state, setState] = useState<AsyncResultState>({ phase: 'idle' });
  const run = useCallback(async (operation: () => Promise<string> | string) => {
    setState({ phase: 'running' });
    try {
      const output = await operation();
      setState({ output, phase: 'success' });
      return output;
    } catch (error) {
      setState({ output: formatError(error), phase: 'error' });
      return undefined;
    }
  }, []);
  const clear = useCallback(() => setState({ phase: 'idle' }), []);
  return { clear, run, state };
}

type LabScreenProps = React.PropsWithChildren<{
  description: string;
  kicker: string;
  testID?: string;
  title: string;
}>;

export function LabScreen({ children, description, kicker, testID, title }: LabScreenProps) {
  return (
    <View style={styles.root} testID={testID}>
      <StatusBar backgroundColor={palette.canvas} barStyle="dark-content" />
      <ScrollView
        contentContainerStyle={styles.page}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        <Text style={styles.kicker}>{kicker}</Text>
        <Text style={styles.title}>{title}</Text>
        <Text style={styles.description}>{description}</Text>
        <View style={styles.content}>{children}</View>
      </ScrollView>
    </View>
  );
}

type PanelProps = React.PropsWithChildren<{
  eyebrow?: string;
  style?: StyleProp<ViewStyle>;
  title?: string;
}>;

export function Panel({ children, eyebrow, style, title }: PanelProps) {
  return (
    <View style={[styles.panel, style]}>
      {eyebrow ? <Text style={styles.panelEyebrow}>{eyebrow}</Text> : null}
      {title ? <Text style={styles.panelTitle}>{title}</Text> : null}
      {children}
    </View>
  );
}

export function DataRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <View style={styles.dataRow}>
      <Text style={styles.dataLabel}>{label}</Text>
      {typeof value === 'string' || typeof value === 'number'
        ? <Text selectable style={styles.dataValue}>{value}</Text>
        : value}
    </View>
  );
}

export function Tag({ children, tone = 'neutral' }: React.PropsWithChildren<{
  tone?: 'neutral' | 'signal' | 'success' | 'danger';
}>) {
  return (
    <View style={[styles.tag, styles[`tag_${tone}`]]}>
      <Text style={[styles.tagText, styles[`tagText_${tone}`]]}>{children}</Text>
    </View>
  );
}

type ActionButtonProps = {
  disabled?: boolean;
  label: string;
  onPress: () => void;
  testID?: string;
  tone?: 'primary' | 'secondary' | 'danger';
};

export function ActionButton({ disabled, label, onPress, testID, tone = 'primary' }: ActionButtonProps) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.actionButton,
        styles[`actionButton_${tone}`],
        pressed && !disabled && styles.actionButtonPressed,
        disabled && styles.actionButtonDisabled,
      ]}
      testID={testID}
    >
      <Text style={[styles.actionButtonText, tone === 'secondary' && styles.actionButtonTextSecondary]}>
        {label}
      </Text>
    </Pressable>
  );
}

export function ActionRow({ children }: React.PropsWithChildren) {
  return <View style={styles.actionRow}>{children}</View>;
}

export function Field(props: TextInputProps & { label: string }) {
  const { label, ...inputProps } = props;
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        autoCapitalize="none"
        autoCorrect={false}
        placeholderTextColor={palette.faint}
        selectionColor={palette.signal}
        style={styles.fieldInput}
        {...inputProps}
      />
    </View>
  );
}

const RESULT_PHASE_LABELS: Record<AsyncResultState['phase'], string> = {
  error: '失败',
  idle: '待执行',
  running: '执行中',
  success: '成功',
};

export function ResultPanel({ state }: { state: AsyncResultState }) {
  if (state.phase === 'idle') return null;
  let tone: 'danger' | 'signal' | 'success' = 'signal';
  if (state.phase === 'success') tone = 'success';
  else if (state.phase === 'error') tone = 'danger';

  return (
    <View style={[styles.result, styles[`result_${tone}`]]}>
      <View style={styles.resultHeader}>
        {state.phase === 'running' ? <ActivityIndicator color={palette.signal} size="small" /> : null}
        <Text style={[styles.resultLabel, styles[`resultLabel_${tone}`]]}>{RESULT_PHASE_LABELS[state.phase]}</Text>
      </View>
      {state.output ? <Text selectable style={styles.resultOutput}>{state.output}</Text> : null}
    </View>
  );
}

export function Note({ children }: React.PropsWithChildren) {
  return (
    <View style={styles.note}>
      <View style={styles.noteMark} />
      <Text style={styles.noteText}>{children}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { backgroundColor: palette.canvas, flex: 1 },
  page: { paddingBottom: 48, paddingHorizontal: spacing.page, paddingTop: 24 },
  kicker: { color: palette.signal, fontSize: 12, fontWeight: '700', letterSpacing: 0.5, textTransform: 'uppercase' },
  title: { color: palette.text, fontSize: 32, fontWeight: '800', letterSpacing: -0.8, lineHeight: 38, marginTop: 8 },
  description: { color: palette.muted, fontSize: 15, lineHeight: 22, marginTop: 10, maxWidth: 640 },
  content: { gap: spacing.section, marginTop: 24 },
  panel: {
    backgroundColor: palette.surface,
    borderRadius: 16,
    elevation: 2,
    gap: 12,
    padding: spacing.card,
    shadowColor: '#000000',
    shadowOffset: { height: 1, width: 0 },
    shadowOpacity: 0.08,
    shadowRadius: 4,
  },
  panelEyebrow: { color: palette.signal, fontSize: 11, fontWeight: '700', letterSpacing: 0.4, textTransform: 'uppercase' },
  panelTitle: { color: palette.text, fontSize: 18, fontWeight: '700', lineHeight: 23 },
  dataRow: { alignItems: 'flex-start', borderTopColor: palette.line, borderTopWidth: StyleSheet.hairlineWidth, flexDirection: 'row', gap: 14, justifyContent: 'space-between', minHeight: 42, paddingTop: 11 },
  dataLabel: { color: palette.muted, flex: 1, fontSize: 13, lineHeight: 19 },
  dataValue: { color: palette.text, flex: 1.4, fontFamily: 'monospace', fontSize: 12, lineHeight: 18, textAlign: 'right' },
  tag: { alignSelf: 'flex-start', borderRadius: 8, paddingHorizontal: 9, paddingVertical: 5 },
  tag_neutral: { backgroundColor: palette.surfaceRaised },
  tag_signal: { backgroundColor: palette.signalSoft },
  tag_success: { backgroundColor: palette.successSoft },
  tag_danger: { backgroundColor: palette.dangerSoft },
  tagText: { fontSize: 10, fontWeight: '700', letterSpacing: 0.3 },
  tagText_neutral: { color: palette.muted },
  tagText_signal: { color: palette.signal },
  tagText_success: { color: palette.success },
  tagText_danger: { color: palette.danger },
  actionRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  actionButton: { alignItems: 'center', borderRadius: 10, justifyContent: 'center', minHeight: 44, paddingHorizontal: 15, paddingVertical: 10 },
  actionButton_primary: { backgroundColor: palette.signal },
  actionButton_secondary: { backgroundColor: palette.signalSoft },
  actionButton_danger: { backgroundColor: palette.danger },
  actionButtonPressed: { opacity: 0.88, transform: [{ scale: 0.96 }] },
  actionButtonDisabled: { opacity: 0.42 },
  actionButtonText: { color: '#FFFFFF', fontSize: 12, fontWeight: '700' },
  actionButtonTextSecondary: { color: palette.signal },
  field: { gap: 8 },
  fieldLabel: { color: palette.muted, fontSize: 12, fontWeight: '600' },
  fieldInput: { backgroundColor: palette.surfaceRaised, borderColor: palette.lineStrong, borderRadius: 10, borderWidth: StyleSheet.hairlineWidth, color: palette.text, fontFamily: 'monospace', fontSize: 12, minHeight: 48, paddingHorizontal: 13, paddingVertical: 10 },
  result: { borderRadius: 10, gap: 10, padding: 13 },
  result_signal: { backgroundColor: palette.signalSoft },
  result_success: { backgroundColor: palette.successSoft },
  result_danger: { backgroundColor: palette.dangerSoft },
  resultHeader: { alignItems: 'center', flexDirection: 'row', gap: 8 },
  resultLabel: { fontSize: 10, fontWeight: '800', letterSpacing: 0.6 },
  resultLabel_signal: { color: palette.signal },
  resultLabel_success: { color: palette.success },
  resultLabel_danger: { color: palette.danger },
  resultOutput: { color: palette.text, fontFamily: 'monospace', fontSize: 11, lineHeight: 17 },
  note: { backgroundColor: palette.surfaceRaised, borderRadius: 12, flexDirection: 'row', gap: 12, padding: 13 },
  noteMark: { backgroundColor: palette.cyan, borderRadius: 2, width: 3 },
  noteText: { color: palette.muted, flex: 1, fontSize: 13, lineHeight: 20 },
});
