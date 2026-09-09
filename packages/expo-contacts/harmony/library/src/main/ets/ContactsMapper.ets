import { contact } from '@kit.ContactsKit';
import { ExpoContactsError } from './ContactsError';
import { requireRecord, requireString } from './ContactsValidation';
import {
  RequestedFields,
  ExpoContactRecord,
  ExpoDateRecord,
  ExpoEmailRecord,
  ExpoPhoneRecord,
  ExpoAddressRecord,
  ExpoRelationshipRecord,
  ExpoInstantMessageRecord,
  ExpoUrlRecord,
} from './ContactsRecords';

export function mapContact(entry: contact.Contact, fields: RequestedFields): ExpoContactRecord {
  const name = entry.name;
  const org = entry.organization;
  const result = new ExpoContactRecord(contactIdentifier(entry), 'person', nativeDisplayName(entry));

  result.firstName = nonEmpty(name?.givenName);
  result.middleName = nonEmpty(name?.middleName);
  result.lastName = nonEmpty(name?.familyName);
  result.namePrefix = nonEmpty(name?.namePrefix);
  result.nameSuffix = nonEmpty(name?.nameSuffix);
  result.phoneticFirstName = nonEmpty(name?.givenNamePhonetic);
  result.phoneticMiddleName = nonEmpty(name?.middleNamePhonetic);
  result.phoneticLastName = nonEmpty(name?.familyNamePhonetic);
  result.nickname = nonEmpty(entry.nickName?.nickName);
  result.company = nonEmpty(org?.name);
  result.jobTitle = nonEmpty(org?.title);
  if (fields.has('note')) result.note = nonEmpty(entry.note?.noteContent);

  if (fields.has('emails')) {
    const emails = (entry.emails ?? []).map((email: contact.Email): ExpoEmailRecord => {
      const item = new ExpoEmailRecord(emailLabel(email));
      item.email = nonEmpty(email.email);

      return item;
    });
    if (emails.length > 0) result.emails = emails;
  }

  if (fields.has('phoneNumbers')) {
    const phones = (entry.phoneNumbers ?? []).map((phone: contact.PhoneNumber): ExpoPhoneRecord => {
      const item = new ExpoPhoneRecord(phoneLabel(phone));
      item.number = nonEmpty(phone.phoneNumber);
      if (item.number !== undefined) item.digits = phoneDigits(item.number);

      return item;
    });
    if (phones.length > 0) result.phoneNumbers = phones;
  }

  if (fields.has('addresses')) {
    const addresses = (entry.postalAddresses ?? []).map((address: contact.PostalAddress): ExpoAddressRecord => {
      const item = new ExpoAddressRecord(addressLabel(address));
      item.street = nonEmpty(address.street) ?? nonEmpty(address.postalAddress);
      item.city = nonEmpty(address.city);
      item.country = nonEmpty(address.country);
      item.region = nonEmpty(address.region);
      item.neighborhood = nonEmpty(address.neighborhood);
      item.postalCode = nonEmpty(address.postcode);
      item.poBox = nonEmpty(address.pobox);

      return item;
    });
    if (addresses.length > 0) result.addresses = addresses;
  }

  if (fields.has('instantMessageAddresses')) {
    const messages = (entry.imAddresses ?? []).map((address: contact.ImAddress): ExpoInstantMessageRecord => {
      const item = new ExpoInstantMessageRecord('other');
      item.service = imLabel(address);
      item.username = nonEmpty(address.imAddress);

      return item;
    });
    if (messages.length > 0) result.instantMessageAddresses = messages;
  }

  if (fields.has('urlAddresses')) {
    const urls = (entry.websites ?? []).map((website: contact.Website): ExpoUrlRecord => {
      const item = new ExpoUrlRecord('url');
      item.url = nonEmpty(website.website);

      return item;
    });
    if (urls.length > 0) result.urlAddresses = urls;
  }

  if (fields.has('relationships')) {
    const relations = (entry.relations ?? []).map((relation: contact.Relation): ExpoRelationshipRecord => {
      const item = new ExpoRelationshipRecord(relationLabel(relation));
      item.name = nonEmpty(relation.relationName);

      return item;
    });
    if (relations.length > 0) result.relationships = relations;
  }

  if (fields.has('birthday') || fields.has('dates')) {
    const dates: ExpoDateRecord[] = [];

    (entry.events ?? []).forEach((event: contact.Event): void => {
      const parsed = parseContactDate(event.eventDate);
      if (parsed === undefined) return;

      parsed.label = eventLabel(event);
      if (isBirthdayEvent(event) && result.birthday === undefined) result.birthday = parsed;
      else dates.push(parsed);
    });

    if (fields.has('dates') && dates.length > 0) result.dates = dates;
    if (!fields.has('birthday')) result.birthday = undefined;
  }

  result.imageAvailable = nonEmpty(entry.portrait?.uri) !== undefined;

  return result;
}

export function nativeContactFromExpo(record: Record<string, ESObject>): contact.Contact {
  const entry: contact.Contact = {};
  mergeExpoContact(entry, record);

  return entry;
}

export function mergeExpoContact(target: contact.Contact, record: Record<string, ESObject>): void {
  // Ignore output `name` so read/modify/write cannot overwrite changed components.
  const named = [
    'firstName',
    'middleName',
    'lastName',
    'namePrefix',
    'nameSuffix',
    'phoneticFirstName',
    'phoneticMiddleName',
    'phoneticLastName',
  ].some((key: string): boolean => {
    return hasConcreteField(record, key);
  });

  if (named) {
    const name = target.name;
    const given = fieldString(record, 'firstName', name?.givenName);
    const middle = fieldString(record, 'middleName', name?.middleName);
    const family = fieldString(record, 'lastName', name?.familyName);
    const changed = ['firstName', 'middleName', 'lastName'].some((key: string): boolean => hasConcreteField(record, key));
    const full = changed ? formattedName(given, middle, family) : (name?.fullName ?? formattedName(given, middle, family));

    target.name = {
      fullName: full,
      givenName: given,
      middleName: middle,
      familyName: family,
      namePrefix: fieldString(record, 'namePrefix', name?.namePrefix),
      nameSuffix: fieldString(record, 'nameSuffix', name?.nameSuffix),
      givenNamePhonetic: fieldString(record, 'phoneticFirstName', name?.givenNamePhonetic),
      middleNamePhonetic: fieldString(record, 'phoneticMiddleName', name?.middleNamePhonetic),
      familyNamePhonetic: fieldString(record, 'phoneticLastName', name?.familyNamePhonetic),
    };
  }

  if (hasConcreteField(record, 'nickname')) {
    const nickname = optionalContactString(record['nickname'], 'contact.nickname');
    target.nickName = { nickName: nickname ?? '' };
  }
  if (hasConcreteField(record, 'note')) {
    const note = optionalContactString(record['note'], 'contact.note');
    target.note = { noteContent: note ?? '' };
  }

  if (hasConcreteField(record, 'company') || hasConcreteField(record, 'jobTitle')) {
    const company = fieldString(record, 'company', target.organization?.name) ?? '';
    const title = fieldString(record, 'jobTitle', target.organization?.title);

    target.organization = { name: company, title: title ?? '' };
  }

  if (hasConcreteField(record, 'emails')) target.emails = nativeEmails(record['emails']);
  if (hasConcreteField(record, 'phoneNumbers')) target.phoneNumbers = nativePhones(record['phoneNumbers']);
  if (hasConcreteField(record, 'addresses')) target.postalAddresses = nativeAddresses(record['addresses']);
  if (hasConcreteField(record, 'instantMessageAddresses')) target.imAddresses = nativeImAddresses(record['instantMessageAddresses']);
  if (hasConcreteField(record, 'urlAddresses')) target.websites = nativeWebsites(record['urlAddresses']);
  if (hasConcreteField(record, 'relationships')) target.relations = nativeRelations(record['relationships']);

  const birthday = hasConcreteField(record, 'birthday');
  const dates = hasConcreteField(record, 'dates');

  if (birthday || dates) {
    const events: contact.Event[] = [];

    if (birthday) {
      const date = requireRecord(record['birthday'], 'contact.birthday');
      events.push(nativeEvent(date, contact.Event.EVENT_BIRTHDAY));
    } else {
      (target.events ?? []).forEach((event: contact.Event): void => {
        if (isBirthdayEvent(event)) events.push(event);
      });
    }

    if (dates) {
      arrayRecords(record['dates'], 'contact.dates').forEach((date: Record<string, ESObject>): void => {
        const label = optionalContactString(date['label'], 'contact.dates.label');
        events.push(nativeEvent(date, dateEventLabelId(label)));
      });
    } else {
      (target.events ?? []).forEach((event: contact.Event): void => {
        if (!isBirthdayEvent(event)) events.push(event);
      });
    }

    target.events = events;
  }

  if (hasConcreteField(record, 'image')) {
    const image = requireRecord(record['image'], 'contact.image');

    target.portrait = { uri: requireString(image['uri'], 'contact.image.uri') };
  }
}

function fieldString(record: Record<string, ESObject>, key: string, fallback?: string): string | undefined {
  return hasConcreteField(record, key) ? optionalContactString(record[key], `contact.${key}`) : nonEmpty(fallback);
}

export function hasConcreteField(record: Record<string, ESObject>, key: string): boolean {
  const value: ESObject = record[key];
  return Object.keys(record).includes(key) && value !== undefined && value !== null;
}

function optionalContactString(value: ESObject, name: string): string | undefined {
  if (value === undefined || value === null) return undefined;

  if (typeof value !== 'string') {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be a string.`);
  }

  return nonEmpty(value);
}

function formattedName(first?: string, middle?: string, last?: string): string {
  return [first, middle, last].filter((part: string | undefined): boolean => part !== undefined && part.length > 0).join(' ');
}

function arrayRecords(value: ESObject, name: string): Record<string, ESObject>[] {
  if (!Array.isArray(value)) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_ARGUMENT', `'${name}' must be an object array.`);
  }

  return value.map((entry: ESObject, index: number): Record<string, ESObject> => {
    return requireRecord(entry, `${name}[${index}]`);
  });
}

function nativeEmails(value: ESObject): contact.Email[] {
  const result: contact.Email[] = [];

  arrayRecords(value, 'contact.emails').forEach((item: Record<string, ESObject>): void => {
    const email = optionalContactString(item['email'], 'contact.emails.email');
    if (email === undefined) return;

    const label = optionalContactString(item['label'], 'contact.emails.label');
    result.push({ email, labelName: label, labelId: emailLabelId(label) });
  });

  return result;
}

function nativePhones(value: ESObject): contact.PhoneNumber[] {
  const result: contact.PhoneNumber[] = [];

  arrayRecords(value, 'contact.phoneNumbers').forEach((item: Record<string, ESObject>): void => {
    const number = optionalContactString(item['number'], 'contact.phoneNumbers.number');
    if (number === undefined) return;

    const label = optionalContactString(item['label'], 'contact.phoneNumbers.label');
    result.push({ phoneNumber: number, labelName: label, labelId: phoneLabelId(label) });
  });

  return result;
}

function nativeAddresses(value: ESObject): contact.PostalAddress[] {
  const result: contact.PostalAddress[] = [];

  arrayRecords(value, 'contact.addresses').forEach((item: Record<string, ESObject>): void => {
    const label = optionalContactString(item['label'], 'contact.addresses.label');
    const street = optionalContactString(item['street'], 'contact.addresses.street');
    const city = optionalContactString(item['city'], 'contact.addresses.city');
    const country = optionalContactString(item['country'], 'contact.addresses.country');
    const region = optionalContactString(item['region'], 'contact.addresses.region');
    const area = optionalContactString(item['neighborhood'], 'contact.addresses.neighborhood');
    const postcode = optionalContactString(item['postalCode'], 'contact.addresses.postalCode');
    const pobox = optionalContactString(item['poBox'], 'contact.addresses.poBox');

    if (
      street === undefined &&
      city === undefined &&
      country === undefined &&
      region === undefined &&
      area === undefined &&
      postcode === undefined &&
      pobox === undefined
    )
      return;

    result.push({
      postalAddress: street ?? '',
      street,
      city,
      country,
      region,
      neighborhood: area,
      postcode,
      pobox,
      labelName: label,
      labelId: addressLabelId(label),
    });
  });

  return result;
}

function nativeImAddresses(value: ESObject): contact.ImAddress[] {
  const result: contact.ImAddress[] = [];

  arrayRecords(value, 'contact.instantMessageAddresses').forEach((item: Record<string, ESObject>): void => {
    const address = optionalContactString(item['username'], 'contact.instantMessageAddresses.username');
    if (address === undefined) return;

    const label = optionalContactString(item['service'], 'contact.instantMessageAddresses.service');
    result.push({
      imAddress: address,
      labelName: label,
      labelId: imLabelId(label),
    });
  });

  return result;
}

function nativeWebsites(value: ESObject): contact.Website[] {
  const result: contact.Website[] = [];

  arrayRecords(value, 'contact.urlAddresses').forEach((item: Record<string, ESObject>): void => {
    const website = optionalContactString(item['url'], 'contact.urlAddresses.url');
    if (website !== undefined) result.push({ website });
  });

  return result;
}

function nativeRelations(value: ESObject): contact.Relation[] {
  const result: contact.Relation[] = [];

  arrayRecords(value, 'contact.relationships').forEach((item: Record<string, ESObject>): void => {
    const name = optionalContactString(item['name'], 'contact.relationships.name');
    if (name === undefined) return;

    const label = optionalContactString(item['label'], 'contact.relationships.label');
    result.push({
      relationName: name,
      labelName: label,
      labelId: relationLabelId(label),
    });
  });

  return result;
}

function nativeEvent(record: Record<string, ESObject>, labelId: number): contact.Event {
  if (hasConcreteField(record, 'format') && record['format'] !== 'gregorian') {
    throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS only supports Gregorian contact dates.');
  }

  const day = requiredDatePart(record['day'], 'day', 1, 31);
  const month = requiredDatePart(record['month'], 'month', 0, 11) + 1;
  const year = optionalDateYear(record['year']);

  if (!isValidGregorianDate(day, month, year)) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_DATE', 'Contact date does not exist in the Gregorian calendar.');
  }

  return {
    eventDate: year === undefined ? `--${padDatePart(month)}-${padDatePart(day)}` : `${padDateYear(year)}-${padDatePart(month)}-${padDatePart(day)}`,
    labelName: optionalContactString(record['label'], 'contact.date.label'),
    labelId,
  };
}

function requiredDatePart(value: ESObject, name: string, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > max) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_DATE', `Contact date '${name}' is invalid.`);
  }

  return value;
}

function optionalDateYear(value: ESObject): number | undefined {
  if (value === undefined || value === null) return undefined;

  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 1 || value > 9999) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_DATE', "Contact date 'year' must be between 1 and 9999.");
  }

  return value;
}

function parseContactDate(value: string): ExpoDateRecord | undefined {
  const match = /^(?:(\d{4})-|--)?(\d{1,2})-(\d{1,2})$/.exec(value);
  if (match === null) return undefined;

  const month = Number(match[2]);
  const day = Number(match[3]);
  const year = match[1] === undefined ? undefined : Number(match[1]);

  if (!Number.isSafeInteger(month) || month < 1 || month > 12 || !Number.isSafeInteger(day) || day < 1 || !isValidGregorianDate(day, month, year)) {
    return undefined;
  }

  const result = new ExpoDateRecord(day, month - 1);
  if (year !== undefined) result.year = year;

  return result;
}

function isValidGregorianDate(day: number, month: number, year?: number): boolean {
  if (year !== undefined && (year < 1 || year > 9999)) return false;

  let days = 31;
  if (month === 4 || month === 6 || month === 9 || month === 11) days = 30;
  if (month === 2) days = year === undefined || isLeapYear(year) ? 29 : 28;

  return day <= days;
}

function isLeapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

export function padDatePart(value: number): string {
  return value < 10 ? `0${value}` : String(value);
}

export function padDateYear(value: number): string {
  if (value < 10) return `000${value}`;
  if (value < 100) return `00${value}`;
  if (value < 1000) return `0${value}`;
  return String(value);
}

function nonEmpty(value?: string): string | undefined {
  return value !== undefined && value.length > 0 ? value : undefined;
}

export function contactIdentifier(entry: contact.Contact): string {
  if (entry.id !== undefined && Number.isSafeInteger(entry.id) && entry.id >= 0) return String(entry.id);
  throw new ExpoContactsError('ERR_CONTACTS_INVALID_IDENTIFIER', 'HarmonyOS returned a contact without a valid numeric identifier.');
}

export function holderIdentifier(holder: contact.Holder): string {
  if (holder.holderId !== undefined) {
    if (Number.isSafeInteger(holder.holderId) && holder.holderId >= 0) return String(holder.holderId);
  } else if (nonEmpty(holder.bundleName) !== undefined) {
    // Include the account name; bundleName alone can identify multiple holders.
    return JSON.stringify([holder.bundleName, holder.displayName ?? '']);
  }
  throw new ExpoContactsError('ERR_CONTACTS_INVALID_CONTAINER', 'HarmonyOS returned a contact holder without a valid identifier.');
}

export function groupIdentifier(group: contact.Group): string {
  if (group.groupId === undefined || !Number.isSafeInteger(group.groupId) || group.groupId < 0) {
    throw new ExpoContactsError('ERR_CONTACTS_INVALID_GROUP', 'HarmonyOS returned a contact group without an identifier.');
  }

  return String(group.groupId);
}

export function hasGroup(entry: contact.Contact, groupId: string): boolean {
  return (entry.groups ?? []).some((group: contact.Group): boolean => groupIdentifier(group) === groupId);
}

export function sortNativeContacts(values: contact.Contact[], sort?: string): void {
  if (sort !== 'firstName' && sort !== 'lastName') return;

  values.sort((left: contact.Contact, right: contact.Contact): number => {
    if (sort === 'firstName') return (left.name?.givenName ?? '').localeCompare(right.name?.givenName ?? '');
    return (left.name?.familyName ?? '').localeCompare(right.name?.familyName ?? '');
  });
}

export function nativeDisplayName(value: contact.Contact): string {
  return (
    nonEmpty(value.name?.fullName) ??
    nonEmpty(formattedName(value.name?.givenName, value.name?.middleName, value.name?.familyName)) ??
    nonEmpty(value.organization?.name) ??
    ''
  );
}

function normalizedLabel(value?: string): string | undefined {
  return nonEmpty(value)?.toLowerCase();
}

function emailLabelId(label?: string): number {
  const normalized = normalizedLabel(label);
  if (normalized === 'home') return contact.Email.EMAIL_HOME;
  if (normalized === 'work') return contact.Email.EMAIL_WORK;
  if (normalized === 'other') return contact.Email.EMAIL_OTHER;
  return contact.Email.CUSTOM_LABEL;
}

function phoneLabelId(label?: string): number {
  const normalized = normalizedLabel(label);
  if (normalized === 'home') return contact.PhoneNumber.NUM_HOME;
  if (normalized === 'mobile' || normalized === 'cell') return contact.PhoneNumber.NUM_MOBILE;
  if (normalized === 'work') return contact.PhoneNumber.NUM_WORK;
  if (normalized === 'faxwork') return contact.PhoneNumber.NUM_FAX_WORK;
  if (normalized === 'faxhome') return contact.PhoneNumber.NUM_FAX_HOME;
  if (normalized === 'pager') return contact.PhoneNumber.NUM_PAGER;
  if (normalized === 'callback') return contact.PhoneNumber.NUM_CALLBACK;
  if (normalized === 'car') return contact.PhoneNumber.NUM_CAR;
  if (normalized === 'companymain') return contact.PhoneNumber.NUM_COMPANY_MAIN;
  if (normalized === 'isdn') return contact.PhoneNumber.NUM_ISDN;
  if (normalized === 'main') return contact.PhoneNumber.NUM_MAIN;
  if (normalized === 'otherfax') return contact.PhoneNumber.NUM_OTHER_FAX;
  if (normalized === 'radio') return contact.PhoneNumber.NUM_RADIO;
  if (normalized === 'telex') return contact.PhoneNumber.NUM_TELEX;
  if (normalized === 'ttytdd') return contact.PhoneNumber.NUM_TTY_TDD;
  if (normalized === 'workmobile') return contact.PhoneNumber.NUM_WORK_MOBILE;
  if (normalized === 'workpager') return contact.PhoneNumber.NUM_WORK_PAGER;
  if (normalized === 'assistant') return contact.PhoneNumber.NUM_ASSISTANT;
  if (normalized === 'mms') return contact.PhoneNumber.NUM_MMS;
  if (normalized === 'other') return contact.PhoneNumber.NUM_OTHER;
  return contact.PhoneNumber.CUSTOM_LABEL;
}

function addressLabelId(label?: string): number {
  const normalized = normalizedLabel(label);
  if (normalized === 'home') return contact.PostalAddress.ADDR_HOME;
  if (normalized === 'work') return contact.PostalAddress.ADDR_WORK;
  if (normalized === 'other') return contact.PostalAddress.ADDR_OTHER;
  return contact.PostalAddress.CUSTOM_LABEL;
}

function relationLabelId(label?: string): number {
  const normalized = normalizedLabel(label);
  if (normalized === 'assistant') return contact.Relation.RELATION_ASSISTANT;
  if (normalized === 'brother') return contact.Relation.RELATION_BROTHER;
  if (normalized === 'child') return contact.Relation.RELATION_CHILD;
  if (normalized === 'domesticpartner') return contact.Relation.RELATION_DOMESTIC_PARTNER;
  if (normalized === 'father') return contact.Relation.RELATION_FATHER;
  if (normalized === 'friend') return contact.Relation.RELATION_FRIEND;
  if (normalized === 'manager') return contact.Relation.RELATION_MANAGER;
  if (normalized === 'mother') return contact.Relation.RELATION_MOTHER;
  if (normalized === 'parent') return contact.Relation.RELATION_PARENT;
  if (normalized === 'partner') return contact.Relation.RELATION_PARTNER;
  if (normalized === 'referredby') return contact.Relation.RELATION_REFERRED_BY;
  if (normalized === 'relative') return contact.Relation.RELATION_RELATIVE;
  if (normalized === 'sister') return contact.Relation.RELATION_SISTER;
  if (normalized === 'spouse') return contact.Relation.RELATION_SPOUSE;
  return contact.Relation.CUSTOM_LABEL;
}

function imLabelId(label?: string): number {
  const normalized = normalizedLabel(label);
  if (normalized === 'aim') return contact.ImAddress.IM_AIM;
  if (normalized === 'msn') return contact.ImAddress.IM_MSN;
  if (normalized === 'yahoo') return contact.ImAddress.IM_YAHOO;
  if (normalized === 'skype') return contact.ImAddress.IM_SKYPE;
  if (normalized === 'qq') return contact.ImAddress.IM_QQ;
  if (normalized === 'icq') return contact.ImAddress.IM_ICQ;
  if (normalized === 'jabber') return contact.ImAddress.IM_JABBER;
  return contact.ImAddress.CUSTOM_LABEL;
}

function dateEventLabelId(label?: string): number {
  const normalized = normalizedLabel(label);
  if (normalized === 'birthday') return contact.Event.EVENT_BIRTHDAY;
  if (normalized === 'anniversary') return contact.Event.EVENT_ANNIVERSARY;
  if (normalized === 'other') return contact.Event.EVENT_OTHER;
  return contact.Event.CUSTOM_LABEL;
}

function emailLabel(value: contact.Email): string {
  return value.labelId === contact.Email.CUSTOM_LABEL ? (nonEmpty(value.labelName) ?? 'other') : emailLabelName(value.labelId);
}

function emailLabelName(value?: number): string {
  if (value === contact.Email.EMAIL_HOME) return 'home';
  if (value === contact.Email.EMAIL_WORK) return 'work';
  return 'other';
}

function phoneLabel(value: contact.PhoneNumber): string {
  return value.labelId === contact.PhoneNumber.CUSTOM_LABEL ? (nonEmpty(value.labelName) ?? 'other') : phoneLabelName(value.labelId);
}

function phoneLabelName(value?: number): string {
  if (value === contact.PhoneNumber.NUM_HOME) return 'home';
  if (value === contact.PhoneNumber.NUM_MOBILE) return 'mobile';
  if (value === contact.PhoneNumber.NUM_WORK) return 'work';
  if (value === contact.PhoneNumber.NUM_FAX_WORK) return 'faxWork';
  if (value === contact.PhoneNumber.NUM_FAX_HOME) return 'faxHome';
  if (value === contact.PhoneNumber.NUM_PAGER) return 'pager';
  if (value === contact.PhoneNumber.NUM_CALLBACK) return 'callback';
  if (value === contact.PhoneNumber.NUM_CAR) return 'car';
  if (value === contact.PhoneNumber.NUM_COMPANY_MAIN) return 'companyMain';
  if (value === contact.PhoneNumber.NUM_ISDN) return 'isdn';
  if (value === contact.PhoneNumber.NUM_MAIN) return 'main';
  if (value === contact.PhoneNumber.NUM_OTHER_FAX) return 'otherFax';
  if (value === contact.PhoneNumber.NUM_RADIO) return 'radio';
  if (value === contact.PhoneNumber.NUM_TELEX) return 'telex';
  if (value === contact.PhoneNumber.NUM_TTY_TDD) return 'ttyTdd';
  if (value === contact.PhoneNumber.NUM_WORK_MOBILE) return 'workMobile';
  if (value === contact.PhoneNumber.NUM_WORK_PAGER) return 'workPager';
  if (value === contact.PhoneNumber.NUM_ASSISTANT) return 'assistant';
  if (value === contact.PhoneNumber.NUM_MMS) return 'mms';
  return 'other';
}

function addressLabel(value: contact.PostalAddress): string {
  if (value.labelId === contact.PostalAddress.CUSTOM_LABEL && nonEmpty(value.labelName) !== undefined) return value.labelName as string;
  if (value.labelId === contact.PostalAddress.ADDR_HOME) return 'home';
  if (value.labelId === contact.PostalAddress.ADDR_WORK) return 'work';
  return 'other';
}

function relationLabel(value: contact.Relation): string {
  if (value.labelId === contact.Relation.CUSTOM_LABEL && nonEmpty(value.labelName) !== undefined) return value.labelName as string;
  if (value.labelId === contact.Relation.RELATION_ASSISTANT) return 'assistant';
  if (value.labelId === contact.Relation.RELATION_BROTHER) return 'brother';
  if (value.labelId === contact.Relation.RELATION_CHILD) return 'child';
  if (value.labelId === contact.Relation.RELATION_DOMESTIC_PARTNER) return 'domesticPartner';
  if (value.labelId === contact.Relation.RELATION_FATHER) return 'father';
  if (value.labelId === contact.Relation.RELATION_FRIEND) return 'friend';
  if (value.labelId === contact.Relation.RELATION_MANAGER) return 'manager';
  if (value.labelId === contact.Relation.RELATION_MOTHER) return 'mother';
  if (value.labelId === contact.Relation.RELATION_PARENT) return 'parent';
  if (value.labelId === contact.Relation.RELATION_PARTNER) return 'partner';
  if (value.labelId === contact.Relation.RELATION_REFERRED_BY) return 'referredBy';
  if (value.labelId === contact.Relation.RELATION_RELATIVE) return 'relative';
  if (value.labelId === contact.Relation.RELATION_SISTER) return 'sister';
  if (value.labelId === contact.Relation.RELATION_SPOUSE) return 'spouse';
  return 'other';
}

function imLabel(value: contact.ImAddress): string {
  if (value.labelId === contact.ImAddress.CUSTOM_LABEL && nonEmpty(value.labelName) !== undefined) return value.labelName as string;
  if (value.labelId === contact.ImAddress.IM_AIM) return 'aim';
  if (value.labelId === contact.ImAddress.IM_MSN) return 'msn';
  if (value.labelId === contact.ImAddress.IM_YAHOO) return 'yahoo';
  if (value.labelId === contact.ImAddress.IM_SKYPE) return 'skype';
  if (value.labelId === contact.ImAddress.IM_QQ) return 'qq';
  if (value.labelId === contact.ImAddress.IM_ICQ) return 'icq';
  if (value.labelId === contact.ImAddress.IM_JABBER) return 'jabber';
  return 'im';
}

function eventLabel(value: contact.Event): string {
  if (value.labelId === contact.Event.CUSTOM_LABEL && nonEmpty(value.labelName) !== undefined) return value.labelName as string;
  if (value.labelId === contact.Event.EVENT_BIRTHDAY) return 'birthday';
  if (value.labelId === contact.Event.EVENT_ANNIVERSARY) return 'anniversary';
  return 'other';
}

function isBirthdayEvent(value: contact.Event): boolean {
  return value.labelId === contact.Event.EVENT_BIRTHDAY || normalizedLabel(value.labelName) === 'birthday';
}

function phoneDigits(value: string): string {
  return value.replace(/[^0-9*#+]/g, '');
}
