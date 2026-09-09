import type { ConfigPlugin } from '@expo/config-plugins';

declare const withHarmonyContacts: ConfigPlugin<{
  contactsPermission?: string;
  readContactsPermission?: string;
  writeContactsPermission?: string;
} | void>;

export = withHarmonyContacts;
