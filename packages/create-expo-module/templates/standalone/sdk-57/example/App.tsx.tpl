/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

{{APP_REACT_IMPORTS}}
import { {{APP_BUTTON_IMPORT}}Text, View } from 'react-native';
import nativeModule{{APP_IMPORTS}} from '{{NPM_NAME}}';
{{#SharedObject}}import { useReleasingSharedObject } from 'expo-modules-core';{{/SharedObject}}

export default function App() {
{{#View}}  const viewRef = useRef<{{MODULE_BASE}}ViewRef>(null);
{{/View}}{{#ViewEvent}}  const [value, setValue] = useState(1);
{{/ViewEvent}}{{#AsyncFunction}}  const [asyncResult, setAsyncResult] = useState('');
{{/AsyncFunction}}{{#Event}}  const [eventValue, setEventValue] = useState('No event yet');
  useEffect(() => {
    const subscription = nativeModule.addListener('onChange', event => setEventValue(event.value));
    return () => subscription.remove();
  }, []);
{{/Event}}{{#SharedObject}}  const counter = useReleasingSharedObject(() => new {{MODULE_BASE}}Counter(0), []);
  const [count, setCount] = useState(counter.value);
{{/SharedObject}}  return (
    <View style={{ flex: 1, gap: 12, justifyContent: 'center', padding: 24 }}>
      <Text>{{MODULE_NAME}}: {nativeModule ? 'Native module ready' : 'Unavailable'}</Text>
{{#Constant}}      <Text>{platform}</Text>
{{/Constant}}{{#Function}}      <Text>{echo('Hello from Harmony')}</Text>
{{/Function}}{{#AsyncFunction}}      <Text>{asyncResult}</Text>
      <Button title="Async function" onPress={async () => setAsyncResult(await echoAsync('Hello from ArkTS'))} />
{{/AsyncFunction}}{{#Event}}      <Text>{eventValue}</Text>
      <Button title="Send event" onPress={() => emitChange('Hello from ArkTS')} />
{{/Event}}{{#SharedObject}}      <Text>Counter: {count}</Text>
      <Button title="Increment shared counter" onPress={() => setCount(counter.increment(1))} />
{{/SharedObject}}{{#View}}      <{{MODULE_BASE}}View
        label="ArkTS Expo View"
{{#ViewEvent}}        onValueChanged={event => setValue(event.nativeEvent.value)}
{{/ViewEvent}}        ref={viewRef}
        style={{ height: 64 }}
        value={{{#ViewEvent}}value{{/ViewEvent}}{{^ViewEvent}}1{{/ViewEvent}}}
      />
      <Button title="Increment view" onPress={() => void viewRef.current?.increment(1)} />
{{/View}}    </View>
  );
}
