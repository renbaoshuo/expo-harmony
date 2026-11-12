/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

'use dom';

import { useState } from 'react';

type Props = {
  count: number;
  onChange: (value: number) => Promise<number>;
  dom?: import('expo/dom').DOMProps;
};

export default function DomCounter({ count, onChange }: Props) {
  const [result, setResult] = useState('');
  const [busy, setBusy] = useState(false);

  const increment = async () => {
    setBusy(true);

    try {
      setResult(String(await onChange(count + 1)));
    } catch (error) {
      setResult(error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main style={{ flex: 1, padding: 16, fontFamily: 'system-ui, sans-serif', color: '#111827', background: '#EAF3FF' }}>
      <style>{'body { margin: 0; } button:disabled { opacity: 0.5; }'}</style>
      <p>网页计数 <strong id="count">{count}</strong></p>
      <button
        disabled={busy}
        id="increment"
        onClick={() => void increment()}
        style={{ padding: '12px 16px', border: 0, borderRadius: 10, background: '#007AFF', color: '#FFFFFF', fontSize: 14 }}
        type="button"
      >
        {busy ? '等待原生返回…' : '网页端加一'}
      </button>
      {result ? <p aria-live="polite" id="result" style={{ marginBottom: 0, fontSize: 13 }}>{result}</p> : null}
    </main>
  );
}
