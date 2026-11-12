/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModule, ExpoModuleDefinition, ExpoValueTypes, ExpoViewContext, ExpoViewDefinition } from '@expo-harmony/expo-modules-core';
import { DomWebView, buildDomWebView } from './DomWebView';
import { SOURCE, SCROLL_TO } from './DomWebViewRecords';

export class ExpoDomWebViewModule extends ExpoModule {
  private readonly views: Set<DomWebView> = new Set();
  private readonly documents: Map<number, DomWebView> = new Map();

  definition(): ExpoModuleDefinition {
    const view = new ExpoViewDefinition<DomWebView>(
      'DomWebView',
      (context: ExpoViewContext): DomWebView => {
        const view = new DomWebView(
          context,
          (id: number, view: DomWebView): void => {
            this.documents.set(id, view);
          },
          (id: number): void => {
            this.documents.delete(id);
          },
        );
        this.views.add(view);

        return view;
      },
      wrapBuilder(buildDomWebView),
    )
      .events(['onMessage', 'onRenderProcessGone', 'onContentProcessDidTerminate'])
      .prop('source', SOURCE, (view: DomWebView, source: Record<string, ESObject>): void => {
        view.source = (source['uri'] as string | null | undefined) ?? null;
      })
      .prop(
        'injectedJavaScriptBeforeContentLoaded',
        ExpoValueTypes.string(),
        (view: DomWebView, script: string): void => {
          view.script = script;
        },
        '',
      )
      .prop(
        'injectedJavaScript',
        ExpoValueTypes.string(),
        (view: DomWebView, script: string): void => {
          view.endScript = script;
        },
        '',
      )
      .prop(
        'injectedJavaScriptObject',
        ExpoValueTypes.string(),
        (view: DomWebView, source: string): void => {
          view.injectedObjectJson = source;
        },
        '{}',
      )
      .prop(
        'useExpoModulesBridge',
        ExpoValueTypes.boolean(),
        (view: DomWebView, enabled: boolean): void => {
          view.setExpoModulesBridge(enabled);
        },
        false,
      )
      .prop(
        'mediaPlaybackRequiresUserAction',
        ExpoValueTypes.boolean(),
        (view: DomWebView, enabled: boolean): void => {
          view.mediaPlaybackRequiresUserAction = enabled;
        },
        true,
      )
      .prop(
        'webviewDebuggingEnabled',
        ExpoValueTypes.boolean(),
        (view: DomWebView, enabled: boolean): void => {
          view.debugging = enabled;
        },
        false,
      )
      .prop(
        'showsHorizontalScrollIndicator',
        ExpoValueTypes.boolean(),
        (view: DomWebView, enabled: boolean): void => {
          view.horizontal = enabled;
        },
        true,
      )
      .prop(
        'showsVerticalScrollIndicator',
        ExpoValueTypes.boolean(),
        (view: DomWebView, enabled: boolean): void => {
          view.vertical = enabled;
        },
        true,
      )
      .prop(
        'nestedScrollEnabled',
        ExpoValueTypes.boolean(),
        (view: DomWebView, enabled: boolean): void => {
          view.nested = enabled;
        },
        true,
      )
      .asyncFunction(
        'injectJavaScript',
        ExpoFunction.ownedTyped1(ExpoValueTypes.string(), (view: DomWebView, script: string): Promise<void> => view.injectJavaScript(script)),
      )
      .asyncFunction(
        'reload',
        ExpoFunction.ownedTyped0((view: DomWebView): Promise<void> => view.reload()),
      )
      .asyncFunction(
        'scrollTo',
        ExpoFunction.ownedTyped1(SCROLL_TO, (view: DomWebView, params: Record<string, ESObject>): Promise<void> => view.scrollTo(params)),
      )
      .onDidUpdateProps((view: DomWebView): void => view.commitProps())
      .onDestroy((view: DomWebView): void => {
        this.views.delete(view);
        view.destroy();
      });

    return new ExpoModuleDefinition()
      .name('ExpoDomWebViewModule')
      .view(view)
      .asyncFunction(
        'evalJsForWebViewAsync',
        ExpoFunction.typed2(ExpoValueTypes.number(), ExpoValueTypes.string(), async (id: number, source: string): Promise<void> => {
          await this.documents.get(id)?.injectForDocument(id, source);
        }),
      )
      .onDestroy((): void => {
        this.views.forEach((view: DomWebView): void => view.destroy());
        this.views.clear();
        this.documents.clear();
      });
  }
}
