import { useRef, useState } from 'react';
import { Button, Text, View } from 'react-native';
import {
  {{MODULE_BASE}}View,
  echo,
  type {{MODULE_BASE}}ViewRef,
} from '{{NPM_NAME}}';

export default function App() {
  const viewRef = useRef<{{MODULE_BASE}}ViewRef>(null);
  const [value, setValue] = useState(1);

  return (
    <View style={{ flex: 1, gap: 12, justifyContent: 'center', padding: 24 }}>
      <Text>{echo('Hello from {{MODULE_NAME}}')}</Text>
      <{{MODULE_BASE}}View
        label="ArkTS Expo View"
        onValueChanged={(event) => setValue(event.nativeEvent.value)}
        ref={viewRef}
        style={{ height: 64 }}
        value={value}
      />
      <Button
        title="Increment through the async view ref"
        onPress={() => void viewRef.current?.increment(1)}
      />
    </View>
  );
}
