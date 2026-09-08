import { ExpoModuleError, ExpoValueType } from '@expo-harmony/expo-modules-core';
import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export const LOCATION_EVENT: string = 'Expo.locationChanged';
export const HEADING_EVENT: string = 'Expo.headingChanged';
export const ERROR_EVENT: string = 'Expo.locationError';
export const LOCATION_TIMEOUT_MS: number = 10_000;
export const HEADING_INTERVAL_NS: number = 200_000_000;

export enum Accuracy {
  Lowest = 1,
  Low = 2,
  Balanced = 3,
  High = 4,
  Highest = 5,
  BestForNavigation = 6,
}

export enum LocationErrorCode {
  PermissionDenied = 201,
  InvalidArgument = 401,
  Unsupported = 801,
  Unavailable = 3301000,
  SwitchOff = 3301100,
  NoLocation = 3301200,
}

export class LocationOptions {
  accuracy: Accuracy = Accuracy.Balanced;
  timeInterval?: number;
  distanceInterval?: number;
  mayShowUserSettingsDialog: boolean = true;
}

export class LastKnownOptions {
  maxAge?: number;
  requiredAccuracy?: number;
}

export class Coordinate {
  latitude: number;
  longitude: number;

  constructor(latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
  }
}

export function validCoordinate(latitude: number, longitude: number): boolean {
  return Number.isFinite(latitude) && latitude >= -90 && latitude <= 90 && Number.isFinite(longitude) && longitude >= -180 && longitude <= 180;
}

function objectArgument(value: ESObject, name: string): Record<string, ESObject> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', `${name} must be an object.`);
  }

  return value as Record<string, ESObject>;
}

function nonnegative(value: ESObject, name: string): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', `${name} must be a finite nonnegative number.`);
  }

  return value as number;
}

export const TASK_OPTIONS = new ExpoValueType<Record<string, ESObject>>(
  'task options',
  (value: ESObject): Record<string, ESObject> => objectArgument(value, 'options'),
  (value: Record<string, ESObject>): ESObject => value,
);

export const LOCATION_OPTIONS = new ExpoValueType<LocationOptions>(
  'location options',
  (value: ESObject): LocationOptions => {
    const input = objectArgument(value, 'options');
    const result = new LocationOptions();

    if (input.accuracy !== undefined && input.accuracy !== null) {
      const accuracy: ESObject = input.accuracy;
      if (typeof accuracy !== 'number' || !Number.isInteger(accuracy) || accuracy < Accuracy.Lowest || accuracy > Accuracy.BestForNavigation) {
        throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'accuracy must be a Location.Accuracy value (1–6).');
      }
      result.accuracy = accuracy as Accuracy;
    }

    result.timeInterval = nonnegative(input.timeInterval, 'timeInterval');
    result.distanceInterval = nonnegative(input.distanceInterval, 'distanceInterval');
    if (input.mayShowUserSettingsDialog !== undefined && input.mayShowUserSettingsDialog !== null) {
      if (typeof input.mayShowUserSettingsDialog !== 'boolean') {
        throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'mayShowUserSettingsDialog must be a boolean.');
      }
      result.mayShowUserSettingsDialog = input.mayShowUserSettingsDialog as boolean;
    }

    return result;
  },
  (value: LocationOptions): ESObject => value,
);

export const LAST_KNOWN_OPTIONS = new ExpoValueType<LastKnownOptions>(
  'last known location options',
  (value: ESObject): LastKnownOptions => {
    const input = objectArgument(value, 'options');

    const result = new LastKnownOptions();
    result.maxAge = nonnegative(input.maxAge, 'maxAge');
    result.requiredAccuracy = nonnegative(input.requiredAccuracy, 'requiredAccuracy');

    return result;
  },
  (value: LastKnownOptions): ESObject => value,
);

export const COORDINATE = new ExpoValueType<Coordinate>(
  'coordinate',
  (value: ESObject): Coordinate => {
    const input = objectArgument(value, 'location');

    if (typeof input.latitude !== 'number' || typeof input.longitude !== 'number' || !validCoordinate(input.latitude, input.longitude)) {
      throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'latitude and longitude must be finite WGS-84 coordinates.');
    }

    return new Coordinate(input.latitude, input.longitude);
  },
  (value: Coordinate): ESObject => value,
);

export const WATCH_ID = new ExpoValueType<number>(
  'watch ID',
  (value: ESObject): number => {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) {
      throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'watchId must be a nonnegative safe integer.');
    }

    return value as number;
  },
  (value: number): ESObject => value,
);

class LocationCoordinates {
  latitude: number;
  longitude: number;
  altitude: number | null;
  accuracy: number | null;
  altitudeAccuracy: number | null;
  heading: number | null;
  speed: number | null;

  constructor(location: geoLocationManager.Location) {
    this.latitude = location.latitude;
    this.longitude = location.longitude;
    this.altitude = finiteOrNull(location.altitude);
    this.accuracy = nonnegativeOrNull(location.accuracy);
    this.altitudeAccuracy = nonnegativeOrNull(location.altitudeAccuracy);
    this.heading = nonnegativeOrNull(location.direction);
    this.speed = nonnegativeOrNull(location.speed);
  }
}

export class LocationRecord {
  coords: LocationCoordinates;
  timestamp: number;

  constructor(location: geoLocationManager.Location) {
    if (!validCoordinate(location.latitude, location.longitude) || !Number.isFinite(location.timeStamp)) {
      throw new ExpoModuleError('ERR_LOCATION_INVALID_RESPONSE', 'HarmonyOS returned an invalid location.');
    }

    this.coords = new LocationCoordinates(location);
    this.timestamp = location.timeStamp;
  }
}

export class LocationEvent {
  watchId: number;
  location: LocationRecord;

  constructor(watchId: number, location: LocationRecord) {
    this.watchId = watchId;
    this.location = location;
  }
}

export class HeadingRecord {
  magHeading: number;
  trueHeading: number;
  accuracy: number;

  constructor(magHeading: number, trueHeading: number, accuracy: number) {
    this.magHeading = magHeading;
    this.trueHeading = trueHeading;
    this.accuracy = accuracy;
  }
}

export class HeadingEvent {
  watchId: number;
  heading: HeadingRecord;

  constructor(watchId: number, heading: HeadingRecord) {
    this.watchId = watchId;
    this.heading = heading;
  }
}

export class LocationErrorEvent {
  watchId: number;
  reason: string;

  constructor(watchId: number, reason: string) {
    this.watchId = watchId;
    this.reason = reason;
  }
}

export class ProviderStatus {
  backgroundModeEnabled: boolean = false;
  locationServicesEnabled: boolean;

  constructor(locationServicesEnabled: boolean) {
    this.locationServicesEnabled = locationServicesEnabled;
  }
}

export class GeocodedAddress {
  city: string | null;
  district: string | null;
  streetNumber: string | null;
  street: string | null;
  region: string | null;
  subregion: string | null;
  country: string | null;
  postalCode: string | null;
  name: string | null;
  isoCountryCode: string | null;
  timezone: string | null = null;
  formattedAddress: string | null;

  constructor(address: geoLocationManager.GeoAddress) {
    this.city = address.locality ?? null;
    this.district = address.subLocality ?? null;
    this.streetNumber = address.premises ?? null;
    this.street = address.roadName ?? null;
    this.region = address.administrativeArea ?? null;
    this.subregion = address.subAdministrativeArea ?? null;
    this.country = address.countryName ?? null;
    this.postalCode = address.postalCode ?? null;
    this.name = address.placeName ?? null;
    this.isoCountryCode = address.countryCode ?? null;
    this.formattedAddress = address.placeName ?? null;
  }
}

export function locationRequest(options: LocationOptions): geoLocationManager.LocationRequest {
  // Defaults match Android LocationHelpers.buildLocationParamsForAccuracy in Expo 55.1.10.
  let interval: number = 3000;
  let distance: number = 100;
  let priority = geoLocationManager.LocationRequestPriority.LOW_POWER;

  switch (options.accuracy) {
    case Accuracy.Lowest:
      interval = 10_000;
      distance = 3000;
      break;
    case Accuracy.Low:
      interval = 5000;
      distance = 1000;
      break;
    case Accuracy.Balanced:
      break;
    case Accuracy.High:
      interval = 2000;
      distance = 50;
      priority = geoLocationManager.LocationRequestPriority.ACCURACY;
      break;
    case Accuracy.Highest:
      interval = 1000;
      distance = 25;
      priority = geoLocationManager.LocationRequestPriority.ACCURACY;
      break;
    case Accuracy.BestForNavigation:
      interval = 500;
      distance = 0;
      priority = geoLocationManager.LocationRequestPriority.ACCURACY;
      break;
  }

  return {
    priority,
    // A non-UNSET scenario overrides priority in Location Kit.
    scenario: geoLocationManager.LocationRequestScenario.UNSET,
    timeInterval: Math.ceil((options.timeInterval ?? interval) / 1000),
    distanceInterval: options.distanceInterval ?? distance,
  };
}

export function finiteOrNull(value: number | undefined): number | null {
  return value !== undefined && Number.isFinite(value) ? value : null;
}

function nonnegativeOrNull(value: number | undefined): number | null {
  return value !== undefined && Number.isFinite(value) && value >= 0 ? value : null;
}

export class ExpoLocationError extends ExpoModuleError {
  constructor(error: Object, code: string = 'ERR_LOCATION_UNAVAILABLE') {
    if (error instanceof ExpoModuleError) {
      code = error.code;
    } else {
      // Synchronous N-API exceptions use string codes; async rejections use numbers.
      switch (Number((error as BusinessError).code)) {
        case LocationErrorCode.PermissionDenied:
          code = 'ERR_LOCATION_UNAUTHORIZED';
          break;
        case LocationErrorCode.InvalidArgument:
          code = 'ERR_LOCATION_INVALID_ARGUMENT';
          break;
        case LocationErrorCode.SwitchOff:
          code = 'ERR_LOCATION_SETTINGS_UNSATISFIED';
          break;
      }
    }

    super(code, message(error), error);
  }
}

export function message(error: Object): string {
  return (error as Error).message || String(error);
}

export function locationErrorReason(error: geoLocationManager.LocationError): string {
  switch (error) {
    case geoLocationManager.LocationError.LOCATING_FAILED_LOCATION_PERMISSION_DENIED:
      return 'Not authorized to use location services.';
    case geoLocationManager.LocationError.LOCATING_FAILED_BACKGROUND_PERMISSION_DENIED:
      return 'Not authorized to use background location services.';
    case geoLocationManager.LocationError.LOCATING_FAILED_LOCATION_SWITCH_OFF:
      return 'Location services are disabled.';
    case geoLocationManager.LocationError.LOCATING_FAILED_INTERNET_ACCESS_FAILURE:
      return 'Location services could not access the network.';
    default:
      return 'HarmonyOS could not obtain a location.';
  }
}
