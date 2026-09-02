import { ComponentBuilderContext, RNComponentContext, RNViewBase } from '@rnoh/react-native-openharmony';
import type { Descriptor } from '@rnoh/react-native-openharmony/ts';
import {
  EXPO_MODULES_CORE_VIEW_COMPONENT_NAME,
  EXPO_MODULE_NAME_PROP,
  EXPO_VIEW_REVISION_PROP,
  EXPO_VIEW_NAME_PROP,
  ExpoViewAdapter,
  ExpoViewAdapterRegistry,
  ExpoViewContentContext,
} from './ExpoViewTypes';
import { EXPO_VIEW_EVENT, EXPO_VIEW_PHASE_CREATE, EXPO_VIEW_PHASE_DESTROY, EXPO_VIEW_PHASE_PROPS } from '../protocol/Protocol';
import { ExpoModuleError } from '../modules/ExpoModuleError';
@Builder
export function buildExpoView(ctx: ComponentBuilderContext) {
  ExpoView({
    ctx: ctx.rnComponentContext,
    tag: ctx.tag,
    fabricComponentName: ctx.componentName,
  });
}

@Component
struct ExpoView {
  @Require public ctx!: RNComponentContext;
  @Require public tag: number = 0;
  @Require public fabricComponentName: string = '';
  private logicalComponentName: string = '';
  private adapter?: ExpoViewAdapter;
  private nativeView: ESObject = {};
  private contentContext?: ExpoViewContentContext;
  private cleanupCallbacks: (() => void)[] = [];
  private hasNativeView: boolean = false;
  private isBound: boolean = false;
  private createPhaseStarted: boolean = false;

  aboutToAppear(): void {
    try {
      const descriptor = this.ctx.descriptorRegistry.getDescriptor<Descriptor>(this.tag);
      const props = descriptor.rawProps as Record<string, ESObject>;
      this.logicalComponentName = resolveLogicalComponentName(this.fabricComponentName, props);

      const adapter = ExpoViewAdapterRegistry.require(this.ctx.rnInstance.getId(), this.logicalComponentName);
      this.adapter = adapter;
      this.nativeView = adapter.create(this.ctx, this.tag, this.logicalComponentName);
      this.hasNativeView = true;

      this.contentContext = adapter.createContentContext(this.nativeView);

      ExpoViewAdapterRegistry.bind(this.ctx.rnInstance.getId(), this.tag, this.logicalComponentName, adapter, this.nativeView);
      this.isBound = true;

      // Record the phase before posting so rollback can notify C++ if posting throws.
      this.createPhaseStarted = true;
      this.ctx.rnInstance.postMessageToCpp(EXPO_VIEW_EVENT, {
        phase: EXPO_VIEW_PHASE_CREATE,
        tag: this.tag,
        componentName: this.logicalComponentName,
      });
      this.updateDescriptor(descriptor);

      // Store each disposer as soon as it is created.
      this.trackCleanup(
        this.ctx.descriptorRegistry.subscribeToDescriptorChanges(this.tag, (nextDescriptor: Descriptor) =>
          this.updateDescriptorFromSubscription(nextDescriptor),
        ),
      );
    } catch (error) {
      this.rollbackMount();

      if (error instanceof ExpoModuleError) {
        throw new ExpoModuleError(error.code, error.message, error.cause, error.path);
      }
      if (error instanceof Error) throw new Error(error.message);
      throw new Error(String(error));
    }
  }

  aboutToDisappear(): void {
    this.teardownView();
  }

  private trackCleanup(callback: () => void): void {
    this.cleanupCallbacks.push(callback);
  }

  private rollbackMount(): void {
    this.teardownView();
  }

  private teardownView(): void {
    const callbacks = this.cleanupCallbacks.splice(0);
    for (let index = callbacks.length - 1; index >= 0; --index) {
      try {
        callbacks[index]();
      } catch (error) {
        reportViewCleanupFailure(`subscription ${index}`, error);
      }
    }

    if (this.createPhaseStarted) {
      this.createPhaseStarted = false;
      try {
        this.ctx.rnInstance.postMessageToCpp(EXPO_VIEW_EVENT, {
          phase: EXPO_VIEW_PHASE_DESTROY,
          tag: this.tag,
          componentName: this.logicalComponentName,
        });
      } catch (error) {
        reportViewCleanupFailure('native destroy message', error);
      }
    }

    const adapter = this.adapter;
    const nativeView: ESObject = this.nativeView;
    const wasBound = this.isBound;
    const hadNativeView = this.hasNativeView;
    this.isBound = false;
    this.hasNativeView = false;
    this.adapter = undefined;
    this.contentContext = undefined;
    this.nativeView = {};
    this.logicalComponentName = '';

    if (wasBound) {
      try {
        ExpoViewAdapterRegistry.destroyBoundView(this.ctx.rnInstance.getId(), this.tag);
      } catch (error) {
        reportViewCleanupFailure('view registry', error);
      }
    } else if (hadNativeView && adapter?.destroy !== undefined) {
      // Without a registry entry, rollback must release the view directly.
      try {
        adapter.destroy(nativeView);
      } catch (error) {
        reportViewCleanupFailure('unbound native view', error);
      }
    }
  }

  private updateDescriptor(descriptor: Descriptor): void {
    if (this.adapter === undefined || descriptor === undefined) return;

    const props = descriptor.rawProps as Record<string, ESObject>;
    const rawRevision: ESObject = props[EXPO_VIEW_REVISION_PROP];
    const revision: number | undefined =
      typeof rawRevision === 'number' && Number.isSafeInteger(rawRevision) && rawRevision > 0 ? rawRevision : undefined;

    try {
      const requiredRevision: number = requirePropsRevision(props, this.tag);
      const logicalComponentName = resolveLogicalComponentName(this.fabricComponentName, props);

      if (logicalComponentName !== this.logicalComponentName) {
        throw new Error(
          `ERR_VIEW_ROUTE_CHANGED: Expo view tag ${this.tag} cannot change from ` + `'${this.logicalComponentName}' to '${logicalComponentName}'.`,
        );
      }

      const authorProps = this.fabricComponentName === EXPO_MODULES_CORE_VIEW_COMPONENT_NAME ? withoutExpoRouteProps(props) : props;

      this.adapter.updateProps(this.nativeView, authorProps);
      this.ctx.rnInstance.postMessageToCpp(EXPO_VIEW_EVENT, {
        phase: EXPO_VIEW_PHASE_PROPS,
        tag: this.tag,
        componentName: this.logicalComponentName,
        props: authorProps,
      });

      ExpoViewAdapterRegistry.markPropsCommitted(this.ctx.rnInstance.getId(), this.tag, this.logicalComponentName, requiredRevision);
    } catch (error) {
      const failure: Error = toViewUpdateError(this.tag, revision, error);
      if (this.isBound) {
        try {
          ExpoViewAdapterRegistry.markPropsFailed(this.ctx.rnInstance.getId(), this.tag, this.logicalComponentName, revision, failure);
        } catch (registryError) {
          reportViewCleanupFailure('props failure state', registryError);
        }
      }
      throw failure;
    }
  }

  private updateDescriptorFromSubscription(descriptor: Descriptor): void {
    try {
      this.updateDescriptor(descriptor);
    } catch (error) {
      reportViewUpdateFailure(this.tag, this.logicalComponentName, error);
    }
  }

  private contentBuilder(): WrappedBuilder<[ExpoViewContentContext]> {
    return this.adapter!.content!;
  }

  @Builder
  private buildContent(): void {
    if (this.adapter?.content !== undefined && this.contentContext !== undefined) {
      this.contentBuilder().builder(this.contentContext);
    }
    if (this.adapter?.content === undefined || this.adapter?.group === true) {
      this.ctx.wrappedRNChildrenBuilder.builder(this.ctx, this.tag);
    }
  }

  build(): void {
    RNViewBase({ ctx: this.ctx, tag: this.tag }) {
      this.buildContent()
    };
  }
}

function resolveLogicalComponentName(fabricComponentName: string, props: Record<string, ESObject>): string {
  if (fabricComponentName !== EXPO_MODULES_CORE_VIEW_COMPONENT_NAME) {
    return fabricComponentName;
  }

  const moduleName: ESObject = props[EXPO_MODULE_NAME_PROP];

  if (typeof moduleName !== 'string' || moduleName.length === 0) {
    throw new Error(`ERR_INVALID_VIEW_ROUTE: '${EXPO_MODULES_CORE_VIEW_COMPONENT_NAME}' requires a non-empty ` + `'${EXPO_MODULE_NAME_PROP}' prop.`);
  }

  const viewName: ESObject = props[EXPO_VIEW_NAME_PROP];

  if (viewName === undefined || viewName === null || viewName === '') {
    return `ViewManagerAdapter_${moduleName}`;
  }

  if (typeof viewName !== 'string') {
    throw new Error(`ERR_INVALID_VIEW_ROUTE: '${EXPO_VIEW_NAME_PROP}' must be a string when provided.`);
  }

  return `ViewManagerAdapter_${moduleName}_${viewName}`;
}

function withoutExpoRouteProps(props: Record<string, ESObject>): Record<string, ESObject> {
  const output: Record<string, ESObject> = {};

  Object.keys(props).forEach((name: string): void => {
    if (name === EXPO_MODULE_NAME_PROP || name === EXPO_VIEW_REVISION_PROP || name === EXPO_VIEW_NAME_PROP) return;

    output[name] = props[name];
  });

  return output;
}

function requirePropsRevision(props: Record<string, ESObject>, tag: number): number {
  const revision: ESObject = props[EXPO_VIEW_REVISION_PROP];
  if (typeof revision !== 'number' || !Number.isSafeInteger(revision) || revision <= 0) {
    throw new Error(`ERR_INVALID_VIEW_REVISION: Expo view tag ${tag} requires a positive safe-integer ` + `'${EXPO_VIEW_REVISION_PROP}' prop.`);
  }

  return revision;
}

function reportViewCleanupFailure(step: string, error: Object): void {
  let message = 'unknown error';
  try {
    message = String(error);
  } catch (_) {}

  try {
    console.error(`Expo View cleanup failed for ${step}: ${message}`);
  } catch (_) {}
}

function toViewUpdateError(tag: number, revision: number | undefined, error: Object): Error {
  const suffix: string = revision === undefined ? 'an invalid revision' : `revision ${revision}`;
  if (error instanceof Error) {
    return new ExpoModuleError('ERR_VIEW_PROPS_UPDATE_FAILED', `Expo view tag ${tag} failed to apply ${suffix}: ${error.message}`, error);
  }
  return new ExpoModuleError('ERR_VIEW_PROPS_UPDATE_FAILED', `Expo view tag ${tag} failed to apply ${suffix}: ${String(error)}`, error);
}

function reportViewUpdateFailure(tag: number, componentName: string, error: Object): void {
  let message = 'unknown error';
  try {
    message = error instanceof Error ? error.message : String(error);
  } catch (_) {}

  try {
    console.error(`Expo View '${componentName}'#${tag} props update failed: ${message}`);
  } catch (_) {}
}
