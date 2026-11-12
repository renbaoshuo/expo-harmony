/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ActionButton } from '../ui';

export function Cycle<T extends string | number>({
  label, value, choices, onChange, disabled,
}: {
  label: string;
  value: T;
  choices: readonly T[];
  onChange: (value: T) => void;
  disabled?: boolean;
}) {
  return (
    <ActionButton
      disabled={disabled}
      label={`${label} · ${value}`}
      onPress={() => {
        const next = choices[(choices.indexOf(value) + 1) % choices.length];
        if (next !== undefined) onChange(next);
      }}
      tone="secondary"
    />
  );
}

export function Toggle({
  label, value, onChange, disabled,
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <ActionButton
      disabled={disabled}
      label={`${label} · ${value ? '开' : '关'}`}
      onPress={() => onChange(!value)}
      tone={value ? 'primary' : 'secondary'}
    />
  );
}

export function optionalNumber(text: string, label: string): number | undefined {
  if (!text.trim()) return undefined;

  const value = Number(text);
  if (!Number.isFinite(value)) throw new Error(`${label}需要填写有效数字。`);

  return value;
}
