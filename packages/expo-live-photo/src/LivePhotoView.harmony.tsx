import { requireNativeViewManager, requireOptionalNativeModule, UnavailabilityError } from 'expo-modules-core';
import { useImperativeHandle, useRef } from 'react';
import type { NativeSyntheticEvent } from 'react-native';
import type {
  LivePhotoLoadError,
  LivePhotoViewProps,
  LivePhotoViewStatics,
  LivePhotoViewType,
  PlaybackStyle,
} from 'expo-live-photo';

const module = requireOptionalNativeModule<{ isAvailable(): boolean }>('ExpoLivePhoto');
const isAvailable = (): boolean => module?.isAvailable() ?? false;
type NativeProps = Omit<LivePhotoViewProps, 'onLoadError'> & {
  ref: React.Ref<LivePhotoViewType | null>;
  onLoadError: (event: NativeSyntheticEvent<LivePhotoLoadError>) => void;
};
const NativeView = isAvailable() ? requireNativeViewManager<NativeProps>('ExpoLivePhoto') : null;

function LivePhotoView({ ref, ...props }: LivePhotoViewProps & { ref?: React.Ref<LivePhotoViewType> }) {
  const view = useRef<LivePhotoViewType | null>(null);

  useImperativeHandle(ref, () => ({
    startPlayback: (style?: PlaybackStyle) => {
      if (!isAvailable()) throw new UnavailabilityError('expo-live-photo', 'startPlayback');

      view.current?.startPlayback(style ?? 'full');
    },
    stopPlayback: () => {
      if (!isAvailable()) throw new UnavailabilityError('expo-live-photo', 'stopPlayback');

      view.current?.stopPlayback();
    },
  }), []);

  if (!NativeView) {
    console.warn('expo-live-photo is not available on this HarmonyOS device');
    return null;
  }

  return <NativeView {...props} ref={view} onLoadError={event => props.onLoadError?.(event.nativeEvent)} />;
}

const component = LivePhotoView as typeof LivePhotoView & LivePhotoViewStatics;
component.isAvailable = isAvailable;
export default component;
