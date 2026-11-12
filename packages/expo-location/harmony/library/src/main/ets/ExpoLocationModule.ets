/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoAppLifecycleState,
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
} from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { geoLocationManager } from '@kit.LocationKit';
import { sensor } from '@kit.SensorServiceKit';
import { ExpoTaskManagerRegistry } from '@expo-harmony/expo-task-manager';
import { validateBackgroundOptions } from './LocationBackgroundConsumer';
import { geofenceOptions } from './LocationGeofencingConsumer';
import { LocationPermissions, PermissionResponse } from './LocationPermissions';
import { backgroundLocationConsumer, geofencingConsumer } from './LocationTaskConsumers';
import {
  BACKGROUND_TASK_TYPE,
  GEOFENCE_TASK_TYPE,
  hasBackgroundConfiguration,
  hasGeofenceConfiguration,
  isContinuousLocationSupported,
  isLocationTaskRegistered,
  requireLocationTaskPermission,
} from './LocationTaskSupport';
import {
  Accuracy,
  COORDINATE,
  Coordinate,
  ERROR_EVENT,
  GeocodedAddress,
  HEADING_EVENT,
  HeadingEvent,
  HeadingRecord,
  LAST_KNOWN_OPTIONS,
  LastKnownOptions,
  LOCATION_EVENT,
  LOCATION_OPTIONS,
  LOCATION_TIMEOUT_MS,
  MOTION_ACTIVITY_EVENT,
  LocationErrorCode,
  LocationErrorEvent,
  LocationEvent,
  LocationOptions,
  LocationRecord,
  ExpoLocationError,
  ProviderStatus,
  TASK_OPTIONS,
  WATCH_ID,
  finiteOrNull,
  message,
  locationErrorReason,
  locationRequest,
  validCoordinate,
} from './LocationRecords';

const RETRY_DELAY_MS: number = 1000;
const RETRY_LIMIT: number = 3;

class LocationWatch {
  id: number;
  options: LocationOptions;
  callback?: (location: geoLocationManager.Location) => void;
  removed: boolean = false;
  active: boolean = false;

  constructor(id: number, options: LocationOptions) {
    this.id = id;
    this.options = options;
  }
}

export class ExpoLocationModule extends ExpoModule {
  private permissions: LocationPermissions;
  private foreground: boolean;
  private destroyed: boolean = false;
  private readonly watches: Map<number, LocationWatch> = new Map();
  private readonly headings: Set<number> = new Set();
  private headingCallback?: (response: sensor.OrientationResponse) => void;
  private locationCallback?: (location: geoLocationManager.Location) => void;
  private enabledCallback?: (enabled: boolean) => void;
  private errorCallback?: (error: geoLocationManager.LocationError) => void;
  private headingActive: boolean = false;
  private locationActive: boolean = false;
  private errorActive: boolean = false;
  private timer: number = -1;
  private attempts: number = 0;
  private failed: boolean = false;
  private declination?: number;
  private generation: number = 0;

  constructor(context: ExpoModuleContext) {
    super(context);
    this.permissions = new LocationPermissions(context);
    this.foreground = context.appLifecycleState === ExpoAppLifecycleState.FOREGROUND;
  }

  definition(): ExpoModuleDefinition {
    return new ExpoModuleDefinition()
      .name('ExpoLocation')
      .events([LOCATION_EVENT, HEADING_EVENT, ERROR_EVENT, MOTION_ACTIVITY_EVENT])
      .asyncFunction('getForegroundPermissionsAsync', async (): Promise<PermissionResponse> => await this.foregroundPermission(false))
      .asyncFunction('requestForegroundPermissionsAsync', async (): Promise<PermissionResponse> => await this.foregroundPermission(true))
      .asyncFunction('getPermissionsAsync', async (): Promise<PermissionResponse> => await this.foregroundPermission(false))
      .asyncFunction('requestPermissionsAsync', async (): Promise<PermissionResponse> => await this.foregroundPermission(true))
      .asyncFunction('getBackgroundPermissionsAsync', async (): Promise<PermissionResponse> => this.backgroundPermission(false))
      .asyncFunction('requestBackgroundPermissionsAsync', async (): Promise<PermissionResponse> => this.backgroundPermission(true))
      .asyncFunction('getMotionActivityPermissionsAsync', async (): Promise<PermissionResponse> => this.motionActivityPermission())
      .asyncFunction('requestMotionActivityPermissionsAsync', async (): Promise<PermissionResponse> => this.motionActivityPermission())
      .asyncFunction(
        'watchMotionActivityImplAsync',
        ExpoFunction.typed1(WATCH_ID, async (_id: number): Promise<void> => {
          this.ensureActive();
          // Public HarmonyOS APIs do not provide Expo's six activity classes.
          throw new ExpoModuleError('ERR_MOTION_ACTIVITY_UNAVAILABLE', 'Motion activity recognition is not available on HarmonyOS.');
        }),
      )
      .asyncFunction('getProviderStatusAsync', async (): Promise<ProviderStatus> => {
        const enabled = this.servicesEnabled();
        return new ProviderStatus(enabled, enabled && this.taskAvailable(BACKGROUND_TASK_TYPE));
      })
      .asyncFunction('hasServicesEnabledAsync', async (): Promise<boolean> => this.servicesEnabled())
      .asyncFunction(
        'getCurrentPositionAsync',
        ExpoFunction.typed1(
          LOCATION_OPTIONS.defaulted(new LocationOptions()),
          async (options: LocationOptions): Promise<LocationRecord> => await this.currentPosition(options),
        ),
      )
      .asyncFunction(
        'getLastKnownPositionAsync',
        ExpoFunction.typed1(
          LAST_KNOWN_OPTIONS.defaulted(new LastKnownOptions()),
          async (options: LastKnownOptions): Promise<LocationRecord | null> => this.lastKnownPosition(options),
        ),
      )
      .asyncFunction(
        'watchPositionImplAsync',
        ExpoFunction.typed2(
          WATCH_ID,
          LOCATION_OPTIONS.defaulted(new LocationOptions()),
          async (id: number, options: LocationOptions): Promise<void> => this.watchPosition(id, options),
        ),
      )
      .asyncFunction(
        'watchDeviceHeading',
        ExpoFunction.typed1(WATCH_ID, async (id: number): Promise<void> => this.watchHeading(id)),
      )
      .asyncFunction(
        'removeWatchAsync',
        ExpoFunction.typed1(WATCH_ID, async (id: number): Promise<void> => this.removeWatch(id)),
      )
      .asyncFunction(
        'geocodeAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (address: string): Promise<Coordinate[]> => await this.geocode(address)),
      )
      .asyncFunction(
        'reverseGeocodeAsync',
        ExpoFunction.typed1(COORDINATE, async (coordinate: Coordinate): Promise<GeocodedAddress[]> => await this.reverseGeocode(coordinate)),
      )
      .asyncFunction(
        'startLocationUpdatesAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          TASK_OPTIONS,
          async (name: string, options: Record<string, ESObject>): Promise<void> => this.startTask(name, BACKGROUND_TASK_TYPE, options),
        ),
      )
      .asyncFunction(
        'startGeofencingAsync',
        ExpoFunction.typed2(
          ExpoValueTypes.string(),
          TASK_OPTIONS,
          async (name: string, options: Record<string, ESObject>): Promise<void> => this.startTask(name, GEOFENCE_TASK_TYPE, options),
        ),
      )
      .asyncFunction(
        'stopLocationUpdatesAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (name: string): Promise<void> => this.stopTask(name, BACKGROUND_TASK_TYPE)),
      )
      .asyncFunction(
        'stopGeofencingAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (name: string): Promise<void> => this.stopTask(name, GEOFENCE_TASK_TYPE)),
      )
      .asyncFunction(
        'hasStartedLocationUpdatesAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (name: string): Promise<boolean> => this.hasTask(name, BACKGROUND_TASK_TYPE)),
      )
      .asyncFunction(
        'hasStartedGeofencingAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (name: string): Promise<boolean> => this.hasTask(name, GEOFENCE_TASK_TYPE)),
      )
      .onForeground((): void => {
        this.setForeground(true);
        backgroundLocationConsumer.refresh(this.context);
        geofencingConsumer.refresh(this.context);
      })
      .onBackground((): void => this.setForeground(false))
      .onPrepareForReload(async (): Promise<void> => this.destroy())
      .onAbilityDestroy((): void => this.destroy())
      .onDestroy((): void => this.destroy());
  }

  private ensureActive(): void {
    if (this.destroyed) throw new ExpoModuleError('ERR_LOCATION_DESTROYED', 'The Expo Location module has been destroyed.');
  }

  private motionActivityPermission(): PermissionResponse {
    this.ensureActive();
    return new PermissionResponse('denied', false);
  }

  private async foregroundPermission(request: boolean): Promise<PermissionResponse> {
    this.ensureActive();

    const permission = request ? await this.permissions.requestForeground() : await this.permissions.getForeground();

    this.ensureActive();
    this.availabilityChanged();

    return permission;
  }

  private async backgroundPermission(request: boolean): Promise<PermissionResponse> {
    this.ensureActive();
    if (!this.taskAvailable(BACKGROUND_TASK_TYPE) && !this.taskAvailable(GEOFENCE_TASK_TYPE)) {
      return new PermissionResponse('denied', false);
    }

    if (request && this.foreground && !this.context.isHeadless) {
      const permission = await this.permissions.requestBackground();
      this.ensureActive();
      if (permission.granted) {
        backgroundLocationConsumer.refresh(this.context);
        geofencingConsumer.refresh(this.context);
      }

      return permission;
    }
    return this.permissions.getBackground();
  }

  private servicesEnabled(logFailure: boolean = true): boolean {
    this.ensureActive();
    if (!canIUse('SystemCapability.Location.Location.Core')) return false;

    try {
      return geoLocationManager.isLocationEnabled();
    } catch (error) {
      if (logFailure) this.warn(`Unable to query location services: ${message(error)}`);
      return false;
    }
  }

  private ensureForegroundPermission(): void {
    this.ensureActive();
    this.permissions.ensureForeground();
  }

  private ensureLocation(): void {
    this.ensureForegroundPermission();

    if (!this.servicesEnabled()) {
      throw new ExpoModuleError('ERR_LOCATION_SETTINGS_UNSATISFIED', 'Location services are disabled or unavailable.');
    }
  }

  private async currentPosition(options: LocationOptions): Promise<LocationRecord> {
    this.ensureLocation();

    const cached = new LastKnownOptions();
    cached.maxAge = options.interval();
    if (cached.maxAge > 0) {
      const location = this.lastKnownPosition(cached);
      if (location !== null) return location;
    }

    const request: geoLocationManager.SingleLocationRequest = {
      locatingPriority:
        options.accuracy >= Accuracy.High
          ? geoLocationManager.LocatingPriority.PRIORITY_ACCURACY
          : geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
      locatingTimeoutMs: LOCATION_TIMEOUT_MS,
    };

    try {
      const location = await geoLocationManager.getCurrentLocation(request);

      this.ensureActive();
      this.permissions.ensureForeground();

      return new LocationRecord(location);
    } catch (error) {
      throw new ExpoLocationError(error);
    }
  }

  private lastKnownPosition(options: LastKnownOptions): LocationRecord | null {
    this.ensureActive();
    this.permissions.ensureForeground();

    try {
      const location = geoLocationManager.getLastLocation();

      const record = new LocationRecord(location);

      if (options.maxAge !== undefined && Date.now() - record.timestamp > options.maxAge) return null;
      if (options.requiredAccuracy !== undefined && (record.coords.accuracy === null || record.coords.accuracy > options.requiredAccuracy))
        return null;

      return record;
    } catch (error) {
      switch (Number((error as BusinessError).code)) {
        case LocationErrorCode.NoLocation:
        case LocationErrorCode.Unavailable:
        case LocationErrorCode.SwitchOff:
        case LocationErrorCode.Unsupported:
          return null;
      }

      throw new ExpoLocationError(error);
    }
  }

  private watchPosition(id: number, options: LocationOptions): void {
    this.ensureLocation();

    this.removeWatch(id);
    if (this.watches.has(id)) {
      throw new ExpoModuleError('ERR_LOCATION_WATCH', 'The previous location subscription could not be released.');
    }

    const watch = new LocationWatch(id, options);
    this.watches.set(id, watch);
    this.startAvailabilityObservers();

    try {
      if (this.foreground) this.startWatch(watch);
    } catch (error) {
      watch.removed = true;
      this.cleanup((): void => this.stopWatch(watch));
      this.cleanup((): void => this.stopErrorObserverIfIdle());
      this.cleanup((): void => this.stopAvailabilityObserversIfIdle());

      throw new ExpoLocationError(error, 'ERR_LOCATION_WATCH');
    }
  }

  private startWatch(watch: LocationWatch): void {
    if (watch.active || watch.removed || this.destroyed || !this.foreground) return;

    if (watch.callback !== undefined) this.stopWatch(watch);
    this.ensureLocation();
    this.startErrorObserver();

    const callback = (location: geoLocationManager.Location): void => {
      if (!this.foreground || this.destroyed || !watch.active || watch.removed || watch.callback !== callback) return;
      if (!this.checkWatchPermission()) return;

      try {
        this.sendEvent(LOCATION_EVENT, new LocationEvent(watch.id, new LocationRecord(location)));
      } catch (error) {
        this.emitError(watch.id, message(error));
      }
    };

    watch.callback = callback;
    geoLocationManager.on('locationChange', locationRequest(watch.options), callback);
    watch.active = true;
  }

  private stopWatch(watch: LocationWatch): void {
    watch.active = false;

    if (watch.callback !== undefined) {
      geoLocationManager.off('locationChange', watch.callback);
      watch.callback = undefined;
    }

    if (watch.removed) this.watches.delete(watch.id);
  }

  private removeWatch(id: number): void {
    const watch = this.watches.get(id);
    if (watch !== undefined) {
      watch.removed = true;
      this.cleanup((): void => this.stopWatch(watch));
    }

    this.headings.delete(id);
    if (this.headings.size === 0) this.cleanup((): void => this.stopHeading());

    this.cleanup((): void => this.stopErrorObserverIfIdle());
    this.cleanup((): void => this.stopAvailabilityObserversIfIdle());
  }

  private watchHeading(id: number): void {
    this.ensureForegroundPermission();

    this.removeWatch(id);
    this.headings.add(id);
    this.startAvailabilityObservers();

    try {
      if (this.foreground) this.startHeading();
    } catch (error) {
      this.headings.delete(id);
      if (this.headings.size === 0) this.cleanup((): void => this.stopHeading());

      this.cleanup((): void => this.stopErrorObserverIfIdle());
      this.cleanup((): void => this.stopAvailabilityObserversIfIdle());

      throw new ExpoLocationError(error, 'ERR_LOCATION_HEADING');
    }
  }

  private startHeading(): void {
    if (this.headings.size === 0 || this.destroyed || !this.foreground) return;

    this.ensureForegroundPermission();

    if (this.headingActive) {
      this.startHeadingLocation();
      return;
    }

    if (this.headingCallback !== undefined || this.locationCallback !== undefined) this.stopHeading();
    if (!canIUse('SystemCapability.Sensors.Sensor')) {
      throw new ExpoModuleError('ERR_LOCATION_HEADING', 'Orientation sensors are unavailable on this device.');
    }

    const callback = (response: sensor.OrientationResponse): void => {
      if (!this.foreground || this.destroyed || !this.headingActive || this.headingCallback !== callback || !Number.isFinite(response.alpha)) return;
      if (!this.checkWatchPermission()) return;

      try {
        const magnetic = normalizeHeading(response.alpha);
        const north = this.declination !== undefined && this.servicesEnabled(false) ? normalizeHeading(magnetic + this.declination) : -1;
        const heading = new HeadingRecord(magnetic, north, headingAccuracy(response.accuracy));

        this.headings.forEach((id: number): void => this.sendEvent(HEADING_EVENT, new HeadingEvent(id, heading)));
      } catch (error) {
        this.headings.forEach((id: number): void => this.emitError(id, message(error)));
      }
    };

    this.headingCallback = callback;
    sensor.on(sensor.SensorId.ORIENTATION, callback);
    this.headingActive = true;
    this.startHeadingLocation();
  }

  private startHeadingLocation(): void {
    try {
      if (this.locationActive || !this.permissions.hasForeground() || !this.servicesEnabled()) return;

      if (this.locationCallback !== undefined) this.stopHeadingLocation();

      const callback = (location: geoLocationManager.Location): void => {
        if (this.destroyed || !this.foreground || !this.locationActive || this.locationCallback !== callback) return;
        this.updateDeclination(location, callback);
      };

      this.startErrorObserver();
      this.locationCallback = callback;
      const options = new LocationOptions();
      options.distanceInterval = 0;

      geoLocationManager.on('locationChange', locationRequest(options), callback);
      this.locationActive = true;

      try {
        this.updateDeclination(geoLocationManager.getLastLocation(), callback);
      } catch (error) {
        if (Number((error as BusinessError).code) !== LocationErrorCode.NoLocation) {
          this.warn(`Unable to read the compass location: ${message(error)}`);
        }
      }
    } catch (error) {
      this.warn(`Unable to obtain true north: ${message(error)}`);

      this.cleanup((): void => this.stopHeadingLocation());
      this.cleanup((): void => this.stopErrorObserverIfIdle());

      this.failed = true;
      this.scheduleRetry();
    }
  }

  private async updateDeclination(location: geoLocationManager.Location, callback: (location: geoLocationManager.Location) => void): Promise<void> {
    const generation = ++this.generation;

    try {
      if (!validCoordinate(location.latitude, location.longitude) || finiteOrNull(location.altitude) === null) {
        this.declination = undefined;
        return;
      }

      const coordinate: sensor.LocationOptions = { latitude: location.latitude, longitude: location.longitude, altitude: location.altitude };
      const info = await sensor.getGeomagneticInfo(coordinate, Date.now());

      if (this.destroyed || !this.foreground || !this.locationActive || this.locationCallback !== callback || generation !== this.generation) return;

      this.declination = finiteOrNull(info.deflectionAngle) ?? undefined;
    } catch (error) {
      if (generation !== this.generation) return;

      this.declination = undefined;
      if (!this.destroyed) this.warn(`Unable to calculate true north: ${message(error)}`);
    }
  }

  private stopHeadingLocation(): void {
    this.locationActive = false;
    this.declination = undefined;
    this.generation += 1;

    if (this.locationCallback !== undefined) {
      geoLocationManager.off('locationChange', this.locationCallback);
      this.locationCallback = undefined;
    }
  }

  private stopHeading(): void {
    this.headingActive = false;

    try {
      if (this.headingCallback !== undefined) {
        sensor.off(sensor.SensorId.ORIENTATION, this.headingCallback);
        this.headingCallback = undefined;
      }
    } finally {
      this.stopHeadingLocation();
    }
  }

  private startErrorObserver(): void {
    if (this.errorActive) return;
    if (this.errorCallback !== undefined) this.stopErrorObserver();

    const callback = (error: geoLocationManager.LocationError): void => {
      if (this.destroyed || !this.foreground || !this.errorActive || this.errorCallback !== callback) return;

      try {
        const reason = locationErrorReason(error);

        this.watches.forEach((watch: LocationWatch): void => {
          if (!watch.removed && watch.active) this.emitError(watch.id, reason);
        });
        // Positioning failures only affect true north. Losing authorization also gates the compass.
        if (error === geoLocationManager.LocationError.LOCATING_FAILED_LOCATION_PERMISSION_DENIED) {
          this.headings.forEach((id: number): void => this.emitError(id, reason));
        }
      } catch (failure) {
        this.warn(`Unable to report a location service error: ${message(failure)}`);
      } finally {
        this.declination = undefined;
        this.generation += 1;

        if (error === geoLocationManager.LocationError.LOCATING_FAILED_LOCATION_PERMISSION_DENIED) {
          this.pauseLocationSources();
        } else if (error === geoLocationManager.LocationError.LOCATING_FAILED_LOCATION_SWITCH_OFF) {
          this.pausePositionSources();
        }
      }
    };

    this.errorCallback = callback;
    try {
      geoLocationManager.on('locationError', callback);
      this.errorActive = true;
    } catch (error) {
      this.cleanup((): void => this.stopErrorObserver());

      throw new ExpoLocationError(error);
    }
  }

  private stopErrorObserver(): void {
    this.errorActive = false;

    if (this.errorCallback !== undefined) {
      geoLocationManager.off('locationError', this.errorCallback);
      this.errorCallback = undefined;
    }
  }

  private stopErrorObserverIfIdle(): void {
    if (this.locationCallback !== undefined) return;

    for (const watch of this.watches.values()) {
      if (watch.callback !== undefined) return;
    }

    this.stopErrorObserver();
  }

  private emitError(id: number, reason: string): void {
    if (this.destroyed) return;

    try {
      this.sendEvent(ERROR_EVENT, new LocationErrorEvent(id, reason));
    } catch (error) {
      this.warn(`Unable to deliver a location error event: ${message(error)}`);
    }
  }

  private ensureForegroundGeocoding(): void {
    this.ensureForegroundPermission();
    if (!this.foreground) throw new ExpoModuleError('ERR_LOCATION_GEOCODING', 'Geocoder is not running while the app is in the background.');
  }

  private ensureGeocoder(): void {
    this.ensureForegroundGeocoding();
    if (!canIUse('SystemCapability.Location.Location.Geocoder') || !geoLocationManager.isGeocoderAvailable()) {
      throw new ExpoModuleError('ERR_LOCATION_GEOCODER_UNAVAILABLE', 'HarmonyOS geocoding is unavailable on this device.');
    }
  }

  private async geocode(address: string): Promise<Coordinate[]> {
    try {
      this.ensureGeocoder();

      const results = await geoLocationManager.getAddressesFromLocationName({ description: address, maxItems: 1 });

      this.ensureForegroundGeocoding();

      return (results ?? []).map((result: geoLocationManager.GeoAddress): Coordinate => {
        if (result.latitude === undefined || result.longitude === undefined || !validCoordinate(result.latitude, result.longitude)) {
          throw new ExpoModuleError('ERR_LOCATION_INVALID_RESPONSE', 'The geocoder returned invalid coordinates.');
        }

        return new Coordinate(result.latitude, result.longitude);
      });
    } catch (error) {
      throw new ExpoLocationError(error, 'ERR_LOCATION_GEOCODING');
    }
  }

  private async reverseGeocode(coordinate: Coordinate): Promise<GeocodedAddress[]> {
    try {
      this.ensureGeocoder();

      const results = await geoLocationManager.getAddressesFromLocation({
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        maxItems: 1,
      });

      this.ensureForegroundGeocoding();

      return (results ?? []).map((result: geoLocationManager.GeoAddress): GeocodedAddress => new GeocodedAddress(result));
    } catch (error) {
      throw new ExpoLocationError(error, 'ERR_LOCATION_GEOCODING');
    }
  }

  private hasSubscriptions(): boolean {
    return this.watches.size > 0 || this.headings.size > 0;
  }

  private startAvailabilityObservers(): void {
    if (this.destroyed || !this.foreground || !this.hasSubscriptions()) return;

    // Suspended subscriptions still need observers to detect permission/service recovery.
    try {
      if (this.enabledCallback === undefined && canIUse('SystemCapability.Location.Location.Core')) {
        const callback = (_enabled: boolean): void => {
          if (this.enabledCallback === callback) this.availabilityChanged();
        };

        geoLocationManager.on('locationEnabledChange', callback);
        this.enabledCallback = callback;
      }
    } catch (error) {
      this.failed = true;
      this.warn(`Unable to observe location availability: ${message(error)}`);
      this.scheduleRetry();
    }

    try {
      this.permissions.startObserving((): void => this.availabilityChanged());
    } catch (error) {
      this.failed = true;
      this.warn(`Unable to observe location permission changes: ${message(error)}`);
      this.scheduleRetry();
    }
  }

  private stopAvailabilityObserversIfIdle(): void {
    if (!this.destroyed && this.foreground && this.hasSubscriptions()) return;

    try {
      if (this.enabledCallback !== undefined) {
        geoLocationManager.off('locationEnabledChange', this.enabledCallback);
        this.enabledCallback = undefined;
      }
    } finally {
      this.permissions.stopObserving();
    }
  }

  private availabilityChanged(): void {
    if (this.destroyed || !this.foreground || !this.hasSubscriptions()) return;
    if (!this.checkWatchPermission()) return;

    if (!this.servicesEnabled()) {
      this.pausePositionSources('Location services are disabled or unavailable.');
      this.resumeHeading();
      return;
    }

    this.setForeground(true);
  }

  private checkWatchPermission(): boolean {
    try {
      this.ensureForegroundPermission();
      return true;
    } catch (error) {
      this.pauseLocationSources(message(error));
      return false;
    }
  }

  private pausePositionSources(reason?: string): void {
    this.watches.forEach((watch: LocationWatch): void => {
      const active = watch.active;
      this.cleanup((): void => this.stopWatch(watch));
      if (active && !watch.removed && reason !== undefined) this.emitError(watch.id, reason);
    });

    this.cleanup((): void => this.stopHeadingLocation());
    this.cleanup((): void => this.stopErrorObserverIfIdle());
    this.cleanup((): void => this.stopAvailabilityObserversIfIdle());
  }

  private pauseLocationSources(reason?: string): void {
    this.pausePositionSources(reason);

    const active = this.headingActive;
    this.cleanup((): void => this.stopHeading());
    if (active && reason !== undefined) this.headings.forEach((id: number): void => this.emitError(id, reason));
  }

  private resumeHeading(): void {
    try {
      this.startHeading();
    } catch (error) {
      this.failed = true;
      this.headings.forEach((id: number): void => this.emitError(id, message(error)));
      this.scheduleRetry();
    }
  }

  private setForeground(foreground: boolean): void {
    if (this.destroyed) return;

    this.foreground = foreground;
    this.failed = false;
    if (foreground) this.startAvailabilityObservers();

    this.watches.forEach((watch: LocationWatch): void => {
      try {
        if (!foreground || watch.removed) this.stopWatch(watch);
        else this.startWatch(watch);
      } catch (error) {
        this.failed = true;
        this.emitError(watch.id, message(error));
        this.scheduleRetry();
      }
    });

    if (foreground) {
      this.resumeHeading();
    } else {
      this.cleanup((): void => this.stopHeading());
      this.cleanup((): void => this.stopErrorObserver());
    }

    this.cleanup((): void => this.stopErrorObserverIfIdle());
    this.cleanup((): void => this.stopAvailabilityObserversIfIdle());

    if (!this.failed && this.timer < 0) this.attempts = 0;
  }

  private warn(message: string): void {
    // The logger getter requires a live runtime; logging must not interrupt cleanup.
    try {
      if (this.context.isValid) this.context.logger.warn(message);
    } catch (_) {}
  }

  private cleanup(action: () => void): void {
    try {
      action();
    } catch (error) {
      this.failed = true;
      this.warn(`Unable to release Expo Location resources: ${message(error)}`);
      this.scheduleRetry();
    }
  }

  private scheduleRetry(): void {
    if (this.timer >= 0 || this.attempts >= RETRY_LIMIT) return;

    this.timer = setTimeout((): void => {
      this.timer = -1;
      this.attempts += 1;
      this.failed = false;

      this.watches.forEach((watch: LocationWatch): void => {
        if (!watch.active || watch.removed || !this.foreground || this.destroyed) {
          this.cleanup((): void => {
            this.stopWatch(watch);
            if (!watch.removed && this.foreground && !this.destroyed) this.startWatch(watch);
          });
        }
      });

      if (!this.headingActive || this.headings.size === 0 || !this.foreground || this.destroyed) {
        this.cleanup((): void => {
          this.stopHeading();
          if (this.foreground && !this.destroyed) this.startHeading();
        });
      } else if (!this.locationActive) {
        this.cleanup((): void => {
          this.stopHeadingLocation();
          this.startHeadingLocation();
        });
      }

      this.cleanup((): void => this.stopErrorObserverIfIdle());
      this.cleanup((): void => this.stopAvailabilityObserversIfIdle());

      if (this.foreground) this.startAvailabilityObservers();

      if (!this.failed) this.attempts = 0;
    }, RETRY_DELAY_MS);
  }

  private destroy(): void {
    if (!this.destroyed) this.attempts = 0;
    this.destroyed = true;
    this.foreground = false;
    this.failed = false;

    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }

    this.watches.forEach((watch: LocationWatch): void => {
      watch.removed = true;
      this.cleanup((): void => this.stopWatch(watch));
    });

    this.headings.clear();
    this.cleanup((): void => this.stopHeading());
    this.cleanup((): void => this.stopErrorObserver());
    this.cleanup((): void => this.stopAvailabilityObserversIfIdle());
  }

  private checkTaskName(name: string): void {
    this.ensureActive();
    if (name.trim().length === 0) throw new ExpoModuleError('ERR_LOCATION_INVALID_ARGUMENT', 'taskName must be a nonempty string.');
  }

  private taskAvailable(taskType: string): boolean {
    const ability = this.context.uiAbilityContext;
    return taskType === GEOFENCE_TASK_TYPE
      ? hasGeofenceConfiguration(ability)
      : hasBackgroundConfiguration(ability) && isContinuousLocationSupported();
  }

  private async startTask(name: string, taskType: string, options: ESObject): Promise<void> {
    this.checkTaskName(name);
    const geofencing = taskType === GEOFENCE_TASK_TYPE;
    if (!this.taskAvailable(taskType)) {
      throw new ExpoModuleError(
        geofencing ? 'ERR_LOCATION_GEOFENCING_UNAVAILABLE' : 'ERR_LOCATION_BACKGROUND_UNAVAILABLE',
        geofencing
          ? 'Harmony geofencing requires the opt-in config plugin, API 23 or later, and GNSS geofencing support.'
          : 'Harmony background location requires the opt-in config plugin, API 21 or later, and continuous location task support.',
      );
    }

    if (!this.foreground || this.context.isHeadless) {
      throw new ExpoModuleError('ERR_LOCATION_BACKGROUND_NOT_FOREGROUND', 'Start location tasks from a foreground UIAbility.');
    }
    requireLocationTaskPermission(this.context, geofencing);

    this.ensureLocation();

    if (geofencing) {
      options = geofenceOptions(options);
    } else {
      validateBackgroundOptions(options);
    }
    await ExpoTaskManagerRegistry.registerTask(this.context, name, taskType, options);
  }

  private async stopTask(name: string, taskType: string): Promise<void> {
    this.checkTaskName(name);
    try {
      await ExpoTaskManagerRegistry.unregisterTaskForConsumer(this.context, name, taskType);
    } catch (error) {
      const code = (error as ExpoModuleError).code;
      if (code !== 'ERR_TASK_MANAGER_TASK_NOT_FOUND' && code !== 'ERR_TASK_MANAGER_TASK_CONFLICT') {
        throw new ExpoLocationError(error);
      }
      throw new ExpoModuleError('ERR_TASK_NOT_FOUND', `Task '${name}' is not registered by Expo Location.`);
    }
  }

  private async hasTask(name: string, taskType: string): Promise<boolean> {
    this.checkTaskName(name);
    return await isLocationTaskRegistered(this.context, name, taskType);
  }
}

function normalizeHeading(value: number): number {
  return ((value % 360) + 360) % 360;
}

function headingAccuracy(value: sensor.SensorAccuracy): number {
  switch (value) {
    case sensor.SensorAccuracy.ACCURACY_LOW:
      return 1;
    case sensor.SensorAccuracy.ACCURACY_MEDIUM:
      return 2;
    case sensor.SensorAccuracy.ACCURACY_HIGH:
      return 3;
    default:
      return 0;
  }
}
