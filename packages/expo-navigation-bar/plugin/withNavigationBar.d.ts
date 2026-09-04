import type { ConfigPlugin } from '@expo/config-plugins';

export type NavigationBarPluginProps = {
  backgroundColor?: string | null;
  barStyle?: 'light' | 'dark' | null;
  position?: 'relative' | 'absolute';
  visibility?: 'visible' | 'hidden';
};

declare const withNavigationBar: ConfigPlugin<NavigationBarPluginProps | void>;
export default withNavigationBar;
