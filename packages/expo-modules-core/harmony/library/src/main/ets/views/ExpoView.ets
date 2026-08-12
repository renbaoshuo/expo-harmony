import {
  ComponentBuilderContext,
  RNComponentContext,
  RNViewBase,
} from '@rnoh/react-native-openharmony';
import type { Descriptor } from '@rnoh/react-native-openharmony/ts';
import {
  ExpoViewAdapter,
  ExpoViewAdapterRegistry,
  ExpoViewContentContext,
} from './ExpoViewTypes';
import {
  EXPO_VIEW_COMMAND,
  EXPO_VIEW_EVENT,
  EXPO_VIEW_EVENT_EMIT,
  EXPO_VIEW_PHASE_CREATE,
  EXPO_VIEW_PHASE_DESTROY,
  EXPO_VIEW_PHASE_PROPS,
} from '../protocol/Protocol';

@Builder
export function buildExpoView(ctx: ComponentBuilderContext) {
  ExpoView({
    ctx: ctx.rnComponentContext,
    tag: ctx.tag,
    componentName: ctx.componentName,
  });
}

@Component
struct ExpoView {
  @Require public ctx!: RNComponentContext;
  @Require public tag: number = 0;
  @Require public componentName: string = '';
  private adapter?: ExpoViewAdapter;
  private nativeView: ESObject = {};
  private contentContext?: ExpoViewContentContext;
  private cleanUpCallbacks: (() => void)[] = [];

  aboutToAppear(): void {
    const adapter = ExpoViewAdapterRegistry.require(this.componentName);
    this.adapter = adapter;
    this.nativeView = adapter.create(
      this.ctx,
      this.tag,
      this.componentName,
    );
    this.contentContext = new ExpoViewContentContext(
      this.ctx,
      this.tag,
      this.componentName,
      this.nativeView,
    );
    ExpoViewAdapterRegistry.bind(this.ctx.rnInstance.getId(), this.tag, adapter, this.nativeView);
    this.ctx.rnInstance.postMessageToCpp(EXPO_VIEW_EVENT, {
      phase: EXPO_VIEW_PHASE_CREATE,
      tag: this.tag,
      componentName: this.componentName,
    });
    const descriptor = this.ctx.descriptorRegistry.getDescriptor<Descriptor>(this.tag);
    this.updateDescriptor(descriptor);
    this.cleanUpCallbacks.push(
      this.ctx.descriptorRegistry.subscribeToDescriptorChanges(
        this.tag,
        (nextDescriptor: Descriptor) => this.updateDescriptor(nextDescriptor),
      ),
      this.ctx.rnInstance.cppEventEmitter.subscribe(
        EXPO_VIEW_COMMAND,
        (payload: ESObject) => {
          if (payload.tag !== this.tag) return;
          const values: ESObject[] = Array.isArray(payload.arguments)
            ? payload.arguments as ESObject[]
            : [];
          ExpoViewAdapterRegistry.dispatchCommand(
            this.ctx.rnInstance.getId(),
            this.tag,
            payload.commandName as string,
            values,
          );
        },
      ),
      this.ctx.rnInstance.cppEventEmitter.subscribe(
        EXPO_VIEW_EVENT_EMIT,
        (payload: ESObject) => {
          if (payload.tag !== this.tag ||
              payload.componentName !== this.componentName) return;
          this.ctx.rnInstance.emitComponentEvent(
            this.tag,
            payload.eventName as string,
            payload.payload ?? {},
          );
        },
      ),
    );
  }

  aboutToDisappear(): void {
    this.cleanUpCallbacks.forEach((callback) => callback());
    this.cleanUpCallbacks = [];
    this.ctx.rnInstance.postMessageToCpp(EXPO_VIEW_EVENT, {
      phase: EXPO_VIEW_PHASE_DESTROY,
      tag: this.tag,
      componentName: this.componentName,
    });
    this.adapter?.destroy?.(this.nativeView);
    ExpoViewAdapterRegistry.unbind(this.ctx.rnInstance.getId(), this.tag);
  }

  private updateDescriptor(descriptor: Descriptor): void {
    if (this.adapter === undefined || descriptor === undefined) return;
    const props = descriptor.rawProps as Record<string, ESObject>;
    this.adapter.updateProps(this.nativeView, props);
    this.ctx.rnInstance.postMessageToCpp(EXPO_VIEW_EVENT, {
      phase: EXPO_VIEW_PHASE_PROPS,
      tag: this.tag,
      componentName: this.componentName,
      props,
    });
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
      this.buildContent();
    }
  }
}
