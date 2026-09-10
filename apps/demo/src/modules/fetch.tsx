import { fetch as expoFetch } from 'expo/fetch';
import { useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { ActionButton, ActionRow, Field, Note, Panel, ResultPanel, useAsyncResult } from '../ui';
import { json } from '../format';

function appendPreview(
  current: Uint8Array<ArrayBufferLike>,
  chunk: Uint8Array<ArrayBufferLike>,
  limit = 2048
): Uint8Array<ArrayBufferLike> {
  if (current.length >= limit) return current;
  const addition = chunk.subarray(0, limit - current.length);
  const result = new Uint8Array(current.length + addition.length);
  result.set(current);
  result.set(addition, current.length);
  return result;
}

export function FetchDemo() {
  const action = useAsyncResult();
  const [method, setMethod] = useState<'GET' | 'POST'>('GET');
  const [url, setUrl] = useState('https://example.com');
  const controller = useRef<AbortController | null>(null);
  const isRunning = action.state.phase === 'running';

  useEffect(() => () => controller.current?.abort(), []);

  const request = () => action.run(async () => {
    const requestController = new AbortController();
    controller.current = requestController;
    try {
      const response = await expoFetch(url.trim(), {
        body: method === 'POST' ? JSON.stringify({ source: 'expo-harmony-demo' }) : undefined,
        credentials: 'include',
        headers: method === 'POST' ? { 'content-type': 'application/json' } : undefined,
        method,
        redirect: 'follow',
        signal: requestController.signal,
      });
      let bytes = 0;
      let chunks = 0;
      let preview: Uint8Array<ArrayBufferLike> = new Uint8Array();
      if (response.body) {
        const reader = response.body.getReader();
        while (true) {
          const item = await reader.read();
          if (item.done) break;
          chunks += 1;
          bytes += item.value.length;
          preview = appendPreview(preview, item.value);
        }
      }
      return json({
        bodyPreview: new TextDecoder().decode(preview),
        bytes,
        chunks,
        headers: Object.fromEntries([...response.headers.entries()].slice(0, 16)),
        redirected: response.redirected,
        status: response.status,
        url: response.url,
      });
    } finally {
      if (controller.current === requestController) controller.current = null;
    }
  });

  const requestHint = useMemo(
    () => method === 'GET'
      ? '可使用任意 HTTP(S) 地址。重定向、Set-Cookie 与分块响应体都会体现在结果中。'
      : 'POST 会发送一个较小的 JSON 请求体，并保持重定向与凭据处理开启。',
    [method]
  );

  return (
    <Panel eyebrow="网络试验场" title="流式读取 HTTP 响应">
      <Field label="请求 URL" onChangeText={setUrl} value={url} />
      <View style={styles.methodRow}>
        {(['GET', 'POST'] as const).map(value => (
          <ActionButton
            key={value}
            disabled={isRunning}
            label={value}
            onPress={() => setMethod(value)}
            tone={method === value ? 'primary' : 'secondary'}
          />
        ))}
      </View>
      <Note>{requestHint}</Note>
      <ActionRow>
        <ActionButton disabled={isRunning || !url.trim()} label="发送请求" onPress={() => void request()} />
        <ActionButton
          disabled={!isRunning}
          label="中止"
          onPress={() => controller.current?.abort()}
          tone="danger"
        />
      </ActionRow>
      <ResultPanel state={action.state} />
    </Panel>
  );
}

const styles = StyleSheet.create({
  methodRow: { flexDirection: 'row', gap: 10 },
});
