import { contact } from '@kit.ContactsKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { ExpoContactsError } from './ContactsError';
import { ExpoDateRecord } from './ContactsRecords';
import { addressLabel, contactIdentifier, dateEventLabelId, emailLabel, eventLabel, imLabel, nativeContactFromExpo, parseContactDate, phoneLabel, relationLabel } from './ContactsMapper';
import { requireRecord, requireString } from './ContactsValidation';

export const NEXT_STRINGS: Record<string, string> = {
  'givenName': 'firstName', 'middleName': 'middleName', 'familyName': 'lastName',
  'nickname': 'nickname', 'prefix': 'namePrefix', 'suffix': 'nameSuffix',
  'phoneticGivenName': 'phoneticFirstName', 'phoneticMiddleName': 'phoneticMiddleName',
  'phoneticFamilyName': 'phoneticLastName', 'company': 'company', 'jobTitle': 'jobTitle', 'note': 'note',
};
export const UNSUPPORTED_NEXT: string[] = ['isFavourite', 'maidenName', 'department', 'phoneticCompanyName', 'nonGregorianBirthday', 'extraNames', 'socialProfiles'];

export class NextListField {
  readonly field: string;
  readonly singular: string;
  readonly legacy: string;
  readonly native: string;
  readonly attribute: contact.Attribute;

  constructor(field: string, singular: string, legacy: string, native: string, attribute: contact.Attribute) {
    this.field = field;
    this.singular = singular;
    this.legacy = legacy;
    this.native = native;
    this.attribute = attribute;
  }
}

export const NEXT_LISTS: NextListField[] = [
  new NextListField('emails', 'Email', 'emails', 'emails', contact.Attribute.ATTR_EMAIL),
  new NextListField('phones', 'Phone', 'phoneNumbers', 'phoneNumbers', contact.Attribute.ATTR_PHONE),
  new NextListField('dates', 'Date', 'dates', 'events', contact.Attribute.ATTR_CONTACT_EVENT),
  new NextListField('addresses', 'Address', 'addresses', 'postalAddresses', contact.Attribute.ATTR_POSTAL_ADDRESS),
  new NextListField('relations', 'Relation', 'relationships', 'relations', contact.Attribute.ATTR_RELATION),
  new NextListField('urlAddresses', 'UrlAddress', 'urlAddresses', 'websites', contact.Attribute.ATTR_WEBSITE),
  new NextListField('imAddresses', 'ImAddress', 'instantMessageAddresses', 'imAddresses', contact.Attribute.ATTR_IM),
];

export function nextDate(date: ExpoDateRecord): Record<string, ESObject> {
  const result: Record<string, ESObject> = { 'day': date.day, 'month': date.month + 1 };
  if (date.year !== undefined) result['year'] = date.year;
  return result;
}

function legacyDate(value: ESObject): Record<string, ESObject> {
  const date = requireRecord(value, 'contact date');
  if (typeof date['month'] !== 'number') throw new ExpoContactsError('ERR_CONTACTS_INVALID_DATE', 'Contact month must be a number from 1 to 12.');
  return { 'year': date['year'], 'month': (date['month'] as number) - 1, 'day': date['day'] };
}

function nextLabel(value: ESObject): string {
  if (value === undefined || value === null) return 'other';
  if (typeof value !== 'string') throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', 'Contact labels must be strings.');
  return value.trim() || 'other';
}

export function legacyNextScalars(input: Record<string, ESObject>, replace: boolean): Record<string, ESObject> {
  const result: Record<string, ESObject> = {};
  for (const field of UNSUPPORTED_NEXT) {
    if (input[field] !== undefined && input[field] !== null) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field}.`);
    }
  }
  for (const field of Object.keys(NEXT_STRINGS)) {
    if (input[field] !== undefined || replace) {
      const value: ESObject = input[field] ?? '';
      if (typeof value !== 'string') throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `contact.${field} must be a string or null.`);
      result[NEXT_STRINGS[field]] = value;
    }
  }
  if (input['birthday'] !== undefined && input['birthday'] !== null) result['birthday'] = legacyDate(input['birthday']);
  if (input['image'] !== undefined && input['image'] !== null) result['image'] = { 'uri': requireString(input['image'], 'contact.image') };
  return result;
}

export function legacyNextInput(input: Record<string, ESObject>): Record<string, ESObject> {
  const result = legacyNextScalars(input, false);
  for (const field of NEXT_LISTS) {
    const values: ESObject = input[field.field];
    if (values === undefined) continue;
    if (values !== undefined && values !== null && !Array.isArray(values)) throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `contact.${field.field} must be an array or null.`);

    const rows = ((values ?? []) as ESObject[]).map((value: ESObject): Record<string, ESObject> => legacyNextRow(field, requireRecord(value, field.field)));
    const source: Record<string, ESObject> = {};
    source[field.legacy] = rows;
    if (nativeNextRows(nativeContactFromExpo(source), field).length !== rows.length) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field.field} entries that cannot be represented by Contacts Kit.`);
    }

    result[field.legacy] = field.field === 'dates' && input['birthday'] !== undefined
      ? rows.filter((row: Record<string, ESObject>): boolean => (row['label'] as string).toLowerCase() !== 'birthday')
      : rows;
  }

  return result;
}

export function legacyNextRow(field: NextListField, value: Record<string, ESObject>): Record<string, ESObject> {
  const result: Record<string, ESObject> = { 'label': nextLabel(value['label']) };
  if ((field.field === 'urlAddresses' || field.field === 'imAddresses') && (result['label'] as string).toLowerCase() !== 'other') {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field.field} labels other than 'other'.`);
  }
  if (field.field === 'addresses' && value['state'] !== undefined && value['state'] !== null) {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose an address state separate from region; use region.');
  }

  let mapping: Record<string, string>;
  switch (field.field) {
    case 'emails': mapping = { 'address': 'email' }; break;
    case 'phones': mapping = { 'number': 'number' }; break;
    case 'addresses': mapping = { 'street': 'street', 'city': 'city', 'region': 'region', 'postcode': 'postalCode', 'country': 'country' }; break;
    case 'relations': mapping = { 'name': 'name' }; break;
    case 'urlAddresses': mapping = { 'url': 'url' }; break;
    case 'imAddresses': mapping = { 'username': 'username', 'service': 'service' }; break;
    case 'dates': {
      if (value['date'] === undefined || value['date'] === null) {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose date entries without a date value.');
      }

      const date = legacyDate(value['date']);
      date['label'] = result['label'];
      return date;
    }
    default: throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field.field}.`);
  }
  for (const key of Object.keys(mapping)) {
    const item: ESObject = value[key];
    if (item !== undefined && item !== null && typeof item !== 'string') throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `${field.field}.${key} must be a string.`);
    result[mapping[key]] = item ?? undefined;
  }
  const values = Object.keys(mapping).filter((key: string): boolean => key !== 'service');
  if (!values.some((key: string): boolean => typeof value[key] === 'string' && (value[key] as string).length > 0)) {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field.field} entries without a value.`);
  }
  return result;
}

export function nativeNextRows(entry: contact.Contact, field: NextListField): ESObject[] {
  const record = entry as ESObject as Record<string, ESObject>;
  return (record[field.native] ?? []) as ESObject[];
}

export function assignNativeNextRows(entry: contact.Contact, field: NextListField, rows: ESObject[]): void {
  const record = entry as ESObject as Record<string, ESObject>;
  record[field.native] = rows;
}

export function newNativeNextRow(field: NextListField, input: Record<string, ESObject>): ESObject {
  const source: Record<string, ESObject> = {};
  source[field.legacy] = [legacyNextRow(field, input)];
  const rows: ESObject[] = nativeNextRows(nativeContactFromExpo(source), field);
  if (rows.length !== 1) {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field.field} entries that cannot be represented by Contacts Kit.`);
  }
  return rows[0];
}

export async function nextRows(entry: contact.Contact, field: NextListField): Promise<Record<string, ESObject>[]> {
  const native: ESObject[] = nativeNextRows(entry, field);
  if (native.length === 0) return [];

  const snapshot = await rowSnapshot(entry, field);
  return native.map((value: ESObject, index: number): Record<string, ESObject> => {
    const result = projectNextRow(value, field);
    result['id'] = JSON.stringify([contactIdentifier(entry), field.field, snapshot, index]);
    return result;
  });
}

function projectNextRow(value: ESObject, field: NextListField): Record<string, ESObject> {
  switch (field.field) {
    case 'emails': {
      const email = value as contact.Email;
      return { 'label': emailLabel(email), 'address': email.email };
    }
    case 'phones': {
      const phone = value as contact.PhoneNumber;
      return { 'label': phoneLabel(phone), 'number': phone.phoneNumber };
    }
    case 'addresses': {
      const address = value as contact.PostalAddress;
      return { 'label': addressLabel(address), 'street': address.street || address.postalAddress, 'city': address.city, 'region': address.region, 'postcode': address.postcode, 'country': address.country };
    }
    case 'relations': {
      const relation = value as contact.Relation;
      return { 'label': relationLabel(relation), 'name': relation.relationName };
    }
    case 'urlAddresses': return { 'label': 'other', 'url': (value as contact.Website).website };
    case 'imAddresses': {
      const address = value as contact.ImAddress;
      return { 'label': 'other', 'username': address.imAddress, 'service': imLabel(address) };
    }
    case 'dates': {
      const event = value as contact.Event;
      const date = parseContactDate(event.eventDate);
      return { 'label': eventLabel(event), 'date': date === undefined ? null : nextDate(date) };
    }
    default: throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', `HarmonyOS Contacts Kit does not expose ${field.field}.`);
  }
}

function orderedRow(value: ESObject, omitEmpty: boolean): Record<string, ESObject> {
  const row = value as Record<string, ESObject>;
  const result: Record<string, ESObject> = {};
  for (const key of Object.keys(row).sort()) {
    if (!omitEmpty || (row[key] !== '' && row[key] !== null)) result[key] = row[key];
  }

  return result;
}

function projectedRowKey(value: ESObject, field: NextListField): string {
  // Providers can materialize absent optional strings as empty strings on readback.
  return JSON.stringify(orderedRow(projectNextRow(value, field), true));
}

export async function addedNextRowId(entry: contact.Contact, field: NextListField, previousRows: ESObject[], added: ESObject): Promise<string> {
  const key = projectedRowKey(added, field);
  const previous: ESObject[] = previousRows.filter((row: ESObject): boolean => projectedRowKey(row, field) === key);
  const rows: ESObject[] = nativeNextRows(entry, field);
  const candidates: number[] = [];
  rows.forEach((row: ESObject, index: number): void => {
    if (projectedRowKey(row, field) === key) candidates.push(index);
  });
  if (candidates.length === previous.length + 1) {
    // Remove the previous occurrences using their complete native values before
    // choosing the added row. Equal native rows are interchangeable.
    for (let index = 0; index < previous.length; index++) {
      const nativeKey: string = JSON.stringify(orderedRow(previous[index], false));
      const match = candidates.findIndex((index: number): boolean => JSON.stringify(orderedRow(rows[index], false)) === nativeKey);
      if (match < 0) break;

      candidates.splice(match, 1);
    }
    if (candidates.length === 1) return JSON.stringify([contactIdentifier(entry), field.field, await rowSnapshot(entry, field), candidates[0]]);
  }
  throw new ExpoContactsError('ERR_CONTACTS_FIELD_NOT_FOUND', 'The field was saved but cannot be identified. Read the contact again.');
}

export async function rowSnapshot(entry: contact.Contact, field: NextListField): Promise<string> {
  const digest = cryptoFramework.createMd('SHA256');
  const rows = nativeNextRows(entry, field).map((row: ESObject): Record<string, ESObject> => orderedRow(row, false));
  await digest.update({ data: new util.TextEncoder().encodeInto(JSON.stringify(rows)) });
  return new util.Base64Helper().encodeToStringSync((await digest.digest()).data);
}

export async function locateNextRow(entry: contact.Contact, field: NextListField, identifier: string): Promise<number> {
  const snapshot = await rowSnapshot(entry, field);
  const rows: ESObject[] = nativeNextRows(entry, field);
  for (let index = 0; index < rows.length; index++) {
    if (identifier === JSON.stringify([contactIdentifier(entry), field.field, snapshot, index])) return index;
  }
  throw new ExpoContactsError('ERR_CONTACTS_STALE_FIELD', 'The field identifier is stale or belongs to another contact. Read the list again before modifying it.');
}

export function patchNativeNextRow(field: NextListField, original: ESObject, merged: Record<string, ESObject>, provided: Record<string, ESObject>): ESObject {
  if (Object.keys(provided).every((key: string): boolean => key === 'id' || provided[key] === undefined)) return original;

  if (field.field === 'dates' && provided['date'] === undefined) {
    if (provided['label'] === undefined) return original;

    const event = original as contact.Event;
    const label = nextLabel(provided['label']);
    return { 'eventDate': event.eventDate, 'labelId': dateEventLabelId(label), 'labelName': label } as contact.Event;
  }
  const next = newNativeNextRow(field, merged) as Record<string, ESObject>;
  const previous = original as Record<string, ESObject>;
  const result: Record<string, ESObject> = {};
  for (const key of Object.keys(previous)) result[key] = previous[key];
  let mapping: Record<string, string[]>;
  switch (field.field) {
    case 'emails': mapping = { 'address': ['email'], 'label': ['labelName', 'labelId'] }; break;
    case 'phones': mapping = { 'number': ['phoneNumber'], 'label': ['labelName', 'labelId'] }; break;
    case 'addresses': mapping = { 'street': ['street', 'postalAddress'], 'city': ['city'], 'region': ['region'], 'postcode': ['postcode'], 'country': ['country'], 'label': ['labelName', 'labelId'] }; break;
    case 'relations': mapping = { 'name': ['relationName'], 'label': ['labelName', 'labelId'] }; break;
    case 'urlAddresses': mapping = { 'url': ['website'] }; break;
    case 'imAddresses': mapping = { 'username': ['imAddress'], 'service': ['labelName', 'labelId'] }; break;
    default: return next;
  }
  for (const key of Object.keys(mapping)) {
    if (provided[key] === undefined) continue;
    for (const nativeKey of mapping[key]) result[nativeKey] = next[nativeKey];
  }

  return result;
}
