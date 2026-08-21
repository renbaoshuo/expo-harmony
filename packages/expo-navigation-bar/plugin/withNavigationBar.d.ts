import type { ConfigPlugin } from '@expo/config-plugins';

export type NavigationBarPluginProps = {
  backgroundColor?: string | null;
  barStyle?: 'light' | 'dark' | null;
  behavior?: 'overlay-swipe' | 'inset-swipe' | 'inset-touch';
  borderColor?: string;
  enforceContrast?: boolean;
  position?: 'relative' | 'absolute';
  visibility?: 'visible' | 'hidden';
};

declare const withNavigationBar: ConfigPlugin<NavigationBarPluginProps | void>;
export default withNavigationBar;
