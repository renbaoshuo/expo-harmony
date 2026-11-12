/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import {
  ExpoFunction,
  ExpoModule,
  ExpoModuleContext,
  ExpoModuleDefinition,
  ExpoModuleError,
  ExpoValueTypes,
  ExpoView,
  ExpoViewContext,
  ExpoViewContentContext,
  ExpoViewDefinition,
} from '@expo-harmony/expo-modules-core';
import { expoLogBoxController } from './ExpoLogBoxController';
import { ExpoLogBoxWebSession, ExpoLogBoxWebView } from './ExpoLogBoxWebView';
import { pasteboard } from '@kit.BasicServicesKit';

interface MessageEvent {
  data: string;
}

@Observed
class LogBoxView extends ExpoView {
  session: ExpoLogBoxWebSession | undefined = undefined;
  payload: string = '';
  error: string = '';

  constructor(context: ExpoViewContext) {
    super(context);
  }

  update(): void {
    if (this.payload.length === 0 || !expoLogBoxController.isEnabled()) return;
    if (this.session !== undefined) {
      this.session.updateProps(this.payload);
      return;
    }
    this.session = new ExpoLogBoxWebSession(
      this.payload,
      '',
      (data: string): void => this.sendEvent<MessageEvent>('onMessage', { data }),
      (): void => {},
      (error: Object): void => {
        this.error = error instanceof Error ? error.message : String(error);
      },
    );
  }

  retry(): void {
    this.session?.dispose();
    this.session = undefined;
    this.error = '';
    this.update();
  }

  minimize(): void {
    this.sendEvent<MessageEvent>('onMessage', {
      data: '{"type":"$$native_action","data":{"uid":"native-fallback-minimize","actionId":"onMinimize","args":[]}}',
    });
  }

  destroy(): void {
    this.session?.dispose();
    this.session = undefined;
  }
}

@Component
struct LogBoxContent {
  @ObjectLink view: LogBoxView;

  build(): void {
    if (this.view.error.length > 0) {
      Column({ space: 16 }) {
        Text('Expo LogBox could not load').fontColor(Color.White)
        Text(this.view.error).fontColor(Color.White)
        Button('Retry')
          .onClick((): void => this.view.retry())
        Button('Minimize')
          .onClick((): void => this.view.minimize())
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#111113')
      .justifyContent(FlexAlign.Center);
    } else if (this.view.session !== undefined) {
      ExpoLogBoxWebView({ session: this.view.session });
    }
  }
}

@Builder
function buildLogBoxView(context: ExpoViewContentContext): void {
  LogBoxContent({ view: context.nativeView as LogBoxView });
}

export class ExpoLogBoxModule extends ExpoModule {
  constructor(context: ExpoModuleContext) {
    super(context);
  }

  override definition(): ExpoModuleDefinition {
    const view = new ExpoViewDefinition<LogBoxView>(
      'LogBoxView',
      (context: ExpoViewContext): LogBoxView => new LogBoxView(context),
      wrapBuilder(buildLogBoxView),
    )
      .events(['onMessage'])
      .prop(
        'payload',
        ExpoValueTypes.string(),
        (view: LogBoxView, value: string): void => {
          view.payload = value;
        },
        '',
      )
      .asyncFunction(
        'injectJavaScript',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), async (view: LogBoxView, script: string): Promise<void> => {
          await view.session?.inject(script);
        }),
      )
      .onDidUpdateProps((view: LogBoxView): void => view.update())
      .onDestroy((view: LogBoxView): void => view.destroy());

    const constants: Record<string, ESObject> = { 'enabled': expoLogBoxController.isEnabled() };
    return new ExpoModuleDefinition()
      .name('ExpoLogBox')
      .constants(constants)
      .asyncFunction(
        'copyTextAsync',
        ExpoFunction.typed1(ExpoValueTypes.string(), async (text: string): Promise<void> => {
          if (!expoLogBoxController.isEnabled()) throw new ExpoModuleError('ERR_LOG_BOX_DISABLED', 'Expo LogBox is disabled.');
          await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
        }),
      )
      .view(view);
  }
}
