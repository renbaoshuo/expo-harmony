import { util } from '@kit.ArkTS';
import { ExpoContactRecord, ExpoDateRecord, ExpoEmailRecord, ExpoPhoneRecord, ExpoAddressRecord, ExpoUrlRecord } from './ContactsRecords';
import { padDatePart, padDateYear } from './ContactsMapper';

const VCARD_LINE_BREAK: string = '\r\n';
const VCARD_MAX_LINE_OCTETS: number = 75;

export function serializeVCard(contacts: ExpoContactRecord[], photos: string[]): string {
  const cards = contacts.map((entry: ExpoContactRecord, index: number): string => serializeContactVCard(entry, photos[index]));
  return `${cards.join(VCARD_LINE_BREAK)}${VCARD_LINE_BREAK}`;
}

function serializeContactVCard(entry: ExpoContactRecord, photo?: string): string {
  const lines: string[] = ['BEGIN:VCARD', 'VERSION:3.0'];

  lines.push(`FN:${escapeVCard(entry.name)}`);
  lines.push(
    `N:${escapeVCard(entry.lastName ?? '')};${escapeVCard(entry.firstName ?? '')};${escapeVCard(entry.middleName ?? '')};${escapeVCard(entry.namePrefix ?? '')};${escapeVCard(entry.nameSuffix ?? '')}`,
  );
  if (entry.nickname !== undefined) lines.push(`NICKNAME:${escapeVCard(entry.nickname)}`);

  const phonetic = [entry.phoneticLastName, entry.phoneticFirstName, entry.phoneticMiddleName]
    .filter((part: string | undefined): boolean => part !== undefined && part.length > 0)
    .join(' ');
  if (phonetic.length > 0) lines.push(`SORT-STRING:${escapeVCard(phonetic)}`);

  entry.phoneNumbers?.forEach((phone: ExpoPhoneRecord): void => {
    if (phone.number !== undefined) lines.push(`TEL;TYPE=${phoneVCardType(phone.label)}:${escapeVCard(phone.number)}`);
  });

  entry.emails?.forEach((email: ExpoEmailRecord): void => {
    if (email.email !== undefined) lines.push(`EMAIL;TYPE=${emailVCardType(email.label)}:${escapeVCard(email.email)}`);
  });

  entry.addresses?.forEach((address: ExpoAddressRecord): void => {
    lines.push(
      `ADR;TYPE=${addressVCardType(address.label)}:${escapeVCard(address.poBox ?? '')};;${escapeVCard(address.street ?? '')};${escapeVCard(address.city ?? '')};${escapeVCard(address.region ?? '')};${escapeVCard(address.postalCode ?? '')};${escapeVCard(address.country ?? '')}`,
    );
  });

  if (entry.company !== undefined) lines.push(`ORG:${escapeVCard(entry.company)}`);
  if (entry.jobTitle !== undefined) lines.push(`TITLE:${escapeVCard(entry.jobTitle)}`);
  if (entry.note !== undefined) lines.push(`NOTE:${escapeVCard(entry.note)}`);
  if (entry.birthday !== undefined) lines.push(`BDAY:${vCardDate(entry.birthday)}`);

  entry.urlAddresses?.forEach((address: ExpoUrlRecord): void => {
    const uri = safeVCardUri(address.url);
    if (uri !== undefined) lines.push(`URL:${uri}`);
  });

  if (photo) lines.push(`PHOTO;ENCODING=b;TYPE=JPEG:${photo}`);

  lines.push('END:VCARD');

  return lines.map((line: string): string => foldVCardLine(line)).join(VCARD_LINE_BREAK);
}

function escapeVCard(value: string): string {
  return value
    .replace(/\\/g, '\\\\')
    .replace(/\r\n|\r|\n/g, '\\n')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,');
}

function phoneVCardType(value: string): string {
  const label = value.toLowerCase();
  if (label === 'home') return 'HOME';
  if (label === 'work') return 'WORK';
  if (label === 'mobile' || label === 'cell') return 'CELL';
  if (label === 'workmobile') return 'WORK,CELL';
  if (label === 'faxwork') return 'WORK,FAX';
  if (label === 'faxhome') return 'HOME,FAX';
  if (label === 'fax' || label === 'otherfax') return 'FAX';
  if (label === 'pager') return 'PAGER';
  if (label === 'workpager') return 'WORK,PAGER';
  if (label === 'video') return 'VIDEO';
  if (label === 'car') return 'CAR';
  if (label === 'isdn') return 'ISDN';
  if (label === 'main') return 'VOICE';
  if (label === 'companymain') return 'WORK,VOICE';
  if (label === 'callback' || label === 'radio' || label === 'assistant') return 'VOICE';
  if (label === 'telex' || label === 'ttytdd') return 'MSG';
  if (label === 'mms') return 'CELL';
  return 'X-OTHER';
}

function emailVCardType(value: string): string {
  const label = value.toLowerCase();
  if (label === 'home') return 'INTERNET,HOME';
  if (label === 'work') return 'INTERNET,WORK';
  return 'INTERNET';
}

function addressVCardType(value: string): string {
  const label = value.toLowerCase();
  if (label === 'home') return 'HOME';
  if (label === 'work') return 'WORK';
  return 'INTL,POSTAL';
}

function safeVCardUri(value?: string): string | undefined {
  return value !== undefined && !/[\r\n]/.test(value) ? value : undefined;
}

function foldVCardLine(value: string): string {
  const encoder = new util.TextEncoder('utf-8');
  const parts: string[] = [];
  let line: string = '';
  let size: number = 0;
  let i: number = 0;

  while (i < value.length) {
    let length = 1;
    const first = value.charCodeAt(i);

    if (first >= 0xd800 && first <= 0xdbff && i + 1 < value.length) {
      const second = value.charCodeAt(i + 1);
      if (second >= 0xdc00 && second <= 0xdfff) length = 2;
    }

    const char = value.slice(i, i + length);
    const octets = encoder.encodeInto(char).byteLength;
    const capacity = parts.length === 0 ? VCARD_MAX_LINE_OCTETS : VCARD_MAX_LINE_OCTETS - 1;

    if (size > 0 && size + octets > capacity) {
      parts.push(line);
      line = '';
      size = 0;
    }

    line += char;
    size += octets;
    i += length;
  }

  parts.push(line);

  return parts.join(`${VCARD_LINE_BREAK} `);
}

function vCardDate(value: ExpoDateRecord): string {
  const month = padDatePart(value.month + 1);
  const day = padDatePart(value.day);

  return value.year === undefined ? `--${month}${day}` : `${padDateYear(value.year)}${month}${day}`;
}
