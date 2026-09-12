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

export function useIncomingShare(): UseIncomingShareResult {
  const [payloads, setPayloads] = useState<SharePayload[]>([]);
  const [resolved, setResolved] = useState<ResolvedSharePayload[]>([]);
  const [resolving, setResolving] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const revision = useRef(0);

  const refresh = useCallback(async (): Promise<void> => {
    const current = ++revision.current;

    setError(null);
    setResolving(true);
    try {
      setPayloads(getSharedPayloads());
      setResolved([]);

      const next = await getResolvedSharedPayloadsAsync();
      if (current !== revision.current) return;

      setPayloads(getSharedPayloads());
      setResolved(next);
    } catch (cause) {
      if (current === revision.current) {
        setError(cause instanceof Error ? cause : new Error('Failed to resolve incoming share data.'));
      }
    } finally {
      if (current === revision.current) setResolving(false);
    }
  }, []);

  const clear = useCallback((): void => {
    clearSharedPayloads();

    revision.current += 1;
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
      revision.current += 1;
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
