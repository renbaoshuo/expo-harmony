import {
  ExpoFunction,
  ExpoModuleContext,
  ExpoSharedObject,
  ExpoSharedObjectClassDefinition,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { contact } from '@kit.ContactsKit';
import { ExpoContactsError } from './ContactsError';
import { ContactsRepository, pageNextContacts } from './ContactsRepository';
import { ExpoContainerRecord, ExpoGroupRecord } from './ContactsRecords';
import { nextQuery, optionalInputString, requireRecord, requireString } from './ContactsValidation';
import type { NextContactObject } from './ExpoContactsNextModule';

const OPTIONAL_STRING = ExpoValueTypes.string().nullable().optional();
const OPTIONAL_QUERY = ExpoValueTypes.custom<Record<string, ESObject>>(
  'contact query options',
  (value: ESObject): Record<string, ESObject> => requireRecord(value, 'contact query options'),
  (value: Record<string, ESObject>): ESObject => value,
).nullable().optional();

export class NextGroupObject extends ExpoSharedObject {
  readonly id: string;

  constructor(context: ExpoModuleContext, id: string) {
    super(context);
    this.id = requireString(id, 'group.id');
  }
}

export class NextContainerObject extends ExpoSharedObject {
  readonly id: string;

  constructor(context: ExpoModuleContext, id: string) {
    super(context);
    this.id = requireString(id, 'container.id');
  }
}

async function selectMembers(
  repository: ContactsRepository,
  options: Record<string, ESObject> | null | undefined,
  groupId?: string,
  containerId?: string,
): Promise<contact.Contact[]> {
  const query = nextQuery(options);
  query.groupId = groupId;
  query.containerId = containerId;
  return pageNextContacts(await repository.select(query), query);
}

export class NextGroupClasses {
  readonly groups: ExpoSharedObjectClassDefinition<NextGroupObject>;
  readonly containers: ExpoSharedObjectClassDefinition<NextContainerObject>;

  constructor(
    context: ExpoModuleContext,
    repository: ContactsRepository,
    contacts: ExpoSharedObjectClassDefinition<NextContactObject>,
    makeContact: (entry: contact.Contact) => NextContactObject,
  ) {
    const groups = new ExpoSharedObjectClassDefinition<NextGroupObject>('Group');
    const containers = new ExpoSharedObjectClassDefinition<NextContainerObject>('Container');
    this.groups = groups;
    this.containers = containers;
    const groupType = groups.valueType();
    const containerType = containers.valueType();
    const contactType = contacts.valueType();
    const makeGroup = (record: ExpoGroupRecord): NextGroupObject =>
      groups.instance(new NextGroupObject(context, requireString(record.id, 'group.id')));
    const makeContainer = (record: ExpoContainerRecord): NextContainerObject =>
      containers.instance(new NextContainerObject(context, record.id));

    groups
      .construct(ExpoFunction.ownedTyped1(
        ExpoValueTypes.string(),
        (owner: ExpoModuleContext, id: string): NextGroupObject => new NextGroupObject(owner, id),
      ))
      .property('id', ExpoValueTypes.string(), (group: NextGroupObject): string => group.id)
      .asyncFunction('getName', ExpoFunction.ownedTyped0(async (group: NextGroupObject): Promise<string | null> => {
        const records = await repository.getGroups({ 'groupId': group.id });
        return records[0]?.name ?? null;
      }).returns(ExpoValueTypes.string().nullable()))
      .asyncFunction('setName', ExpoFunction.ownedTyped1(
        ExpoValueTypes.string(),
        async (_group: NextGroupObject, _name: string): Promise<void> => {
          throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose renaming contact groups.');
        },
      ))
      .asyncFunction('addContact', ExpoFunction.ownedTyped1(
        contactType,
        async (group: NextGroupObject, entry: NextContactObject): Promise<void> => repository.changeGroupMembership(entry.id, group.id, true),
      ))
      .asyncFunction('removeContact', ExpoFunction.ownedTyped1(
        contactType,
        async (group: NextGroupObject, entry: NextContactObject): Promise<void> => repository.changeGroupMembership(entry.id, group.id, false),
      ))
      .asyncFunction('getContacts', ExpoFunction.ownedTyped1(
        OPTIONAL_QUERY,
        async (group: NextGroupObject, options?: Record<string, ESObject> | null): Promise<NextContactObject[]> =>
          (await selectMembers(repository, options, group.id)).map(makeContact),
      ).returns(ExpoValueTypes.array(contactType)))
      .asyncFunction('delete', ExpoFunction.ownedTyped0(
        async (_group: NextGroupObject): Promise<void> => {
          throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose deleting contact groups.');
        },
      ))
      .staticAsyncFunction('create', ExpoFunction.ownedTyped2(
        ExpoValueTypes.string(),
        OPTIONAL_STRING,
        async (_owner: ExpoModuleContext, _name: string, _containerId?: string | null): Promise<NextGroupObject> => {
          throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose creating contact groups.');
        },
      ).returns(groupType))
      .staticAsyncFunction('getAll', ExpoFunction.ownedTyped1(
        OPTIONAL_STRING,
        async (_owner: ExpoModuleContext, containerId?: string | null): Promise<NextGroupObject[]> =>
          (await repository.getGroups({ 'containerId': optionalInputString(containerId, 'containerId') })).map(makeGroup),
      ).returns(ExpoValueTypes.array(groupType)));

    containers
      .construct(ExpoFunction.ownedTyped1(
        ExpoValueTypes.string(),
        (owner: ExpoModuleContext, id: string): NextContainerObject => new NextContainerObject(owner, id),
      ))
      .property('id', ExpoValueTypes.string(), (container: NextContainerObject): string => container.id)
      .asyncFunction('getName', ExpoFunction.ownedTyped0(async (container: NextContainerObject): Promise<string | null> => {
        const records = await repository.getContainers({ 'containerId': container.id });
        return records[0]?.name ?? null;
      }).returns(ExpoValueTypes.string().nullable()))
      .asyncFunction('getType', ExpoFunction.ownedTyped0(async (container: NextContainerObject): Promise<string> => {
        await repository.getContainers({ 'containerId': container.id });
        return 'unknown';
      }).returns(ExpoValueTypes.string()))
      .asyncFunction('getGroups', ExpoFunction.ownedTyped0(
        async (container: NextContainerObject): Promise<NextGroupObject[]> =>
          (await repository.getGroups({ 'containerId': container.id })).map(makeGroup),
      ).returns(ExpoValueTypes.array(groupType)))
      .asyncFunction('getContacts', ExpoFunction.ownedTyped1(
        OPTIONAL_QUERY,
        async (container: NextContainerObject, options?: Record<string, ESObject> | null): Promise<NextContactObject[]> =>
          (await selectMembers(repository, options, undefined, container.id)).map(makeContact),
      ).returns(ExpoValueTypes.array(contactType)))
      .staticAsyncFunction('getAll', ExpoFunction.ownedTyped0(
        async (_owner: ExpoModuleContext): Promise<NextContainerObject[]> => (await repository.getContainers()).map(makeContainer),
      ).returns(ExpoValueTypes.array(containerType)))
      .staticAsyncFunction('getDefault', ExpoFunction.ownedTyped0(async (_owner: ExpoModuleContext): Promise<NextContainerObject | null> => {
        throw new ExpoContactsError('ERR_CONTACTS_UNSUPPORTED', 'HarmonyOS Contacts Kit does not expose the default contact container.');
      }).returns(containerType.nullable()));
  }
}
