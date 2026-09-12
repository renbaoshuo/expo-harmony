import type { common } from '@kit.AbilityKit';
import type { ExpoRuntimeSession } from './ExpoRuntimeSession';
import { ExpoModuleError } from '../modules/ExpoModuleError';

export abstract class ExpoService {
  abstract readonly identity: ExpoServiceBinding<Object>;
  readonly interfaces: ExpoServiceBinding<Object>[] = [];

  constructor(_context?: ExpoServiceContext) {}
}

export interface ExpoServiceClass {
  readonly name: string;
  readonly create: (context: ExpoServiceContext) => ExpoService;
}

export class ExpoServiceBinding<T extends Object> {
  readonly key: ExpoServiceKey<T>;
  readonly value: T;

  constructor(key: ExpoServiceKey<T>, value: T) {
    this.key = key;
    this.value = value;
  }
}

export type ExpoServiceOverride = ExpoService | ExpoServiceBinding<Object>;

export class ExpoServiceKey<T extends Object> {
  readonly name: string;

  constructor(name: string) {
    this.name = name;
  }

  bind(service: T): ExpoServiceBinding<T> {
    return new ExpoServiceBinding<T>(this, service);
  }
}

export class ExpoServiceContext {
  private ability?: common.UIAbilityContext;
  private registry?: ExpoServicesRegistry;
  private owner?: ExpoRuntimeSession;

  constructor(ability: common.UIAbilityContext, registry: ExpoServicesRegistry, session?: ExpoRuntimeSession) {
    this.ability = ability;
    this.registry = registry;
    this.owner = session;
  }

  get uiAbilityContext(): common.UIAbilityContext {
    if (this.registry?.isValid !== true || this.ability === undefined) throw new Error('The Expo services registry has been invalidated.');
    return this.ability;
  }

  get services(): ExpoServicesRegistry {
    if (this.registry?.isValid !== true) throw new Error('The Expo services registry has been invalidated.');
    return this.registry;
  }

  get session(): ExpoRuntimeSession | undefined {
    if (this.registry?.isValid !== true) throw new Error('The Expo services registry has been invalidated.');
    return this.owner;
  }

  assertActive(): void {
    if (this.registry?.isValid !== true) throw new Error('The Expo services registry has been invalidated.');
    this.session?.assertOpen();
  }

  invalidate(): void {
    this.ability = undefined;
    this.registry = undefined;
    this.owner = undefined;
  }
}

export class ExpoServicesRegistry {
  readonly isHeadless: boolean;
  private readonly entries: Map<Object, Object> = new Map<Object, Object>();
  private readonly context: ExpoServiceContext;
  private valid: boolean = true;

  constructor(context: common.UIAbilityContext, session?: ExpoRuntimeSession, isHeadless: boolean = false) {
    this.isHeadless = isHeadless;
    this.context = new ExpoServiceContext(context, this, session);
  }

  get isValid(): boolean {
    return this.valid;
  }

  registerClass(declaration: ExpoServiceClass): ExpoServicesRegistry {
    this.context.assertActive();
    if (declaration.name.length === 0) throw new Error('An Expo service class must have a name.');

    let service: ExpoService;
    try {
      service = declaration.create(this.context);
    } catch (error) {
      throw new ExpoModuleError('ERR_SERVICE_CONSTRUCTION', `Unable to construct Expo service '${declaration.name}'.`, error as Object);
    }

    return this.registerService(service);
  }

  registerClasses(declarations: ExpoServiceClass[]): ExpoServicesRegistry {
    this.context.assertActive();
    declarations.forEach((declaration: ExpoServiceClass): void => {
      this.registerClass(declaration);
    });
    return this;
  }

  registerService(service: ExpoService): ExpoServicesRegistry {
    this.context.assertActive();
    const interfaces = service.interfaces;
    const bindings = interfaces.length > 0 ? interfaces : [service.identity];
    if (bindings.some((binding: ExpoServiceBinding<Object>): boolean => binding.value !== service)) {
      throw new Error('An Expo service must bind its interfaces to itself.');
    }

    bindings.forEach((binding: ExpoServiceBinding<Object>): void => {
      this.register(binding.key, binding.value);
    });
    return this;
  }

  registerOverrides(overrides: ExpoServiceOverride[]): ExpoServicesRegistry {
    this.context.assertActive();
    overrides.forEach((override: ExpoServiceOverride): void => {
      if (override instanceof ExpoServiceBinding) this.register(override.key, override.value);
      else this.registerService(override);
    });
    return this;
  }

  register<T extends Object>(key: ExpoServiceKey<T>, service: T): ExpoServicesRegistry {
    this.context.assertActive();
    this.entries.set(key, service);
    return this;
  }

  get<T extends Object>(key: ExpoServiceKey<T>): T | undefined {
    if (!this.valid) throw new Error('The Expo services registry has been invalidated.');
    return this.entries.get(key) as T | undefined;
  }

  require<T extends Object>(key: ExpoServiceKey<T>): T {
    const service = this.get(key);
    if (service === undefined) throw new Error(`Expo service '${key.name}' is not registered.`);
    return service;
  }

  invalidate(): void {
    this.valid = false;
    this.entries.clear();
    this.context.invalidate();
  }
}
