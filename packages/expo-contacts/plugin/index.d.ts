export type ContactsPluginOptions = {
  contactsPermission?: string;
  readContactsPermission?: string;
  writeContactsPermission?: string;
};

export default function contacts(props?: ContactsPluginOptions): [string, ContactsPluginOptions];
