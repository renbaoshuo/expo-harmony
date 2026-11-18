import { ExpoModuleContext, ExpoService, ExpoServiceContext, ExpoServiceKey } from '@expo-harmony/expo-modules-core';
import { ContactsPermissions } from './ContactsPermissions';
import { ContactsRepository } from './ContactsRepository';
import { ExpoContactsError } from './ContactsError';

export class ExpoContactsService extends ExpoService {
  static readonly key = new ExpoServiceKey<ExpoContactsService>('ExpoContactsService');
  readonly identity = ExpoContactsService.key.bind(this);
  private writes: Promise<void> = Promise.resolve();
  private permissionRequests: Promise<void> = Promise.resolve();
  private presenting: boolean = false;

  constructor(context?: ExpoServiceContext) {
    super(context);
  }

  createPermissions(context: ExpoModuleContext): ContactsPermissions {
    return new ContactsPermissions(context, this);
  }

  createRepository(context: ExpoModuleContext, permissions: ContactsPermissions): ContactsRepository {
    return new ContactsRepository(context, permissions, this);
  }

  runWrite<Result>(operation: () => Promise<Result>): Promise<Result> {
    const result = this.writes.then(operation);
    this.writes = result.then((): void => {}, (): void => {});
    return result;
  }

  runPermissionRequest<Result>(operation: () => Promise<Result>): Promise<Result> {
    const result = this.permissionRequests.then(operation);
    this.permissionRequests = result.then((): void => {}, (): void => {});
    return result;
  }

  async present<Result>(operation: () => Promise<Result>): Promise<Result> {
    if (this.presenting) throw new ExpoContactsError('ERR_CONTACTS_UI_IN_PROGRESS', 'A contacts picker, form, or share operation is already in progress.');

    this.presenting = true;

    try {
      return await operation();
    } finally {
      this.presenting = false;
    }
  }
}
