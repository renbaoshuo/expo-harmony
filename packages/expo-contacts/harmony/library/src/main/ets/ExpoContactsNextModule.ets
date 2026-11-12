import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoPermissionStatus, ExpoSharedObject, ExpoSharedObjectClassDefinition, ExpoValueType, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { contact } from '@kit.ContactsKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { ContactsPermissions, ContactsPermissionResponse } from './ContactsPermissions';
import { ContactsRepository, CONTACTS_DATA_CAPABILITY, CONTACT_PORTRAIT_API, pageNextContacts, updateAttributes, validateWritableContact } from './ContactsRepository';
import { RequestedFields } from './ContactsRecords';
import { contactIdentifier, isBirthdayEvent, mapContact, mergeExpoContact } from './ContactsMapper';
import { ExpoContactsError } from './ContactsError';
import { ExpoContactsModule } from './ExpoContactsModule';
import { ExpoContactsService } from './ExpoContactsService';
import { cachePortrait } from './ContactsFiles';
import { nextQuery, requireRecord, requireString } from './ContactsValidation';
import { addedNextRowId, assignNativeNextRows, legacyNextInput, legacyNextScalars, locateNextRow, nativeNextRows, newNativeNextRow, nextDate, NEXT_LISTS, NEXT_STRINGS, NextListField, nextRows, patchNativeNextRow, UNSUPPORTED_NEXT } from './ContactsNextMapper';
import { NextGroupClasses } from './ContactsNextGroups';

const NEXT_RECORD = ExpoValueTypes.custom<Record<string, ESObject>>(
  'contact record',
  (value: ESObject): Record<string, ESObject> => requireRecord(value, 'contact record'),
  (value: Record<string, ESObject>): ESObject => value,
);
const NEXT_OPTIONS = NEXT_RECORD.nullable().optional();
const NEXT_VALUE: ExpoValueType<ESObject> = ExpoValueTypes.custom<ESObject>('contact value', (value: ESObject): ESObject => value, (value: ESObject): ESObject => value);
const NEXT_FIELDS = ExpoValueTypes.array(ExpoValueTypes.string()).nullable().optional();
const THUMBNAIL_MAX_DIMENSION: number = 256;
const NEXT_READ_ONLY: string[] = ['id', 'fullName', 'thumbnail'];
const DEFAULT_DETAIL_FIELDS: string[] = Object.keys(NEXT_STRINGS)
  .concat(NEXT_LISTS.map((field: NextListField): string => field.field), ['fullName', 'image', 'thumbnail', 'birthday']);
type FieldMutation = 'add' | 'update' | 'delete';

function validateNextKeys(input: Record<string, ESObject>): void {
  const allowed = Object.keys(NEXT_STRINGS).concat(NEXT_LISTS.map((field: NextListField): string => field.field), UNSUPPORTED_NEXT, NEXT_READ_ONLY, ['birthday', 'image']);
  for (const key of Object.keys(input)) {
    if (!allowed.includes(key)) throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `Unknown contact field '${key}'.`);
  }
}

function detailFields(fields?: string[] | null): string[] {
  if (fields === undefined || fields === null) return DEFAULT_DETAIL_FIELDS;
  return fields.filter((field: string): boolean => {
    if (UNSUPPORTED_NEXT.includes(field)) return false;
    if (!DEFAULT_DETAIL_FIELDS.includes(field)) throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `Unknown contact field '${field}'.`);
    return true;
  });
}

async function readDetails(context: ExpoModuleContext, entry: contact.Contact, fields: string[]): Promise<Record<string, ESObject>> {
  const legacyFields = ['birthday', 'note'].filter((field: string): boolean => fields.includes(field));
  const legacy = mapContact(entry, new RequestedFields(legacyFields));
  const scalars = legacy as ESObject as Record<string, ESObject>;
  const result: Record<string, ESObject> = { 'id': legacy.id };
  for (const key of fields) {
    if (Object.keys(NEXT_STRINGS).includes(key)) result[key] = scalars[NEXT_STRINGS[key]] ?? null;
    else if (key === 'fullName') result[key] = legacy.name;
    else if (key === 'birthday') result[key] = legacy.birthday === undefined ? null : nextDate(legacy.birthday);
    else if (key === 'image' || key === 'thumbnail') {
      result[key] = entry.portrait?.uri && deviceInfo.sdkApiVersion >= CONTACT_PORTRAIT_API
        ? (await cachePortrait(context, entry.portrait.uri, key === 'thumbnail' ? THUMBNAIL_MAX_DIMENSION : undefined)).uri ?? null
        : null;
    } else {
      const field = NEXT_LISTS.find((item: NextListField): boolean => item.field === key);
      if (field !== undefined) result[key] = await nextRows(entry, field);
    }
  }
  context.assertActive();
  return result;
}

export class NextContactObject extends ExpoSharedObject {
  readonly id: string;
  private readonly repository: ContactsRepository;
  private pickerEntry?: contact.Contact;
  private deleted: boolean = false;

  constructor(context: ExpoModuleContext, repository: ContactsRepository, id: string, pickerEntry?: contact.Contact) {
    super(context);
    this.repository = repository;
    this.id = requireString(id, 'contact.id');
    this.pickerEntry = pickerEntry;
  }

  async getEntry(): Promise<contact.Contact> {
    this.context.assertActive();
    if (this.deleted) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', 'This contact has been deleted.');

    const snapshot = this.pickerEntry;
    if (snapshot === undefined) return await this.repository.requireContact(this.id);
    if (!canIUse(CONTACTS_DATA_CAPABILITY) || this.context.permissionStatus('ohos.permission.READ_CONTACTS') !== ExpoPermissionStatus.GRANTED) return snapshot;

    try {
      return await this.repository.findContact(this.id) ?? snapshot;
    } catch (error) {
      if (error instanceof ExpoContactsError && error.code === 'ERR_CONTACTS_MISSING_PERMISSION') return snapshot;
      if ((error as BusinessError).code === 201) return snapshot;
      throw error as Error;
    }
  }

  async details(fields?: string[] | null): Promise<Record<string, ESObject>> {
    const requested = detailFields(fields);
    const entry = await this.getEntry();
    const details = await readDetails(this.context, entry, requested);
    const snapshot = this.pickerEntry;
    if (entry === snapshot) return details;

    try {
      this.repository.ensureReadable();
      return details;
    } catch (error) {
      if (snapshot !== undefined && error instanceof ExpoContactsError && error.code === 'ERR_CONTACTS_MISSING_PERMISSION') {
        return await readDetails(this.context, snapshot, requested);
      }
      throw error as Error;
    }
  }

  async patch(input: Record<string, ESObject>, replace: boolean = false): Promise<void> {
    this.context.assertActive();
    if (this.deleted) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', 'This contact has been deleted.');
    validateNextKeys(input);

    await this.repository.mutate(async (): Promise<void> => {
      const entry = await this.repository.requireContact(this.id);
      const legacy = legacyNextScalars(input, replace);
      validateWritableContact(legacy);
      if ((input['image'] === null || (replace && input['image'] === undefined)) && entry.portrait?.uri) {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose removing contact images.');
      }

      const attributes = updateAttributes(legacy);
      for (const field of NEXT_LISTS) {
        const values: ESObject = input[field.field];
        if (values === undefined && !replace) continue;
        if (values !== null && values !== undefined && !Array.isArray(values)) throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `contact.${field.field} must be an array or null.`);

        const records: ESObject[] = (values ?? []) as ESObject[];
        const existing = !replace && records.length > 0 ? await nextRows(entry, field) : [];
        const before: ESObject[] = nativeNextRows(entry, field);
        const rows: ESObject[] = [];
        const ids = new Set<string>();

        for (let index = 0; index < records.length; index++) {
          const record = requireRecord(records[index], field.field);
          if (replace || record['id'] === undefined) {
            rows.push(newNativeNextRow(field, record));
            continue;
          }
          const identifier = requireString(record['id'], 'field.id');
          const offset = existing.findIndex((item: Record<string, ESObject>): boolean => item['id'] === identifier);
          const previous = existing[offset];
          if (previous === undefined) throw new ExpoContactsError('ERR_CONTACTS_STALE_FIELD', 'The field identifier is stale or belongs to another contact. Read the list again before modifying it.');
          if (ids.has(identifier)) throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', 'A contact list cannot contain the same existing field identifier more than once.');

          ids.add(identifier);
          const row: Record<string, ESObject> = {};
          for (const key of Object.keys(previous)) row[key] = previous[key];
          for (const key of Object.keys(record)) if (record[key] !== undefined) row[key] = record[key];
          rows.push(patchNativeNextRow(field, before[offset], row, record));
        }

        assignNativeNextRows(entry, field, rows);
        if (!attributes.attributes.includes(field.attribute)) attributes.attributes.push(field.attribute);
      }

      if (input['birthday'] === null) {
        entry.events = (entry.events ?? []).filter((event: contact.Event): boolean => !isBirthdayEvent(event));
        if (!attributes.attributes.includes(contact.Attribute.ATTR_CONTACT_EVENT)) attributes.attributes.push(contact.Attribute.ATTR_CONTACT_EVENT);
      }
      mergeExpoContact(entry, legacy);

      await this.repository.save(entry, attributes);
      this.pickerEntry = undefined;
    });
  }

  async delete(): Promise<void> {
    this.context.assertActive();
    if (this.deleted) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', 'This contact has been deleted.');

    await this.repository.remove(this.id);
    this.pickerEntry = undefined;
    this.deleted = true;
  }

  async changeRow(field: NextListField, input: Record<string, ESObject>, operation: FieldMutation): Promise<string | undefined> {
    this.context.assertActive();
    if (this.deleted) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', 'This contact has been deleted.');
    return await this.repository.mutate(async (): Promise<string | undefined> => {
      const entry = await this.repository.requireContact(this.id);

      const before: ESObject[] = nativeNextRows(entry, field);
      const rows: ESObject[] = before.slice();
      const index = operation === 'add' ? rows.length : await locateNextRow(entry, field, requireString(input['id'], 'field.id'));
      if (operation === 'delete') rows.splice(index, 1);
      else {
        const value: ESObject = newNativeNextRow(field, input);
        if (operation === 'add') rows.push(value);
        else rows[index] = value;
      }

      assignNativeNextRows(entry, field, rows);

      await this.repository.save(entry, { attributes: [field.attribute] });
      this.pickerEntry = undefined;

      if (operation !== 'add') return undefined;

      const refreshed = await this.repository.requireContact(this.id);
      return await addedNextRowId(refreshed, field, before, rows[index]);
    });
  }
}

export class ExpoContactsNextModule extends ExpoModule {
  private readonly repository: ContactsRepository;
  private readonly permissions: ContactsPermissions;
  private readonly ui: ExpoContactsModule;

  constructor(context: ExpoModuleContext) {
    super(context);
    const service = context.services.require(ExpoContactsService.key);
    this.repository = service.getRepository(context);
    this.permissions = service.getPermissions(context);
    this.ui = new ExpoContactsModule(context);
  }

  definition(): ExpoModuleDefinition {
    const contacts = new ExpoSharedObjectClassDefinition<NextContactObject>('Contact');
    const contactType = contacts.valueType();
    const makeContact = (entry: contact.Contact): NextContactObject => contacts.instance(new NextContactObject(this.context, this.repository, contactIdentifier(entry)));
    contacts
      .construct(ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (context: ExpoModuleContext, id: string): NextContactObject => new NextContactObject(context, this.repository, id)))
      .property('id', (value: NextContactObject): string => value.id)
      .asyncFunction('getDetails', ExpoFunction.ownedTyped1(NEXT_FIELDS, async (value: NextContactObject, fields?: string[] | null): Promise<Record<string, ESObject>> => await value.details(fields)))
      .asyncFunction('patch', ExpoFunction.ownedTyped1(NEXT_RECORD, async (value: NextContactObject, input: Record<string, ESObject>): Promise<void> => await value.patch(input)))
      .asyncFunction('update', ExpoFunction.ownedTyped1(NEXT_RECORD, async (value: NextContactObject, input: Record<string, ESObject>): Promise<void> => await value.patch(input, true)))
      .asyncFunction('delete', ExpoFunction.ownedTyped0(async (value: NextContactObject): Promise<void> => await value.delete()))
      .asyncFunction('getFullName', ExpoFunction.ownedTyped0(async (value: NextContactObject): Promise<string> => (await value.details(['fullName']))['fullName'] as string))
      .asyncFunction('editWithForm', ExpoFunction.ownedTyped1(NEXT_OPTIONS, async (_value: NextContactObject, _options?: Record<string, ESObject> | null): Promise<boolean> => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose a system edit form for an existing contact.');
      }))
      .staticAsyncFunction('getAll', ExpoFunction.ownedTyped1(NEXT_OPTIONS, async (_context: ExpoModuleContext, options?: Record<string, ESObject> | null): Promise<NextContactObject[]> => {
        const query = nextQuery(options);
        return pageNextContacts(await this.repository.select(query), query).map(makeContact);
      }).returns(ExpoValueTypes.array(contactType)))
      .staticAsyncFunction('getAllDetails', ExpoFunction.ownedTyped2(ExpoValueTypes.array(ExpoValueTypes.string()), NEXT_OPTIONS, async (_context: ExpoModuleContext, fields: string[], options?: Record<string, ESObject> | null): Promise<Record<string, ESObject>[]> => {
        const requested = detailFields(fields);
        const query = nextQuery(options);
        const entries = pageNextContacts(await this.repository.select(query), query);
        const results: Record<string, ESObject>[] = [];
        this.repository.ensureReadable();

        for (const entry of entries) {
          results.push(await readDetails(this.context, entry, requested));
          this.repository.ensureReadable();
        }

        return results;
      }))
      .staticAsyncFunction('create', ExpoFunction.ownedTyped1(NEXT_RECORD, async (_context: ExpoModuleContext, input: Record<string, ESObject>): Promise<NextContactObject> => {
        validateNextKeys(input);
        const id = await this.repository.add(legacyNextInput(input));
        return contacts.instance(new NextContactObject(this.context, this.repository, id));
      }).returns(contactType))
      .staticAsyncFunction('getCount', ExpoFunction.ownedTyped0(async (_context: ExpoModuleContext): Promise<number> => await this.repository.count()))
      .staticAsyncFunction('hasAny', ExpoFunction.ownedTyped0(async (_context: ExpoModuleContext): Promise<boolean> => await this.repository.hasContacts()))
      .staticAsyncFunction('presentCreateForm', ExpoFunction.ownedTyped2(NEXT_OPTIONS, NEXT_OPTIONS, async (_context: ExpoModuleContext, input?: Record<string, ESObject> | null, options?: Record<string, ESObject> | null): Promise<boolean> => {
        validateNextKeys(input ?? {});
        return await this.ui.presentForm(undefined, legacyNextInput(input ?? {}), options);
      }))
      .staticAsyncFunction('presentPicker', ExpoFunction.ownedTyped0(async (_context: ExpoModuleContext): Promise<NextContactObject | null> => {
        const selected = await this.ui.presentNativePicker();
        return selected === null ? null : contacts.instance(new NextContactObject(this.context, this.repository, contactIdentifier(selected), selected));
      }).returns(contactType.nullable()))
      .staticAsyncFunction('presentAccessPicker', ExpoFunction.ownedTyped0(async (_context: ExpoModuleContext): Promise<NextContactObject[]> => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose limited contact access.');
      }).returns(ExpoValueTypes.array(contactType)));

    for (const key of Object.keys(NEXT_STRINGS).concat(['birthday', 'image', 'thumbnail'])) {
      const suffix = key.charAt(0).toUpperCase() + key.slice(1);
      contacts.asyncFunction(`get${suffix}`, ExpoFunction.ownedTyped0(async (value: NextContactObject): Promise<ESObject> => (await value.details([key]))[key]));
      if (key === 'thumbnail') continue;

      contacts.asyncFunction(`set${suffix}`, ExpoFunction.ownedTyped1(NEXT_VALUE, async (value: NextContactObject, input: ESObject): Promise<boolean> => {
        const patch: Record<string, ESObject> = {};
        patch[key] = input;
        await value.patch(patch);
        return true;
      }));
    }
    for (const field of NEXT_LISTS) {
      const suffix = field.field.charAt(0).toUpperCase() + field.field.slice(1);
      contacts
        .asyncFunction(`get${suffix}`, ExpoFunction.ownedTyped0(async (value: NextContactObject): Promise<ESObject> => (await value.details([field.field]))[field.field]))
        .asyncFunction(`add${field.singular}`, ExpoFunction.ownedTyped1(NEXT_RECORD, async (value: NextContactObject, input: Record<string, ESObject>): Promise<string | undefined> => await value.changeRow(field, input, 'add')))
        .asyncFunction(`update${field.singular}`, ExpoFunction.ownedTyped1(NEXT_RECORD, async (value: NextContactObject, input: Record<string, ESObject>): Promise<void> => { await value.changeRow(field, input, 'update'); }))
        .asyncFunction(`delete${field.singular}`, ExpoFunction.ownedTyped1(ExpoValueTypes.custom<Record<string, ESObject>>('existing contact field', (input: ESObject): Record<string, ESObject> => typeof input === 'string' ? { 'id': input } : requireRecord(input, 'existing contact field'), (input: Record<string, ESObject>): ESObject => input), async (value: NextContactObject, input: Record<string, ESObject>): Promise<void> => { await value.changeRow(field, input, 'delete'); }));
    }
    for (const field of UNSUPPORTED_NEXT) {
      const suffix = field.charAt(0).toUpperCase() + field.slice(1);
      contacts.asyncFunction(`get${suffix}`, ExpoFunction.ownedTyped0(async (_value: NextContactObject): Promise<ESObject> => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field}.`);
      }));

      if (field === 'extraNames' || field === 'socialProfiles') {
        const singular = field === 'extraNames' ? 'ExtraName' : 'SocialProfile';
        for (const operation of ['add', 'update', 'delete']) {
          contacts.asyncFunction(`${operation}${singular}`, ExpoFunction.ownedTyped1(NEXT_VALUE, async (_value: NextContactObject, _input: ESObject): Promise<ESObject> => {
            throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field}.`);
          }));
        }
      } else {
        contacts.asyncFunction(`set${suffix}`, ExpoFunction.ownedTyped1(NEXT_VALUE, async (_value: NextContactObject, _input: ESObject): Promise<ESObject> => {
          throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field}.`);
        }));
      }
    }
    const groups = new NextGroupClasses(this.context, this.repository, contacts, makeContact);
    return new ExpoModuleDefinition()
      .name('ExpoContactsNext')
      .sharedObjectClass(contacts)
      .sharedObjectClass(groups.groups)
      .sharedObjectClass(groups.containers)
      .events(['contactsDidChange'])
      .onDestroy((): void => this.ui.releaseUi())
      .onStartObserving('contactsDidChange', (): void => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose contact-store change notifications.');
      })
      .asyncFunction('getPermissionsAsync', async (): Promise<ContactsPermissionResponse> => await this.permissions.get())
      .asyncFunction('requestPermissionsAsync', async (): Promise<ContactsPermissionResponse> => await this.permissions.request());
  }
}
