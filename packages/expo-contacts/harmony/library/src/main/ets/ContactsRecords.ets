export type ContactType = 'person' | 'company';

export interface ContactQuery {
  pageSize: number;
  pageOffset: number;
  fields?: string[];
  sort?: string;
  name?: string;
  ids?: string[];
  groupId?: string;
  containerId?: string;
}

export class ExpoDateRecord {
  day: number;
  month: number;
  year?: number;
  label?: string;
  format: string = 'gregorian';

  constructor(day: number, month: number) {
    this.day = day;
    this.month = month;
  }
}

export class ExpoEmailRecord {
  email?: string;
  label: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class ExpoPhoneRecord {
  number?: string;
  digits?: string;
  label: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class ExpoAddressRecord {
  street?: string;
  city?: string;
  country?: string;
  region?: string;
  neighborhood?: string;
  postalCode?: string;
  poBox?: string;
  label: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class ExpoRelationshipRecord {
  label: string;
  name?: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class ExpoInstantMessageRecord {
  username?: string;
  service?: string;
  label: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class ExpoUrlRecord {
  label: string;
  url?: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class ExpoImageRecord {
  uri?: string;
  width?: number;
  height?: number;
}

export class ExpoContactRecord {
  id: string;
  contactType: ContactType;
  name: string;
  firstName?: string;
  middleName?: string;
  lastName?: string;
  namePrefix?: string;
  nameSuffix?: string;
  nickname?: string;
  phoneticFirstName?: string;
  phoneticMiddleName?: string;
  phoneticLastName?: string;
  company?: string;
  jobTitle?: string;
  note?: string;
  imageAvailable?: boolean;
  image?: ExpoImageRecord;
  rawImage?: ExpoImageRecord;
  birthday?: ExpoDateRecord;
  dates?: ExpoDateRecord[];
  relationships?: ExpoRelationshipRecord[];
  emails?: ExpoEmailRecord[];
  phoneNumbers?: ExpoPhoneRecord[];
  addresses?: ExpoAddressRecord[];
  instantMessageAddresses?: ExpoInstantMessageRecord[];
  urlAddresses?: ExpoUrlRecord[];

  constructor(id: string, contactType: ContactType, name: string) {
    this.id = id;
    this.contactType = contactType;
    this.name = name;
  }
}

export class ContactResponse {
  data: ExpoContactRecord[];
  hasNextPage: boolean;
  hasPreviousPage: boolean;

  constructor(data: ExpoContactRecord[], hasNextPage: boolean, hasPreviousPage: boolean) {
    this.data = data;
    this.hasNextPage = hasNextPage;
    this.hasPreviousPage = hasPreviousPage;
  }
}

export class ExpoGroupRecord {
  id?: string;
  name?: string;
}

export class ExpoContainerRecord {
  id: string;
  name: string;
  type: string = 'unassigned';

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

export class RequestedFields {
  private readonly all: boolean;
  private readonly values: Set<string> = new Set<string>();

  constructor(fields?: string[]) {
    this.all = fields === undefined;
    fields?.forEach((field: string): void => {
      this.values.add(field);
    });
  }

  has(field: string): boolean {
    return this.all || this.values.has(field);
  }
}
