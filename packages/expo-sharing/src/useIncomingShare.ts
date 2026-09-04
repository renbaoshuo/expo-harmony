import { requireNativeModule } from 'expo-modules-core';
import type { EventSubscription } from 'expo-modules-core';
import {
  clearSharedPayloads,
  getResolvedSharedPayloadsAsync,
  getSharedPayloads,
} from 'expo-sharing';
import type {
  ResolvedSharePayload,
  SharePayload,
  UseIncomingShareResult,
} from 'expo-sharing';
import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

type SharingModule = {
  addListener(event: 'onSharedPayloadsChanged', listener: () => void): EventSubscription;
};

const native = requireNativeModule<SharingModule>('ExpoSharing');

function payloadKey(item: SharePayload): string {
  return JSON.stringify([item.value, item.mimeType ?? null, item.shareType]);
}

function equalPayloads(left: SharePayload[], right: SharePayload[]): boolean {
  if (left.length !== right.length) return false;

  const counts = new Map<string, number>();
  for (const item of left) {
    const key = payloadKey(item);
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  for (const item of right) {
    const key = payloadKey(item);
    const count = counts.get(key) ?? 0;
    if (count === 0) return false;
    counts.set(key, count - 1);
  }

  return true;
}

export function useIncomingShare(): UseIncomingShareResult {
  const [payloads, setPayloads] = useState<SharePayload[]>(getSharedPayloads());
  const [resolved, setResolved] = useState<ResolvedSharePayload[]>([]);
  const [resolving, setResolving] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const previous = useRef<SharePayload[]>([]);

  const refresh = useCallback(async (): Promise<void> => {
    try {
      const next = getSharedPayloads();
      if (equalPayloads(next, previous.current)) return;

      previous.current = next;
      setPayloads(next);
      setResolved([]);
      setError(null);
      if (next.length === 0) return;

      setResolving(true);
      try {
        setResolved(await getResolvedSharedPayloadsAsync());
      } catch (cause) {
        setError(cause instanceof Error ? cause : new Error('Unknown incoming share error.'));
      } finally {
        setResolving(false);
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause : new Error('Failed to read incoming share data.'));
    }
  }, []);

  const clear = useCallback((): void => {
    clearSharedPayloads();

    previous.current = [];
    setPayloads([]);
    setResolved([]);
    setError(null);
    setResolving(false);
  }, []);

  useEffect(() => {
    const subscription = native.addListener('onSharedPayloadsChanged', refresh);
    const activity = AppState.addEventListener('change', (state) => {
      if (state === 'active') void refresh();
    });

    void refresh();

    return () => {
      subscription.remove();
      activity.remove();
    };
  }, [refresh]);

  return {
    sharedPayloads: payloads,
    resolvedSharedPayloads: resolved,
    clearSharedPayloads: clear,
    isResolving: resolving,
    error,
    refreshSharePayloads: refresh,
  };
}
