import { ExpoModuleContext, ExpoService, ExpoServiceContext, ExpoServiceKey } from '@expo-harmony/expo-modules-core';
import { ContactsPermissions } from './ContactsPermissions';
import { ContactsRepository } from './ContactsRepository';
import { ExpoContactsError } from './ContactsError';

export class ExpoContactsService extends ExpoService {
  static readonly key = new ExpoServiceKey<ExpoContactsService>('ExpoContactsService');
  readonly identity = ExpoContactsService.key.bind(this);
  private permissions?: ContactsPermissions;
  private repository?: ContactsRepository;
  private presenter?: Object;

  constructor(context?: ExpoServiceContext) {
    super(context);
  }

  getPermissions(context: ExpoModuleContext): ContactsPermissions {
    if (this.permissions === undefined) this.permissions = new ContactsPermissions(context);
    return this.permissions;
  }

  getRepository(context: ExpoModuleContext): ContactsRepository {
    if (this.repository === undefined) this.repository = new ContactsRepository(context, this.getPermissions(context));
    return this.repository;
  }

  beginUi(owner: Object): void {
    if (this.presenter !== undefined) throw new ExpoContactsError('ERR_CONTACTS_UI_IN_PROGRESS', 'A contacts picker, form, or share operation is already in progress.');
    this.presenter = owner;
  }

  endUi(owner: Object): void {
    if (this.presenter === owner) this.presenter = undefined;
  }
}
