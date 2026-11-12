/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { CheckboxEvent, CheckboxProps } from 'expo-checkbox';
import {
  findNodeHandle,
  PlatformColor,
  Pressable,
  StyleSheet,
  View,
  type GestureResponderEvent,
  type NativeSyntheticEvent,
} from 'react-native';

export default function Checkbox({
  color,
  disabled = false,
  onChange,
  onValueChange,
  style,
  value = false,
  ...viewProps
}: CheckboxProps) {
  let tint = color;
  if (tint == null && disabled) {
    tint = value ? '#AAB8C2' : '#CCD6DD';
  } else if (tint == null && value) {
    tint = PlatformColor('ohos_id_color_emphasize') ?? '#009688';
  }

  function handlePress(event: GestureResponderEvent) {
    if (disabled) return;

    const next = !value;
    if (onChange) {
      // Fabric's host instance works with findNodeHandle, whose legacy types expect a View.
      const currentTarget = event.currentTarget;
      const changeEvent: NativeSyntheticEvent<CheckboxEvent> = {
        type: 'change',
        target: currentTarget,
        currentTarget,
        nativeEvent: { target: findNodeHandle(currentTarget as View), value: next },
        bubbles: event.bubbles,
        cancelable: event.cancelable,
        defaultPrevented: event.defaultPrevented,
        eventPhase: event.eventPhase,
        isTrusted: event.isTrusted,
        timeStamp: event.timeStamp,
        preventDefault() {
          event.preventDefault();
          changeEvent.defaultPrevented = event.defaultPrevented;
        },
        isDefaultPrevented: () => event.isDefaultPrevented(),
        stopPropagation: () => event.stopPropagation(),
        isPropagationStopped: () => event.isPropagationStopped(),
        persist: () => event.persist(),
      };
      onChange(changeEvent);
    }

    onValueChange?.(next);
  }

  return (
    <Pressable
      {...viewProps}
      accessibilityRole="checkbox"
      role="checkbox"
      aria-checked={value}
      disabled={disabled}
      onPress={handlePress}
      style={[
        styles.root,
        style,
        tint != null && { borderColor: tint },
        (value || disabled) && { backgroundColor: value ? tint : 'transparent' },
      ]}
    >
      {value && (
        <View importantForAccessibility="no" pointerEvents="none" style={styles.checkmark} />
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  root: {
    alignItems: 'center',
    justifyContent: 'center',
    height: 20,
    width: 20,
    borderRadius: 2,
    borderWidth: 2,
    borderColor: '#657786',
  },
  checkmark: {
    height: '75%',
    width: '40%',
    borderBottomWidth: 2,
    borderRightWidth: 2,
    borderColor: 'white',
    transform: [{ translateY: -1 }, { rotate: '45deg' }],
  },
});
