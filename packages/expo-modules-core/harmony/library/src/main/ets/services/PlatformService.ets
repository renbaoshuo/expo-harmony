import type { UITurboModuleContext } from '@rnoh/react-native-openharmony';

export interface ExpoPlatformService {
  readonly name: string;
  invoke(methodName: string, argumentsValue: ESObject[]): Promise<ESObject>;
  invokeSync?(methodName: string, argumentsValue: ESObject[]): ESObject;
}

export interface ExpoPlatformServiceResult {
  readonly ok: boolean;
  readonly value?: ESObject;
  readonly code?: string;
  readonly message?: string;
}

export class ExpoPlatformServiceError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    if (!/^ERR_[A-Z0-9_]+$/.test(code)) {
      throw new Error(`Invalid Expo platform service error code '${code}'.`);
    }
    this.name = 'ExpoPlatformServiceError';
    this.code = code;
  }
}

export interface ExpoPlatformServiceFactory {
  readonly name: string;
  create(context: UITurboModuleContext): ExpoPlatformService | Promise<ExpoPlatformService>;
}

interface ExpoPlatformServiceErrorLike {
  readonly code?: string;
  readonly message?: string;
}

/**
 * Registry for copy-value-only Harmony platform services. Service objects must
 * never retain Hermes/JSI values; calls cross RNOH's ArkTS TurboModule bridge.
 */
export class ExpoPlatformServiceRegistry {
  private static readonly factories: Map<string, ExpoPlatformServiceFactory> = new Map();
  private readonly services: Map<string, ExpoPlatformService>;

  private constructor(services: Map<string, ExpoPlatformService>) {
    this.services = services;
  }

  static register(factory: ExpoPlatformServiceFactory): () => void {
    if (factory.name.length === 0) {
      throw new Error('Expo platform service names cannot be empty.');
    }
    if (ExpoPlatformServiceRegistry.factories.has(factory.name)) {
      throw new Error(`Expo platform service '${factory.name}' was registered twice.`);
    }
    ExpoPlatformServiceRegistry.factories.set(factory.name, factory);
    return (): void => {
      if (ExpoPlatformServiceRegistry.factories.get(factory.name) === factory) {
        ExpoPlatformServiceRegistry.factories.delete(factory.name);
      }
    };
  }

  static async createScope(context: UITurboModuleContext): Promise<ExpoPlatformServiceRegistry> {
    const services = new Map<string, ExpoPlatformService>();
    const factories = Array.from(ExpoPlatformServiceRegistry.factories.entries());
    for (let index = 0; index < factories.length; ++index) {
      const name = factories[index][0];
      const factory = factories[index][1];
      const service = await factory.create(context);
      if (service.name !== name) {
        throw new Error(
          `Expo platform service factory '${name}' created service '${service.name}'.`,
        );
      }
      services.set(name, service);
    }
    return new ExpoPlatformServiceRegistry(services);
  }

  require(name: string): ExpoPlatformService {
    const service = this.services.get(name);
    if (service === undefined) {
      throw new Error(`Expo platform service '${name}' is not registered.`);
    }
    return service;
  }

  async invoke(
    name: string,
    methodName: string,
    argumentsValue: ESObject[],
  ): Promise<ExpoPlatformServiceResult> {
    try {
      const value: ESObject = await this.require(name).invoke(methodName, argumentsValue);
      return { ok: true, value };
    } catch (error) {
      return platformServiceFailure(error);
    }
  }

  invokeSync(
    name: string,
    methodName: string,
    argumentsValue: ESObject[],
  ): ExpoPlatformServiceResult {
    try {
      const service = this.require(name);
      if (service.invokeSync === undefined) {
        return {
          ok: false,
          code: 'ERR_PLATFORM_ASYNC_SERVICE',
          message: `Platform service '${name}' does not expose synchronous methods.`,
        };
      }
      return { ok: true, value: service.invokeSync(methodName, argumentsValue) };
    } catch (error) {
      return platformServiceFailure(error);
    }
  }
}

function platformServiceFailure(error: Object): ExpoPlatformServiceResult {
  let structuredCode: string | undefined = undefined;
  let structuredMessage: string | undefined = undefined;
  try {
    if (error !== null && typeof error === 'object') {
      const structured = error as ExpoPlatformServiceErrorLike;
      const candidateCode = structured.code;
      const candidateMessage = structured.message;
      structuredCode = typeof candidateCode === 'string' &&
        /^ERR_[A-Z0-9_]+$/.test(candidateCode) ? candidateCode : undefined;
      structuredMessage = typeof candidateMessage === 'string' ? candidateMessage : undefined;
    }
  } catch (_) {
    // A third-party adapter may reject with an object whose getters throw.
    // Treat it as an opaque value and use the safe fallback below.
  }
  if (structuredCode !== undefined) {
    return {
      ok: false,
      code: structuredCode,
      message: structuredMessage !== undefined && structuredMessage.length > 0
        ? structuredMessage
        : structuredCode,
    };
  }

  // Keep text parsing only for legacy platform adapters. New adapters should
  // throw ExpoPlatformServiceError (or an Error-compatible object with code).
  let rawMessage = 'The Harmony platform service failed.';
  try {
    rawMessage = String(error).replace(/^(?:Error:\s*)+/, '');
  } catch (_) {
    // String conversion itself can invoke a hostile toString/valueOf getter.
  }
  const match = rawMessage.match(/^(ERR_[A-Z0-9_]+)(?::\s*|\s+-\s+)?(.*)$/s);
  if (match !== null) {
    return {
      ok: false,
      code: match[1],
      message: match[2].length > 0 ? match[2] : rawMessage,
    };
  }
  return {
    ok: false,
    code: 'ERR_PLATFORM_ADAPTER',
    message: rawMessage.length > 0 ? rawMessage : 'The Harmony platform service failed.',
  };
}
