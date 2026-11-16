/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { contact } from '@kit.ContactsKit';
import { contact as vCardContact, VCardBuilder, VCardConfig } from '@ohos/vcard';
import { isBirthdayEvent, nativeDisplayName, parseContactDate } from './ContactsMapper';

export function serializeContactVCard(entry: contact.Contact, photo: string): string {
  const card = new vCardContact.Contact();

  const name = new vCardContact.Name();
  name.fullName = nativeDisplayName(entry);
  name.givenName = entry.name?.givenName ?? null;
  name.middleName = entry.name?.middleName ?? null;
  name.familyName = entry.name?.familyName ?? null;
  name.namePrefix = entry.name?.namePrefix ?? null;
  name.nameSuffix = entry.name?.nameSuffix ?? null;
  name.givenNamePhonetic = entry.name?.givenNamePhonetic ?? null;
  name.middleNamePhonetic = entry.name?.middleNamePhonetic ?? null;
  name.familyNamePhonetic = entry.name?.familyNamePhonetic ?? null;
  card.name = name;

  // These Contacts Kit records share their data fields with the builder, which
  // reads them as values. Event and relation records use class checks below.
  card.nickName = (entry.nickName ?? null) as ESObject as vCardContact.NickName | null;
  card.emails = (entry.emails ?? null) as ESObject as vCardContact.Email[] | null;
  card.imAddresses = (entry.imAddresses ?? null) as ESObject as vCardContact.ImAddress[] | null;
  card.websites = (entry.websites ?? null) as ESObject as vCardContact.Website[] | null;
  card.organization = (entry.organization ?? null) as ESObject as vCardContact.Organization | null;
  card.note = (entry.note ?? null) as ESObject as vCardContact.Note | null;

  card.postalAddresses = (entry.postalAddresses ?? []).map((address: contact.PostalAddress): vCardContact.PostalAddress => {
    const postal = new vCardContact.PostalAddress();
    postal.street = address.street || address.postalAddress;
    postal.city = address.city ?? null;
    postal.country = address.country ?? null;
    postal.region = address.region ?? null;
    postal.neighborhood = address.neighborhood ?? null;
    postal.postcode = address.postcode ?? null;
    postal.pobox = address.pobox ?? null;
    postal.labelId = address.labelId ?? null;
    postal.labelName = address.labelName ?? null;

    return postal;
  });

  card.events = (entry.events ?? []).filter((event: contact.Event): boolean => parseContactDate(event.eventDate) !== undefined)
    .map((event: contact.Event): vCardContact.Event => {
      const row = new vCardContact.Event();
      row.eventDate = event.eventDate;
      row.labelId = isBirthdayEvent(event) ? vCardContact.Event.EVENT_BIRTHDAY : event.labelId ?? null;

      return row;
    });

  card.relations = (entry.relations ?? []).map((relation: contact.Relation): vCardContact.Relation => {
    const row = new vCardContact.Relation();
    row.relationName = relation.relationName;
    row.labelId = relation.labelId ?? null;

    return row;
  });

  const builder = new VCardBuilder(VCardConfig.VCARD_TYPE_V30_GENERIC, 'UTF-8');
  builder.appendNameProperties(card).appendNickNames(card);

  for (const phone of entry.phoneNumbers ?? []) {
    // The builder does not escape newlines in phone numbers.
    const number = phone.phoneNumber.replace(/[\r\n]+/g, ' ').trim();
    if (number.length > 0) builder.appendTelLine(phone.labelId ?? null, phone.labelName ?? '', number, false);
  }

  builder.appendEmails(card).appendPostals(card).appendOrganizations(card).appendWebsites(card)
    .appendNotes(card).appendEvents(card).appendRelation(card).appendIms(card);
  if (photo.length > 0) builder.appendPhotoLine(photo, 'JPEG');

  return builder.toString();
}
