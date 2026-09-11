import type { ExpoModuleRegistration } from '../modules/ExpoModule';
import type { ExpoServiceOverride } from './ExpoServicesRegistry';
import { ExpoRuntimeSession } from './ExpoRuntimeSession';

export interface ExpoRuntimeOptions {
  session?: ExpoRuntimeSession;
  services?: ExpoServiceOverride[];
  moduleOverrides?: ExpoModuleRegistration[];
}

export class ExpoRuntimeConfig {
  readonly session?: ExpoRuntimeSession;
  readonly services: ExpoServiceOverride[];
  readonly moduleOverrides: ExpoModuleRegistration[];

  constructor(options: ExpoRuntimeOptions = {}) {
    this.session = options.session;
    this.services = (options.services ?? []).slice();
    this.moduleOverrides = (options.moduleOverrides ?? []).map((registration: ExpoModuleRegistration): ExpoModuleRegistration => ({
      registrationId: registration.registrationId,
      moduleClassName: registration.moduleClassName,
      factory: registration.factory,
    }));
  }
}
