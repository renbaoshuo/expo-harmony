/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleContext, ExpoModuleDefinition, ExpoModuleError, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { ExpoContactsError } from './ContactsError';
import { CONTACTS_DATA_CAPABILITY, ContactsPermissions, ContactsPermissionResponse } from './ContactsPermissions';
import { ContactsRepository } from './ContactsRepository';
import { ContactQuery, ContactResponse, ExpoContactRecord, ExpoContainerRecord, ExpoGroupRecord } from './ContactsRecords';
import { readContactQuery, requireRecord } from './ContactsValidation';
import { ExpoContactsService } from './ExpoContactsService';
import { ContactsPresentation } from './ContactsPresentation';

const PERMISSION_DENIED: number = 201;
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
  private readonly presentation: ContactsPresentation;

  constructor(context: ExpoModuleContext) {
    super(context);

    const service = context.services.require(ExpoContactsService.key);
    this.permissions = service.createPermissions(context);
    this.repository = service.createRepository(context, this.permissions);
    this.presentation = new ContactsPresentation(context, this.repository, service);
  }

  definition(): ExpoModuleDefinition {
    const module = new ExpoModuleDefinition()
      .name('ExpoContacts')
      .onDestroy((): void => this.presentation.dispose())
      .events([CHANGE_EVENT])
      .onStartObserving(CHANGE_EVENT, (): void => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'Contacts Kit does not expose contact-store change notifications.');
      })
      .asyncFunction('getPermissionsAsync', async (): Promise<ContactsPermissionResponse> => this.permissions.get())
      .asyncFunction('requestPermissionsAsync', async (): Promise<ContactsPermissionResponse> => await this.permissions.request())
      .asyncFunction('presentAccessPickerAsync', async (): Promise<void> => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'Limited contact access is only available on iOS.');
      })
      .asyncFunction(
        'presentContactPickerAsync',
        async (): Promise<ExpoContactRecord | null> =>
          await this.run(async (): Promise<ExpoContactRecord | null> => {
            return await this.presentation.presentPicker();
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
            await this.run(async (): Promise<void> => { await this.presentation.presentForm(id, record, options); });
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
          async (record: Record<string, ESObject>, container: string | null | undefined): Promise<string> =>
            await this.run(async (): Promise<string> => await this.repository.add(record, container)),
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
            await this.run(async (): Promise<void> => await this.presentation.shareContact(id, message)),
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
          async (id: string, group: string): Promise<void> =>
            await this.run(async (): Promise<void> => await this.repository.changeGroupMembership(id, group, true)),
        ),
      )
      .asyncFunction(
        'removeContactFromGroupAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          ExpoValueTypes.string(),
          async (id: string, group: string): Promise<void> =>
            await this.run(async (): Promise<void> => await this.repository.changeGroupMembership(id, group, false)),
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

}
