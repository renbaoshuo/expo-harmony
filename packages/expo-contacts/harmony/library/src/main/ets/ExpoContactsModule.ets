import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { contact } from '@kit.ContactsKit';
import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { fileUri } from '@kit.CoreFileKit';
import { ExpoContactsError } from './ContactsError';
import { ContactsPermissions, ContactsPermissionResponse } from './ContactsPermissions';
import { ContactsRepository, validateWritableContact } from './ContactsRepository';
import { ContactQuery, ContactResponse, ExpoContactRecord, ExpoContainerRecord, ExpoGroupRecord, RequestedFields } from './ContactsRecords';
import { nativeContactFromExpo } from './ContactsMapper';
import { readContactQuery, requireRecord } from './ContactsValidation';

const CONTACT_FORM_API: number = 15;
const USER_CANCELLED: number = 16700103;
const PERMISSION_DENIED: number = 201;
const CONTACTS_UI_CAPABILITY: string = 'SystemCapability.Applications.Contacts';
const CONTACTS_DATA_CAPABILITY: string = 'SystemCapability.Applications.ContactsData';
const SHARE_CAPABILITY: string = 'SystemCapability.Collaboration.SystemShare';
const CHANGE_EVENT: string = 'onContactsChange';

const CONTACT_RECORD = ExpoValueTypes.custom<Record<string, ESObject>>(
  'contact record',
  (value: ESObject): Record<string, ESObject> => requireRecord(value, 'contact record'),
  (value: Record<string, ESObject>): ESObject => value,
);
const CONTACT_QUERY = ExpoValueTypes.custom<ContactQuery>(
  'ContactQuery',
  (value: ESObject): ContactQuery => readContactQuery(value),
  (value: ContactQuery): ESObject => value,
).defaulted(readContactQuery(undefined));
const OPTIONAL_RECORD = CONTACT_RECORD.nullable().optional();
const OPTIONAL_STRING = ExpoValueTypes.string().nullable().optional();

export class ExpoContactsModule extends ExpoModule {
  private readonly permissions: ContactsPermissions;
  private readonly repository: ContactsRepository;
  private static activeUi?: ExpoContactsModule;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.permissions = new ContactsPermissions(context);
    this.repository = new ContactsRepository(context, this.permissions);
  }

  definition(): ExpoModuleDefinition {
    const module = new ExpoModuleDefinition()
      .name('ExpoContacts')
      .events([CHANGE_EVENT])
      .onStartObserving(CHANGE_EVENT, (): void => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'Contacts Kit does not expose contact-store change notifications.');
      })
      .onDestroy((): void => {
        if (ExpoContactsModule.activeUi === this) ExpoContactsModule.activeUi = undefined;
      })
      .asyncFunction('getPermissionsAsync', async (): Promise<ContactsPermissionResponse> => await this.permissions.get())
      .asyncFunction('requestPermissionsAsync', async (): Promise<ContactsPermissionResponse> => await this.permissions.request())
      .asyncFunction('presentAccessPickerAsync', async (): Promise<void> => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'Limited contact access is only available on iOS.');
      })
      .asyncFunction(
        'presentContactPickerAsync',
        async (): Promise<ExpoContactRecord | null> =>
          await this.run(async (): Promise<ExpoContactRecord | null> => {
            return await this.presentPicker();
          }),
      )
      .asyncFunction(
        'presentFormAsync',
        ExpoFunction.typed3(
          OPTIONAL_STRING,
          OPTIONAL_RECORD,
          OPTIONAL_RECORD,
          async (
            id: string | null | undefined,
            record: Record<string, ESObject> | null | undefined,
            options: Record<string, ESObject> | null | undefined,
          ): Promise<void> => {
            await this.run(async (): Promise<void> => await this.presentForm(id, record, options));
          },
        ),
      );

    if (!canIUse(CONTACTS_DATA_CAPABILITY)) return module;

    return module
      .asyncFunction(
        'getContactsAsync',
        ExpoFunction.typed1(
          CONTACT_QUERY,
          async (query: ContactQuery): Promise<ContactResponse> =>
            await this.run(async (): Promise<ContactResponse> => await this.repository.getContacts(query)),
        ),
      )
      .asyncFunction(
        'hasContactsAsync',
        async (): Promise<boolean> => await this.run(async (): Promise<boolean> => await this.repository.hasContacts()),
      )
      .asyncFunction(
        'addContactAsync',
        ExpoFunction.typed2(
          CONTACT_RECORD,
          OPTIONAL_STRING,
          async (record: Record<string, ESObject>, containerId: string | null | undefined): Promise<string> =>
            await this.run(async (): Promise<string> => await this.repository.add(record, containerId)),
        ),
      )
      .asyncFunction(
        'updateContactAsync',
        ExpoFunction.typed1(
          CONTACT_RECORD,
          async (record: Record<string, ESObject>): Promise<string> =>
            await this.run(async (): Promise<string> => await this.repository.update(record)),
        ),
      )
      .asyncFunction(
        'removeContactAsync',
        ExpoFunction.typed1(
          ExpoValueTypes.string(),
          async (id: string): Promise<void> => await this.run(async (): Promise<void> => await this.repository.remove(id)),
        ),
      )
      .asyncFunction(
        'writeContactToFileAsync',
        ExpoFunction.typed1(
          CONTACT_QUERY,
          async (query: ContactQuery): Promise<string | undefined> =>
            await this.run(async (): Promise<string | undefined> => await this.repository.writeVCard(query)),
        ),
      )
      .asyncFunction(
        'shareContactAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          OPTIONAL_STRING,
          async (id: string, message: string | null | undefined): Promise<void> =>
            await this.run(async (): Promise<void> => await this.shareContact(id, message)),
        ),
      )
      .asyncFunction(
        'getGroupsAsync',
        ExpoFunction.typed1(
          OPTIONAL_RECORD,
          async (query: Record<string, ESObject> | null | undefined): Promise<ExpoGroupRecord[]> =>
            await this.run(async (): Promise<ExpoGroupRecord[]> => await this.repository.getGroups(query)),
        ),
      )
      .asyncFunction(
        'getContainersAsync',
        ExpoFunction.typed1(
          OPTIONAL_RECORD,
          async (query: Record<string, ESObject> | null | undefined): Promise<ExpoContainerRecord[]> =>
            await this.run(async (): Promise<ExpoContainerRecord[]> => await this.repository.getContainers(query)),
        ),
      )
      .asyncFunction(
        'addExistingContactToGroupAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          async (id: string, groupId: string): Promise<void> =>
            await this.run(async (): Promise<void> => await this.repository.changeGroupMembership(id, groupId, true)),
        ),
      )
      .asyncFunction(
        'removeContactFromGroupAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          async (id: string, groupId: string): Promise<void> =>
            await this.run(async (): Promise<void> => await this.repository.changeGroupMembership(id, groupId, false)),
        ),
      );
  }

  private async run<Result>(operation: () => Promise<Result>): Promise<Result> {
    try {
      this.ensureActive();

      const result = await operation();
      this.ensureActive();

      return result;
    } catch (error) {
      if (error instanceof ExpoModuleError) throw new ExpoContactsError(error.code, error.message, error);

      const native = error as BusinessError;
      if (native.code === PERMISSION_DENIED) {
        throw new ExpoContactsError('ERR_CONTACTS_MISSING_PERMISSION', 'The required contacts permission has not been granted.');
      }

      throw new ExpoContactsError(
        'ERR_CONTACTS_OPERATION',
        native.message ?? 'Unable to complete the HarmonyOS contacts operation.',
        error as Object,
      );
    }
  }

  private ensureActive(): void {
    if (!this.context.isValid) throw new ExpoContactsError('ERR_CONTACTS_DESTROYED', 'The contacts module has been destroyed.');
  }

  private beginUi(): void {
    this.ensureActive();
    if (ExpoContactsModule.activeUi !== undefined) {
      throw new ExpoContactsError('ERR_CONTACTS_UI_IN_PROGRESS', 'A contacts picker, form, or share operation is already in progress.');
    }

    ExpoContactsModule.activeUi = this;
  }

  private endUi(): void {
    if (ExpoContactsModule.activeUi === this) ExpoContactsModule.activeUi = undefined;
  }

  private async presentPicker(): Promise<ExpoContactRecord | null> {
    if (!canIUse(CONTACTS_UI_CAPABILITY))
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'The contact picker is unavailable on this device.');

    this.beginUi();

    try {
      const options: contact.ContactSelectionOptions = { isMultiSelect: false };
      if (deviceInfo.sdkApiVersion >= CONTACT_FORM_API) options.isDisplayedByName = true;

      const selected = await contact.selectContacts(options);
      this.ensureActive();
      if (selected.length === 0) return null;

      // The picker grants access to its result; it does not grant READ_CONTACTS.
      return await this.repository.serialize(selected[0], new RequestedFields());
    } catch (error) {
      if ((error as BusinessError).code === USER_CANCELLED) return null;
      if (error instanceof ExpoModuleError) throw new ExpoContactsError(error.code, error.message, error);
      throw new ExpoContactsError('ERR_CONTACTS_PICKER', 'Unable to present the HarmonyOS contact picker.', error as Object);
    } finally {
      this.endUi();
    }
  }

  private async presentForm(id?: string | null, record?: Record<string, ESObject> | null, options?: Record<string, ESObject> | null): Promise<void> {
    if (!canIUse(CONTACTS_UI_CAPABILITY) || deviceInfo.sdkApiVersion < CONTACT_FORM_API) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'The contact form requires HarmonyOS API 15 or later.');
    }
    if (id !== undefined && id !== null)
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS has no public form for viewing or editing a specified contact.');
    if (options !== undefined && options !== null && Object.keys(options).length > 0) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS cannot customize the system contact form.');
    }

    const data: Record<string, ESObject> = record ?? {};
    validateWritableContact(data);
    if (data['image'] !== undefined && data['image'] !== null) {
      throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'The HarmonyOS system form cannot prefill a contact image.');
    }

    this.beginUi();

    try {
      const value = nativeContactFromExpo(data);
      // Contacts Kit rejects an empty Contact; an empty Name opens a blank form.
      if (Object.keys(value).length === 0) value.name = { fullName: '' };

      await contact.addContactViaUI(this.context.uiAbilityContext, value);
    } catch (error) {
      if ((error as BusinessError).code !== USER_CANCELLED) {
        if (error instanceof ExpoModuleError) throw new ExpoContactsError(error.code, error.message, error);
        throw new ExpoContactsError('ERR_CONTACTS_FORM', 'Unable to present the HarmonyOS contact form.', error as Object);
      }
    } finally {
      this.endUi();
    }
  }

  private async shareContact(id: string, message?: string | null): Promise<void> {
    if (!canIUse(SHARE_CAPABILITY)) throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'System sharing is unavailable on this device.');

    this.beginUi();

    try {
      const uri = await this.repository.writeVCard(readContactQuery({ id }));
      if (uri === undefined) throw new ExpoContactsError('ERR_CONTACTS_NOT_FOUND', `No contact exists for identifier '${id}'.`);

      this.ensureActive();

      // JS consumes standard file URLs; system sharing needs an app-scoped URI.
      const path = decodeURIComponent(new fileUri.FileUri(uri).path);
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.VCARD,
        uri: fileUri.getUriFromPath(path),
        title: message ?? undefined,
      };
      const controller = new systemShare.ShareController(new systemShare.SharedData(record));

      await controller.show(this.context.uiAbilityContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT,
      });
    } finally {
      this.endUi();
    }
  }
}
