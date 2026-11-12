/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext } from '@expo-harmony/expo-modules-core';
import { contact } from '@kit.ContactsKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { ContactsPermissions } from './ContactsPermissions';
import { ExpoContactsError } from './ContactsError';
import { cachePortrait, readBase64, writeCacheFile } from './ContactsFiles';
import { serializeVCard } from './ContactsVCard';
import { ContactQuery, ContactResponse, ExpoContactRecord, ExpoContainerRecord, ExpoGroupRecord, RequestedFields } from './ContactsRecords';
import {
  contactIdentifier,
  groupIdentifier,
  hasConcreteField,
  hasGroup,
  holderIdentifier,
  mapContact,
  mergeExpoContact,
  nativeContactFromExpo,
  nativeDisplayName,
  sortNativeContacts,
} from './ContactsMapper';
import { optionalInputString, optionalStringOrStringList, requireString } from './ContactsValidation';

export const CONTACT_PORTRAIT_API: number = 22;
export const CONTACTS_DATA_CAPABILITY: string = 'SystemCapability.Applications.ContactsData';
const CONTACT_COUNT_API: number = 22;
const CONTACT_QUERY_PARAMETER_ERROR: number = 401;

export function pageNextContacts(values: contact.Contact[], query: ContactQuery): contact.Contact[] {
  if (query.emptyPage) return [];
  return values.slice(query.pageOffset, query.pageSize === 0 ? undefined : query.pageOffset + query.pageSize);
}

export class ContactsRepository {
  private readonly context: ExpoModuleContext;
  private readonly permissions: ContactsPermissions;
  private writes: Promise<void> = Promise.resolve();

  constructor(context: ExpoModuleContext, permissions: ContactsPermissions) {
    this.context = context;
    this.permissions = permissions;
  }

  async mutate<Result>(operation: () => Promise<Result>): Promise<Result> {
    this.context.assertActive();

    const result = this.writes.then(async (): Promise<Result> => {
      this.context.assertActive();
      this.permissions.ensureWrite();

      const value = await operation();
      this.context.assertActive();
      return value;
    });
    this.writes = result.then(
      (): void => {},
      (): void => {},
    );

    return await result;
  }

  async hasContacts(): Promise<boolean> {
    return await this.count() > 0;
  }

  ensureReadable(): void {
    this.context.assertActive();
    this.permissions.ensureRead();
  }

  async count(): Promise<number> {
    this.ensureReadable();

    const count = deviceInfo.sdkApiVersion >= CONTACT_COUNT_API
      ? await contact.queryContactsCount(this.context.uiAbilityContext)
      : (await contact.queryContacts(this.context.uiAbilityContext)).length;
    this.ensureReadable();
    return count;
  }

  async select(query: ContactQuery): Promise<contact.Contact[]> {
    this.ensureReadable();

    if (query.emptyPage || query.ids?.length === 0) return [];

    if (query.ids?.length === 1) {
      const entry = await this.findContact(query.ids[0]);
      return entry === undefined ? [] : [entry];
    }

    let holder: contact.Holder | undefined;
    if (query.ids === undefined && (query.name === undefined || query.matchPhoneticName) && query.containerId !== undefined && query.groupId === undefined) {
      holder = await this.findHolder(query.containerId);
      if (holder === undefined) return [];
    }

    // Attribute filtering drops contacts with no matching data rows; project fields locally.
    // The N-API parser distinguishes omitted arguments from undefined.
    let values =
      holder === undefined
        ? await contact.queryContacts(this.context.uiAbilityContext)
        : await contact.queryContacts(this.context.uiAbilityContext, holder);
    this.ensureReadable();

    if (query.ids !== undefined) {
      const ids = query.ids;
      values = values.filter((entry: contact.Contact): boolean => ids.includes(contactIdentifier(entry)));
    } else if (query.name !== undefined && !query.matchPhoneticName) {
      const needle = query.name.toLocaleLowerCase();
      values = values.filter((entry: contact.Contact): boolean => nativeDisplayName(entry).toLocaleLowerCase().includes(needle));
    } else if (query.groupId !== undefined) {
      const group = query.groupId;
      values = values.filter((entry: contact.Contact): boolean => hasGroup(entry, group));
    }

    if (query.name !== undefined && query.matchPhoneticName) {
      const needle = query.name.toLocaleLowerCase();
      values = values.filter((entry: contact.Contact): boolean => {
        const phonetic = [entry.name?.givenNamePhonetic, entry.name?.middleNamePhonetic, entry.name?.familyNamePhonetic]
          .filter((part: string | undefined): boolean => part !== undefined && part.length > 0)
          .join(' ');
        return nativeDisplayName(entry).toLocaleLowerCase().includes(needle) || phonetic.toLocaleLowerCase().includes(needle);
      });
    }

    sortNativeContacts(values, query.sort);
    return values;
  }

  async getContacts(query: ContactQuery): Promise<ContactResponse> {
    const values = await this.select(query);

    const end = query.pageSize === 0 ? values.length : query.pageOffset + query.pageSize;
    const page = values.slice(query.pageOffset, end);

    const data: ExpoContactRecord[] = [];
    this.ensureReadable();

    for (const entry of page) {
      data.push(await this.serialize(entry, new RequestedFields(query.fields)));
      this.ensureReadable();
    }

    return new ContactResponse(data, end < values.length, query.pageOffset > 0);
  }

  async serialize(entry: contact.Contact, fields: RequestedFields): Promise<ExpoContactRecord> {
    const result = mapContact(entry, fields);
    if (fields.has('image') && entry.portrait?.uri && deviceInfo.sdkApiVersion >= CONTACT_PORTRAIT_API) {
      result.image = await cachePortrait(this.context, entry.portrait.uri);
    }

    return result;
  }

  async findContact(id: string): Promise<contact.Contact | undefined> {
    this.ensureReadable();

    const numericId = Number(id);
    if (!Number.isSafeInteger(numericId) || numericId < 0 || String(numericId) !== id) return undefined;

    const context = this.context.uiAbilityContext;

    try {
      const key = await contact.queryKey(context, numericId);
      this.ensureReadable();

      if (key) {
        const entry = await contact.queryContact(context, key);
        this.ensureReadable();
        if (entry?.id === numericId) return entry;
      }
    } catch (error) {
      // Contacts Kit can report missing or stale IDs as a generic parameter error.
      if ((error as BusinessError).code !== CONTACT_QUERY_PARAMETER_ERROR) throw error as Error;
    }

    this.ensureReadable();

    const entries = await contact.queryContacts(context);
    this.ensureReadable();
    return entries.find((entry: contact.Contact): boolean => entry.id === numericId);
  }

  async requireContact(id: string): Promise<contact.Contact> {
    this.context.assertActive();

    const entry = await this.findContact(id);
    this.context.assertActive();
    if (entry === undefined) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', `No contact exists for identifier '${id}'.`);

    return entry;
  }

  async add(record: Record<string, ESObject>, container?: string | null): Promise<string> {
    validateWritableContact(record);
    if (container !== undefined && container !== null) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS cannot create a contact in a specified container.');
    }

    return await this.mutate(async (): Promise<string> => {
      const entry = nativeContactFromExpo(record);
      if (entry.portrait?.uri) this.context.fileSourceForRead(entry.portrait.uri);

      const id = await contact.addContact(this.context.uiAbilityContext, entry);
      if (!Number.isSafeInteger(id) || id < 0) throw new ExpoContactsError('ERR_CONTACTS_ADD', 'HarmonyOS did not return a valid contact ID.');

      return String(id);
    });
  }

  async update(record: Record<string, ESObject>): Promise<string> {
    validateWritableContact(record);
    const id = requireString(record['id'], 'contact.id');

    const attributes = updateAttributes(record);

    return await this.mutate(async (): Promise<string> => {
      const entry = await this.requireContact(id);
      if (attributes.attributes.length === 0) return id;

      mergeExpoContact(entry, record);

      await this.save(entry, attributes);

      return id;
    });
  }

  async save(entry: contact.Contact, attributes: contact.ContactAttributes): Promise<void> {
    this.context.assertActive();
    if (attributes.attributes.length === 0) return;

    this.permissions.ensureWrite();

    if (attributes.attributes.includes(contact.Attribute.ATTR_PORTRAIT) && entry.portrait?.uri) {
      this.context.fileSourceForRead(entry.portrait.uri);
    }

    if (attributes.attributes.includes(contact.Attribute.ATTR_CONTACT_EVENT)) {
      // ContactsData drops ATTR_CONTACT_EVENT (0); keep the rest of the native
      // record intact when the full contact has to be written.
      await contact.updateContact(this.context.uiAbilityContext, entry);
    } else {
      await contact.updateContact(this.context.uiAbilityContext, entry, attributes);
    }
    this.context.assertActive();
  }

  async remove(id: string): Promise<void> {
    await this.mutate(async (): Promise<void> => {
      const entry = await this.findContact(id);
      if (entry === undefined) return;

      this.permissions.ensureWrite();

      await contact.deleteContact(this.context.uiAbilityContext, requireString(entry.key, 'contact.key'));
    });
  }

  async writeVCard(query: ContactQuery): Promise<string | undefined> {
    const values = await this.select(query);
    this.ensureReadable();

    const end = query.pageSize === 0 ? values.length : query.pageOffset + query.pageSize;
    const page = values.slice(query.pageOffset, end);
    if (page.length === 0) return undefined;

    const records: ExpoContactRecord[] = [];
    const photos: string[] = [];
    for (const entry of page) {
      const record = await this.serialize(entry, new RequestedFields());
      records.push(record);
      photos.push(record.image?.uri ? await readBase64(this.context, record.image.uri) : '');
      this.ensureReadable();
    }

    const bytes = new util.TextEncoder().encodeInto(serializeVCard(records, photos));

    return await writeCacheFile(this.context, 'vcf', bytes.buffer as ArrayBuffer, (): void => this.ensureReadable());
  }

  private async findHolder(id: string): Promise<contact.Holder | undefined> {
    const holders = await contact.queryHolders(this.context.uiAbilityContext);
    this.ensureReadable();
    return holders.find((holder: contact.Holder): boolean => holderIdentifier(holder) === id);
  }

  async getGroups(query?: Record<string, ESObject> | null): Promise<ExpoGroupRecord[]> {
    this.ensureReadable();

    const container = optionalInputString(query?.['containerId'], 'groupQuery.containerId');
    const id = optionalInputString(query?.['groupId'], 'groupQuery.groupId');
    const name = optionalInputString(query?.['groupName'], 'groupQuery.groupName', true);

    let holder: contact.Holder | undefined;
    if (name === undefined && container !== undefined) {
      holder = await this.findHolder(container);
      if (holder === undefined) return [];
    }

    const groups =
      holder === undefined
        ? await contact.queryGroups(this.context.uiAbilityContext)
        : await contact.queryGroups(this.context.uiAbilityContext, holder);
    this.ensureReadable();

    return groups
      .filter((entry: contact.Group): boolean => {
        if (name !== undefined) return entry.title === name;
        return container !== undefined || id === undefined || groupIdentifier(entry) === id;
      })
      .map((entry: contact.Group): ExpoGroupRecord => {
        const result = new ExpoGroupRecord();
        result.id = groupIdentifier(entry);
        result.name = entry.title;

        return result;
      });
  }

  async getContainers(query?: Record<string, ESObject> | null): Promise<ExpoContainerRecord[]> {
    this.ensureReadable();

    const ids = optionalStringOrStringList(query?.['containerId'], 'containerQuery.containerId');
    const contactId = optionalInputString(query?.['contactId'], 'containerQuery.contactId');
    const groupId = optionalInputString(query?.['groupId'], 'containerQuery.groupId');

    const holders = await contact.queryHolders(this.context.uiAbilityContext);
    this.ensureReadable();

    const result: ExpoContainerRecord[] = [];
    for (const holder of holders) {
      if (contactId !== undefined) {
        const entries = await contact.queryContacts(this.context.uiAbilityContext, holder);
        this.ensureReadable();
        if (!entries.some((entry: contact.Contact): boolean => contactIdentifier(entry) === contactId)) continue;
      } else if (groupId !== undefined) {
        const groups = await contact.queryGroups(this.context.uiAbilityContext, holder);
        this.ensureReadable();
        if (!groups.some((group: contact.Group): boolean => groupIdentifier(group) === groupId)) continue;
      } else if (ids !== undefined && !ids.includes(holderIdentifier(holder))) continue;

      result.push(new ExpoContainerRecord(holderIdentifier(holder), holder.displayName || holder.bundleName));
    }

    return result;
  }

  async changeGroupMembership(id: string, groupId: string, add: boolean): Promise<void> {
    await this.mutate(async (): Promise<void> => {
      const entry = await this.requireContact(id);
      const groups = await contact.queryGroups(this.context.uiAbilityContext);
      this.ensureReadable();

      const group = groups.find((item: contact.Group): boolean => groupIdentifier(item) === groupId);
      if (group === undefined) throw new ExpoContactsError('ERR_CONTACTS_GROUP_NOT_FOUND', `No contact group exists for identifier '${groupId}'.`);

      const holders = await this.getContainers({ 'contactId': id });
      const containers = await this.getContainers({ 'groupId': groupId });
      if (!holders.some((holder: ExpoContainerRecord): boolean => containers.some((other: ExpoContainerRecord): boolean => holder.id === other.id))) {
        throw new ExpoContactsError('ERR_CONTACTS_GROUP_CONTAINER_MISMATCH', 'The contact and group must belong to the same HarmonyOS holder.');
      }

      const members = entry.groups ?? [];
      const included = members.some((item: contact.Group): boolean => groupIdentifier(item) === groupId);
      if (included === add) return;

      if (add) members.push(group);
      entry.groups = add ? members : members.filter((item: contact.Group): boolean => groupIdentifier(item) !== groupId);

      await this.save(entry, { attributes: [contact.Attribute.ATTR_GROUP_MEMBERSHIP] });
    });
  }
}

export function validateWritableContact(record: Record<string, ESObject>): void {
  const unsupported = ['department', 'nonGregorianBirthday', 'socialProfiles', 'isFavorite', 'rawImage', 'extraNames'];
  for (const field of unsupported) {
    if (hasConcreteField(record, field)) throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS cannot write contact.${field}.`);
  }

  if (hasConcreteField(record, 'contactType') && record['contactType'] !== 'person') {
    throw new ExpoContactsError(
      'ERR_CONTACTS_UNSUPPORTED',
      'HarmonyOS does not expose the company contact type. Use the company field on a person contact.',
    );
  }

  if (hasConcreteField(record, 'image') && deviceInfo.sdkApiVersion < CONTACT_PORTRAIT_API) {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'Writing contact images requires HarmonyOS API 22 or later.');
  }
}

export function updateAttributes(record: Record<string, ESObject>): contact.ContactAttributes {
  const mapping: Record<string, contact.Attribute> = {
    'firstName': contact.Attribute.ATTR_NAME,
    'middleName': contact.Attribute.ATTR_NAME,
    'lastName': contact.Attribute.ATTR_NAME,
    'namePrefix': contact.Attribute.ATTR_NAME,
    'nameSuffix': contact.Attribute.ATTR_NAME,
    'phoneticFirstName': contact.Attribute.ATTR_NAME,
    'phoneticMiddleName': contact.Attribute.ATTR_NAME,
    'phoneticLastName': contact.Attribute.ATTR_NAME,
    'nickname': contact.Attribute.ATTR_NICKNAME,
    'company': contact.Attribute.ATTR_ORGANIZATION,
    'jobTitle': contact.Attribute.ATTR_ORGANIZATION,
    'birthday': contact.Attribute.ATTR_CONTACT_EVENT,
    'dates': contact.Attribute.ATTR_CONTACT_EVENT,
    'note': contact.Attribute.ATTR_NOTE,
    'emails': contact.Attribute.ATTR_EMAIL,
    'phoneNumbers': contact.Attribute.ATTR_PHONE,
    'addresses': contact.Attribute.ATTR_POSTAL_ADDRESS,
    'instantMessageAddresses': contact.Attribute.ATTR_IM,
    'urlAddresses': contact.Attribute.ATTR_WEBSITE,
    'relationships': contact.Attribute.ATTR_RELATION,
    'image': contact.Attribute.ATTR_PORTRAIT,
  };

  const attributes: contact.Attribute[] = [];
  for (const key of Object.keys(mapping)) {
    if (hasConcreteField(record, key) && !attributes.includes(mapping[key])) attributes.push(mapping[key]);
  }

  return { attributes };
}
