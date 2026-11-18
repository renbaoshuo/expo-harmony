/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoAppLifecycleState, ExpoModuleContext, ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { contact } from '@kit.ContactsKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { fileUri } from '@kit.CoreFileKit';
import { ExpoContactsError } from './ContactsError';
import { ContactsRepository, validateWritableContact } from './ContactsRepository';
import { ExpoContactRecord, RequestedFields } from './ContactsRecords';
import { nativeContactFromExpo } from './ContactsMapper';
import { readContactQuery } from './ContactsValidation';
import type { ExpoContactsService } from './ExpoContactsService';

const CONTACT_FORM_API: number = 15;
const USER_CANCELLED: number = 16700103;
const CONTACTS_UI_CAPABILITY: string = 'SystemCapability.Applications.Contacts';
const SHARE_CAPABILITY: string = 'SystemCapability.Collaboration.SystemShare';

export class ContactsPresentation {
  private readonly context: ExpoModuleContext;
  private readonly repository: ContactsRepository;
  private readonly service: ExpoContactsService;
  private finishShare?: () => void;

  constructor(context: ExpoModuleContext, repository: ContactsRepository, service: ExpoContactsService) {
    this.context = context;
    this.repository = repository;
    this.service = service;
  }

  dispose(): void {
    this.finishShare?.();
  }

  private ensureForeground(): void {
    this.context.assertActive();

    if (this.context.isHeadless || this.context.appLifecycleState !== ExpoAppLifecycleState.FOREGROUND) {
      throw new ExpoContactsError('ERR_CONTACTS_UI_UNAVAILABLE', 'Contacts UI requires a foreground UIAbility.');
    }
  }

  async presentPicker(): Promise<ExpoContactRecord | null> {
    const entry = await this.presentNativePicker();

    return entry === null ? null : await this.repository.serialize(entry, new RequestedFields());
  }

  async presentNativePicker(): Promise<contact.Contact | null> {
    if (!canIUse(CONTACTS_UI_CAPABILITY)) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'The contact picker is unavailable on this device.');
    }

    this.ensureForeground();

    return await this.service.present(async (): Promise<contact.Contact | null> => {
      try {
        const options: contact.ContactSelectionOptions = { isMultiSelect: false };
        if (deviceInfo.sdkApiVersion >= CONTACT_FORM_API) options.isDisplayedByName = true;

        const entries = await contact.selectContacts(options);
        this.context.assertActive();

        return entries.length === 0 ? null : entries[0];
      } catch (error) {
        if ((error as BusinessError).code === USER_CANCELLED) {
          this.context.assertActive();
          return null;
        }

        if (error instanceof ExpoModuleError) throw new ExpoContactsError(error.code, error.message, error);

        throw new ExpoContactsError('ERR_CONTACTS_PICKER', 'Unable to present the HarmonyOS contact picker.', error as Object);
      }
    });
  }

  async presentForm(id?: string | null, record?: Record<string, ESObject> | null, options?: Record<string, ESObject> | null): Promise<boolean> {
    if (!canIUse(CONTACTS_UI_CAPABILITY) || deviceInfo.sdkApiVersion < CONTACT_FORM_API) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'The contact form requires HarmonyOS API 15 or later.');
    }
    if (id !== undefined && id !== null) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS has no public form for viewing or editing a specified contact.');
    }
    if (options !== undefined && options !== null && Object.keys(options).length > 0) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS cannot customize the system contact form.');
    }

    const data: Record<string, ESObject> = record ?? {};
    validateWritableContact(data);
    if (data['image'] !== undefined && data['image'] !== null) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'The HarmonyOS system form cannot prefill a contact image.');
    }

    this.ensureForeground();

    return await this.service.present(async (): Promise<boolean> => {
      try {
        const value = nativeContactFromExpo(data);
        // An empty Name opens a blank form; Contacts Kit rejects an empty Contact.
        if (Object.keys(value).length === 0) value.name = { fullName: '' };

        const key = await contact.addContactViaUI(this.context.uiAbilityContext, value);
        this.context.assertActive();
        if (!Number.isSafeInteger(key) || key < 0) {
          throw new ExpoContactsError('ERR_CONTACTS_FORM', 'HarmonyOS did not return a valid contact ID from the contact form.');
        }

        return true;
      } catch (error) {
        if ((error as BusinessError).code !== USER_CANCELLED) {
          if (error instanceof ExpoModuleError) throw new ExpoContactsError(error.code, error.message, error);
          throw new ExpoContactsError('ERR_CONTACTS_FORM', 'Unable to present the HarmonyOS contact form.', error as Object);
        }

        this.context.assertActive();
        return false;
      }
    });
  }

  async shareContact(id: string, message?: string | null): Promise<void> {
    if (!canIUse(SHARE_CAPABILITY)) throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'System sharing is unavailable on this device.');

    this.ensureForeground();

    await this.service.present(async (): Promise<void> => {
      const uri = await this.repository.writeVCard(readContactQuery({ id }));
      if (uri === undefined) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', `No contact exists for identifier '${id}'.`);

      this.ensureForeground();
      this.repository.ensureReadable();

      // JS consumes standard file URLs; system sharing needs an app-scoped URI.
      const path = this.context.filePathForRead(uri);
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.VCARD,
        uri: fileUri.getUriFromPath(path),
        title: message ?? undefined,
      };
      const controller = new systemShare.ShareController(new systemShare.SharedData(record));

      let dismiss: () => void = (): void => {};
      const closed = new Promise<void>((resolve: () => void): void => {
        dismiss = resolve;
      });

      controller.on('dismiss', dismiss);
      this.finishShare = dismiss;

      try {
        const shown = controller.show(this.context.uiAbilityContext, {
          selectionMode: systemShare.SelectionMode.SINGLE,
          previewMode: systemShare.SharePreviewMode.DEFAULT,
        });

        await Promise.race([closed, shown.then((): Promise<void> => closed)]);
      } finally {
        this.finishShare = undefined;
        controller.off('dismiss', dismiss);
      }
    });
  }
}
