import { ContactQuery } from './ContactsRecords';
import { ExpoContactsError } from './ContactsError';

export function readContactQuery(value: ESObject): ContactQuery {
  const input = optionalInputRecord(value, 'contactQuery');
  const raw: ESObject = input?.['rawContacts'];
  if (raw !== undefined && raw !== null && typeof raw !== 'boolean') {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', "'contactQuery.rawContacts' must be a boolean.");
  }
  if (input?.['rawContacts'] === true) {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS does not expose raw contacts.');
  }

  const size = optionalNonNegativeInteger(input?.['pageSize'], 'pageSize') ?? 0;
  const offset = optionalNonNegativeInteger(input?.['pageOffset'], 'pageOffset') ?? 0;
  const fields = optionalStringList(input?.['fields'], 'contactQuery.fields');
  const id: ESObject = input === undefined ? undefined : input['id'];

  let ids: string[] | undefined;
  if (typeof id === 'string') {
    ids = [requireString(id, 'contactQuery.id')];
  } else if (Array.isArray(id)) {
    ids = id.map((entry: ESObject, index: number): string => {
      return requireString(entry, `contactQuery.id[${index}]`);
    });
  } else if (id !== undefined && id !== null) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', "'contactQuery.id' must be a string or string array.");
  }

  const sort = optionalInputString(input?.['sort'], 'contactQuery.sort');
  if (sort !== undefined && sort !== 'userDefault' && sort !== 'firstName' && sort !== 'lastName' && sort !== 'none') {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'contactQuery.sort' has unsupported value '${sort}'.`);
  }

  return {
    pageSize: size,
    pageOffset: offset,
    fields,
    sort,
    name: optionalInputString(input?.['name'], 'contactQuery.name', true),
    ids,
    groupId: optionalInputString(input?.['groupId'], 'contactQuery.groupId'),
    containerId: optionalInputString(input?.['containerId'], 'contactQuery.containerId'),
  };
}

function optionalNonNegativeInteger(value: ESObject, name: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be a non-negative integer.`);
  }
  return value;
}

function optionalRecord(value: ESObject): Record<string, ESObject> | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'object' || Array.isArray(value)) return undefined;
  return value as Record<string, ESObject>;
}

export function optionalInputRecord(value: ESObject, name: string): Record<string, ESObject> | undefined {
  if (value === undefined || value === null) return undefined;
  const record = optionalRecord(value);
  if (record === undefined) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be an object.`);
  }

  return record;
}

export function requireRecord(value: ESObject, name: string): Record<string, ESObject> {
  const record = optionalRecord(value);
  if (record === undefined) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be an object.`);
  }

  return record;
}

function optionalString(value: ESObject): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function optionalInputString(value: ESObject, name: string, allowEmpty: boolean = false): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string' || (!allowEmpty && value.length === 0)) {
    const requirement = allowEmpty ? 'a string' : 'a non-empty string';
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be ${requirement}.`);
  }
  return value;
}

export function requireString(value: ESObject, name: string): string {
  const result = optionalString(value);
  if (result === undefined) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be a non-empty string.`);
  }

  return result;
}

function optionalStringList(value: ESObject, name: string): string[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value)) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be a string array.`);
  }

  return value.map((entry: ESObject, index: number): string => {
    return requireString(entry, `${name}[${index}]`);
  });
}

export function optionalStringOrStringList(value: ESObject, name: string): string[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value === 'string') return [requireString(value, name)];
  return optionalStringList(value, name);
}
