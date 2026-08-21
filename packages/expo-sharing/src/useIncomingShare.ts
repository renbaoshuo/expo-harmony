import { requireNativeModule } from 'expo-modules-core';
import type { EventSubscription } from 'expo-modules-core';
import { useIncomingShare as useExpoIncomingShare } from 'expo-sharing-upstream';
import type { UseIncomingShareResult } from 'expo-sharing-upstream';
import { useCallback, useEffect } from 'react';

type SharingModule = {
  addListener(event: 'onSharedPayloadsChanged', listener: () => void): EventSubscription;
};

const native = requireNativeModule<SharingModule>('ExpoSharing');

export function useIncomingShare(): UseIncomingShareResult {
  const incoming = useExpoIncomingShare();

  const clearSharedPayloads = useCallback((): void => {
    incoming.clearSharedPayloads();
    incoming.refreshSharePayloads();
  }, [incoming.clearSharedPayloads, incoming.refreshSharePayloads]);

  useEffect(() => {
    const subscription = native.addListener('onSharedPayloadsChanged', incoming.refreshSharePayloads);
    incoming.refreshSharePayloads();

    return () => subscription.remove();
  }, [incoming.refreshSharePayloads]);

  return {
    ...incoming,
    clearSharedPayloads,
  };
}
