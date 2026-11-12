/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import React, { useCallback, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
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
  const message = error instanceof Error ? error.message : String(error);
  const code = typeof error === 'object' && error !== null && 'code' in error ? error.code : undefined;
  return typeof code === 'string' && code.length > 0 ? `${code}\n${message}` : message;
}

export function useAsyncResult() {
  const [state, setState] = useState<AsyncResultState>({ phase: 'idle' });
  const request = useRef(0);
  const run = useCallback(async (operation: () => Promise<string> | string) => {
    const id = ++request.current;
    setState({ phase: 'running' });
    try {
      const output = await operation();
      if (request.current === id) setState({ output, phase: 'success' });
      return output;
    } catch (error) {
      if (request.current === id) setState({ output: formatError(error), phase: 'error' });
      return undefined;
    }
  }, []);
  const clear = useCallback(() => {
    request.current++;
    setState({ phase: 'idle' });
  }, []);
  return { clear, run, state };
}

type LabScreenProps = React.PropsWithChildren<{
  testID?: string;
}>;

export function LabScreen({ children, testID }: LabScreenProps) {
  return (
    <View style={styles.root} testID={testID}>
      <ScrollView
        contentContainerStyle={styles.page}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        {children}
      </ScrollView>
    </View>
  );
}

type PanelProps = React.PropsWithChildren<{
  style?: StyleProp<ViewStyle>;
  title?: string;
}>;

export function Panel({ children, style, title }: PanelProps) {
  return (
    <View style={[styles.panel, style]}>
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
  const { label, style, ...inputProps } = props;
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      <TextInput
        accessibilityLabel={label}
        autoCapitalize="none"
        autoCorrect={false}
        placeholderTextColor={palette.faint}
        selectionColor={palette.signal}
        style={[styles.fieldInput, inputProps.multiline && styles.multilineInput, style]}
        {...inputProps}
      />
    </View>
  );
}

export function ResultPanel({ state }: { state: AsyncResultState }) {
  if (state.phase === 'idle') return null;
  let tone: 'danger' | 'signal' | 'success' = 'signal';
  if (state.phase === 'success') tone = 'success';
  else if (state.phase === 'error') tone = 'danger';

  return (
    <View style={[styles.result, styles[`result_${tone}`]]}>
      {state.phase === 'running' ? <ActivityIndicator color={palette.signal} size="small" /> : null}
      {state.phase !== 'running'
        ? <Text selectable style={styles.resultOutput}>{state.output === '' ? '' : state.output ?? '已完成'}</Text>
        : null}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { backgroundColor: palette.canvas, flex: 1 },
  page: { gap: spacing.section, paddingBottom: 48, paddingHorizontal: spacing.page, paddingTop: 16 },
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
  panelTitle: { color: palette.text, fontSize: 18, fontWeight: '700', lineHeight: 23 },
  dataRow: { alignItems: 'flex-start', borderTopColor: palette.line, borderTopWidth: StyleSheet.hairlineWidth, flexDirection: 'row', gap: 14, justifyContent: 'space-between', minHeight: 42, paddingTop: 11 },
  dataLabel: { color: palette.muted, flex: 1, fontSize: 13, lineHeight: 19 },
  dataValue: { color: palette.text, flex: 1.4, fontFamily: 'monospace', fontSize: 12, lineHeight: 18, textAlign: 'right' },
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
  multilineInput: { maxHeight: 180, textAlignVertical: 'top' },
  result: { borderRadius: 10, gap: 10, padding: 13 },
  result_signal: { backgroundColor: palette.signalSoft },
  result_success: { backgroundColor: palette.successSoft },
  result_danger: { backgroundColor: palette.dangerSoft },
  resultOutput: { color: palette.text, fontFamily: 'monospace', fontSize: 11, lineHeight: 17 },
});
