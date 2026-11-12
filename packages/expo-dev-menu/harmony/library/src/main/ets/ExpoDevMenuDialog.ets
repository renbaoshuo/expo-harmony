/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleError } from '@expo-harmony/expo-modules-core';
import { ComponentContent, UIContext } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { DevMenuDialogItem } from './DevMenuTypes';
import { DevMenuAppInfo } from './DevMenuAppInfo';
import { DevMenuPreference, DevMenuPreferences } from './DevMenuPreferences';
import { DevMenuSourceData, DevMenuSourceEntry, DevMenuSourceFile, DevMenuSourceMap } from './DevMenuSourceMap';
import { highlightSource, SourceToken } from './DevMenuSourceHighlight';

export enum DevMenuScreen {
  Main = 'main',
  Settings = 'settings',
  SourceMap = 'sourceMap',
}

@Observed
export class DevMenuDialogModel {
  screen: DevMenuScreen = DevMenuScreen.Main;
  onboarding: boolean;
  settings: Record<string, boolean>;
  error: string = '';
  copied: string = '';
  sourceFiles: DevMenuSourceFile[] = [];
  sourceLoading: boolean = false;
  sourceLoaded: boolean = false;
  selectedSource?: DevMenuSourceFile;
  sourceFilter: string = '';
  sourceFolder: string = '';
  sourceText: string = '';
  sourceTokens: SourceToken[] = [];
  sourceFontSize: number = 12;
  sourceWrap: boolean = false;
  sourceEditing: boolean = false;
  private selecting: boolean = false;
  private disposed: boolean = false;
  private readonly sources: DevMenuSourceMap;
  readonly sourceData: DevMenuSourceData = new DevMenuSourceData();
  private copyTimer?: number;

  readonly app: DevMenuAppInfo;
  items: DevMenuDialogItem[];
  readonly preferences: DevMenuPreferences;
  readonly close: () => Promise<void>;
  readonly report: (error: Error) => void;
  readonly handleKey: (event: KeyEvent) => boolean;
  readonly touchMenu: () => void;

  constructor(
    app: DevMenuAppInfo,
    sources: DevMenuSourceMap,
    items: DevMenuDialogItem[],
    preferences: DevMenuPreferences,
    close: () => Promise<void>,
    report: (error: Error) => void,
    handleKey: (event: KeyEvent) => boolean,
    touchMenu: () => void,
  ) {
    this.app = app;
    this.sources = sources;
    this.items = items;
    this.preferences = preferences;
    this.close = close;
    this.report = report;
    this.handleKey = handleKey;
    this.touchMenu = touchMenu;
    this.settings = preferences.snapshot();
    this.onboarding = !preferences.get(DevMenuPreference.OnboardingFinished);
  }

  refresh(items: DevMenuDialogItem[]): void {
    this.items = items;
    this.settings = this.preferences.snapshot();
    if (this.preferences.get(DevMenuPreference.OnboardingFinished)) this.onboarding = false;
  }

  run(action: () => void | Promise<void>): void {
    if (this.disposed) return;

    try {
      Promise.resolve(action()).catch((error: Error): void => this.fail(error));
    } catch (error) {
      this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  async select(id: string): Promise<void> {
    if (this.selecting || this.disposed) return;

    const item = this.items.find((entry: DevMenuDialogItem): boolean => entry.id === id);
    if (item === undefined || !item.enabled) return;
    this.selecting = true;
    try {
      // Android triggers the action, then starts collapsing without waiting for reload.
      const action = Promise.resolve(item.action());
      await Promise.all([action, item.shouldCollapse ? this.close() : Promise.resolve()]);
    } finally {
      this.selecting = false;
    }
  }

  async finishOnboarding(): Promise<void> {
    await this.preferences.set(DevMenuPreference.OnboardingFinished, true);
    if (!this.disposed) this.onboarding = false;
  }

  async copy(text: string, message: string): Promise<void> {
    await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
    if (this.disposed) return;
    this.copied = message;
    if (this.copyTimer !== undefined) clearTimeout(this.copyTimer);
    this.copyTimer = setTimeout((): void => {
      this.copyTimer = undefined;
      this.copied = '';
    }, 2000);
  }

  async showSources(): Promise<void> {
    this.screen = DevMenuScreen.SourceMap;
    if (this.sourceLoading || this.sourceLoaded) return;
    this.sourceLoading = true;
    this.error = '';
    try {
      const files = await this.sources.load(this.app.hostUrl, this.app.localBundlePath);
      if (!this.disposed) {
        this.sourceFiles = files;
        this.sourceLoaded = true;
        this.filterSources(this.sourceFilter);
      }
    } catch (error) {
      if (!this.disposed)
        throw new ExpoModuleError(
          error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_SOURCE_MAP',
          error instanceof Error ? error.message : String(error),
          error as Object,
        );
    } finally {
      if (!this.disposed) this.sourceLoading = false;
    }
  }

  filterSources(value: string): void {
    this.sourceFilter = value;

    const search = value.toLowerCase();
    const entries: DevMenuSourceEntry[] = [];
    const folders = new Set<string>();
    this.sourceFiles.forEach((file: DevMenuSourceFile): void => {
      if (search.length > 0) {
        if (file.path.toLowerCase().includes(search)) entries.push(new DevMenuSourceEntry(file.path, file));
        return;
      }

      const path = file.path.replace(/\\/g, '/').replace(/^\/+/, '');
      if (!path.startsWith(this.sourceFolder)) return;

      const slash = path.indexOf('/', this.sourceFolder.length);
      if (slash < 0) entries.push(new DevMenuSourceEntry(path, file));
      else folders.add(path.slice(0, slash + 1));
    });
    folders.forEach((folder: string): void => {
      entries.push(new DevMenuSourceEntry(folder));
    });
    entries.sort((left: DevMenuSourceEntry, right: DevMenuSourceEntry): number => {
      if ((left.file === undefined) !== (right.file === undefined)) return left.file === undefined ? -1 : 1;
      return left.path.localeCompare(right.path);
    });
    this.sourceData.replace(entries);
  }

  selectSource(entry: DevMenuSourceEntry): void {
    if (entry.file === undefined) {
      this.sourceFolder = entry.path;
      this.filterSources('');
    } else {
      this.selectedSource = entry.file;
      this.sourceText = entry.file.content ?? '';
      this.sourceTokens = highlightSource(this.sourceText);
      this.sourceEditing = false;
    }
  }

  sourceParent(): void {
    const parent = this.sourceFolder.slice(0, -1).lastIndexOf('/');
    this.sourceFolder = parent < 0 ? '' : this.sourceFolder.slice(0, parent + 1);
    this.filterSources('');
  }

  lineNumbers(): string {
    return this.sourceText
      .split('\n')
      .map((_line: string, index: number): string => (index + 1).toString())
      .join('\n');
  }

  fail(error: Error): void {
    this.report(error);
    if (!this.disposed) this.error = error.message;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.copyTimer !== undefined) clearTimeout(this.copyTimer);
    try {
      this.sources.dispose();
    } catch (error) {
      this.report(error instanceof Error ? error : new Error(String(error)));
    }
  }
}

@Component
struct DevMenuToggleRow {
  @ObjectLink model: DevMenuDialogModel;
  @Prop checked: boolean = false;
  @Prop available: boolean = true;
  @State pending: boolean = false;
  itemId: string = '';
  title: string = '';

  private async select(value: boolean): Promise<void> {
    this.checked = value;
    this.pending = true;

    try {
      await this.model.select(this.itemId);
    } finally {
      // Even an ignored action can change the native toggle's visual state.
      const item = this.model.items.find((entry: DevMenuDialogItem): boolean => entry.id === this.itemId);

      this.checked = item?.checked ?? false;
      this.pending = false;
    }
  }

  build(): void {
    Row() {
      Text(this.title)
        .layoutWeight(1)
        .fontSize(16)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .enabled(this.available && !this.pending)
        .accessibilityText(this.title)
        .onChange((value: boolean): void => {
          if (value !== this.checked) this.model.run((): Promise<void> => this.select(value));
        })
    }
    .width('100%')
    .padding(12);
  }
}

@Component
struct ExpoDevMenuDialog {
  @ObjectLink model: DevMenuDialogModel;

  private tokenColor(kind: string): ResourceColor {
    if (kind === 'keyword') return '#AD64C2';
    if (kind === 'string') return '#B47D32';
    if (kind === 'number') return '#4286B8';
    return kind === 'comment' ? $r('sys.color.font_secondary') : $r('sys.color.font_primary');
  }

  @Builder
  private action(title: string, action: () => void | Promise<void>, enabled: boolean = true): void {
    Button(title, { type: ButtonType.Normal })
      .width('100%')
      .height('auto')
      .padding(16)
      .borderRadius(12)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .fontColor($r('sys.color.font_primary'))
      .fontSize(16)
      .enabled(enabled)
      .onClick((): void => this.model.run(action));
  }

  @Builder
  private setting(title: string, key: DevMenuPreference, enabled: boolean = true): void {
    Row() {
      Text(title)
        .layoutWeight(1)
        .fontSize(16)
      Toggle({ type: ToggleType.Switch, isOn: this.model.settings[key] ?? false })
        .enabled(enabled)
        .onChange((value: boolean): void => {
          if (value !== this.model.preferences.get(key)) this.model.run((): Promise<void> => this.model.preferences.set(key, value));
        })
    }
    .width('100%')
    .padding(12);
  }

  @Builder
  private main(): void {
    ForEach(
      this.model.items,
      (item: DevMenuDialogItem): void => {
        if (item.checked !== undefined) {
          DevMenuToggleRow({ model: this.model, itemId: item.id, title: item.title, available: item.enabled, checked: item.checked });
        } else {
          this.action(item.title, (): Promise<void> => this.model.select(item.id), item.enabled);
        }

        if (!item.enabled && item.detail.length > 0) {
          Text(item.detail)
            .fontSize(12)
            .fontColor($r('sys.color.font_secondary'));
        }
      },
      (item: DevMenuDialogItem): string => `${item.id}-${item.enabled}-${item.checked}`,
    );
    this.setting('Tools button', DevMenuPreference.ShowFab);
    this.action('Menu settings', (): void => {
      this.model.screen = DevMenuScreen.Settings;
    });
    this.action('Source code explorer', (): Promise<void> => this.model.showSources());
    if (this.model.app.hostUrl.length > 0) {
      Text(this.model.app.hostUrl.startsWith('http://') || this.model.app.hostUrl.startsWith('https://') ? 'Connected to' : 'Bundle')
        .fontSize(12)
        .fontColor($r('sys.color.font_secondary'));
      Text(this.model.app.hostUrl)
        .fontSize(13)
        .copyOption(CopyOptions.LocalDevice)
        .width('100%');
      this.action('Copy bundle URL', (): Promise<void> => this.model.copy(this.model.app.hostUrl, 'Bundle URL copied'));
    }
    Text(`Version: ${this.model.app.appVersion ?? 'Unknown'}`).fontSize(14);
    if (this.model.app.runtimeVersion !== undefined) {
      Text(`Runtime version: ${this.model.app.runtimeVersion}`).fontSize(14);
    } else if (this.model.app.sdkVersion !== undefined) {
      Text(`SDK version: ${this.model.app.sdkVersion}`).fontSize(14);
    }
    if (this.model.app.engine !== undefined) {
      Text(`Engine: ${this.model.app.engine}`).fontSize(14);
    }
    this.action('Copy system info', (): Promise<void> => this.model.copy(this.model.app.serialize(), 'System info copied'));
  }

  @Builder
  private sourceExplorer(): void {
    if (this.model.selectedSource !== undefined) {
      this.action('Back to files', (): void => {
        this.model.selectedSource = undefined;
      });
      Text(this.model.selectedSource.path)
        .fontSize(13)
        .width('100%');
      if (this.model.selectedSource.content !== null) {
        this.action('Copy source', (): Promise<void> => this.model.copy(this.model.sourceText, 'Source copied'));
        Row({ space: 8 }) {
          Button(this.model.sourceEditing ? 'Done' : 'Edit')
            .onClick((): void => {
              this.model.sourceEditing = !this.model.sourceEditing;
            })
          Button(this.model.sourceWrap ? 'Unwrap' : 'Wrap')
            .onClick((): void => {
              this.model.sourceWrap = !this.model.sourceWrap;
            })
          Button('A−')
            .enabled(this.model.sourceFontSize > 8)
            .onClick((): void => {
              this.model.sourceFontSize -= 1;
            })
          Button('A+')
            .enabled(this.model.sourceFontSize < 24)
            .onClick((): void => {
              this.model.sourceFontSize += 1;
            })
        }.width('100%');
        if (this.model.sourceEditing) {
          Text('Edits are temporary and do not modify the running bundle.').fontSize(12);
          TextArea({ text: this.model.sourceText })
            .height(360)
            .width('100%')
            .fontFamily('monospace')
            .fontSize(this.model.sourceFontSize)
            .onChange((value: string): void => {
              this.model.sourceText = value;
              this.model.sourceTokens = highlightSource(value);
            });
        } else if (this.model.sourceWrap) {
          Row({ space: 12 }) {
            Text(this.model.lineNumbers())
              .fontFamily('monospace')
              .fontSize(this.model.sourceFontSize)
              .lineHeight(this.model.sourceFontSize * 1.5)
              .fontColor($r('sys.color.font_secondary'))
            Text() {
              ForEach(this.model.sourceTokens, (token: SourceToken): void => {
                Span(token.value).fontColor(this.tokenColor(token.kind));
              })
            }
            .fontFamily('monospace')
            .fontSize(this.model.sourceFontSize)
            .lineHeight(this.model.sourceFontSize * 1.5)
            .copyOption(CopyOptions.LocalDevice)
            .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%');
        } else {
          Scroll() {
            Row({ space: 12 }) {
              Text(this.model.lineNumbers())
                .fontFamily('monospace')
                .fontSize(this.model.sourceFontSize)
                .lineHeight(this.model.sourceFontSize * 1.5)
                .fontColor($r('sys.color.font_secondary'))
              Text() {
                ForEach(this.model.sourceTokens, (token: SourceToken): void => {
                  Span(token.value).fontColor(this.tokenColor(token.kind));
                })
              }
              .fontFamily('monospace')
              .fontSize(this.model.sourceFontSize)
              .lineHeight(this.model.sourceFontSize * 1.5)
              .copyOption(CopyOptions.LocalDevice)
            }.alignItems(VerticalAlign.Top)
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%');
        }
      } else {
        Text('Source content is not included in this source map.');
      }
    } else {
      TextInput({ text: this.model.sourceFilter, placeholder: 'Search files' })
        .onChange((value: string): void => this.model.filterSources(value));
      if (this.model.sourceLoading) {
        LoadingProgress()
          .width(32)
          .height(32);
      }
      if (!this.model.sourceLoading && !this.model.sourceLoaded) {
        this.action('Retry loading source map', (): Promise<void> => this.model.showSources());
      }
      if (this.model.sourceFolder.length > 0 && this.model.sourceFilter.length === 0) {
        this.action(`Parent folder · ${this.model.sourceFolder}`, (): void => this.model.sourceParent());
      }
      if (this.model.sourceLoaded && this.model.sourceData.totalCount() === 0) {
        Text('No files found');
      }
      List({ space: 8 }) {
        LazyForEach(
          this.model.sourceData,
          (entry: DevMenuSourceEntry): void => {
            ListItem() {
              this.action(entry.path, (): void => this.model.selectSource(entry))
            };
          },
          (entry: DevMenuSourceEntry): string => (entry.file === undefined ? entry.path : `${entry.path}:${entry.file.index}`),
        )
      }
      .width('100%')
      .height(360);
    }
  }

  build(): void {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        if (this.model.app.icon !== undefined) {
          Image(this.model.app.icon)
            .width(40)
            .height(40)
            .borderRadius(8);
        }
        Column({ space: 4 }) {
          Text(this.model.app.appName ?? 'Development menu')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
          Text(
            this.model.screen === DevMenuScreen.Main
              ? 'Development menu'
              : this.model.screen === DevMenuScreen.Settings
                ? 'Menu settings'
                : 'Source code explorer',
          )
            .fontSize(13)
            .fontColor($r('sys.color.font_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        if (this.model.screen !== DevMenuScreen.Main) {
          Button('Back')
            .onClick((): void => {
              this.model.screen = DevMenuScreen.Main;
            });
        }
        Button('Close')
          .onClick((): void => this.model.run(this.model.close))
      }.width('100%')
      Scroll() {
        Column({ space: 10 }) {
          if (this.model.onboarding) {
            Text('Welcome to your development build')
              .fontSize(24)
              .fontWeight(FontWeight.Bold);
            Text(
              'Use the tools button or hold three fingers on your app to open this menu. Connect an external keyboard and press Ctrl+D or Command+D to toggle it.',
            );
            this.action('Continue', (): Promise<void> => this.model.finishOnboarding());
          } else if (this.model.screen === DevMenuScreen.Settings) {
            this.setting('Three-finger long press', DevMenuPreference.TouchGesture);
            this.setting('Keyboard shortcuts', DevMenuPreference.KeyCommands);
            this.setting('Show at launch', DevMenuPreference.ShowsAtLaunch);
            this.setting('Tools button', DevMenuPreference.ShowFab);
            this.setting('Shake to open', DevMenuPreference.MotionGesture, false);
            Text('RNOH owns the shake detector. Its menu cannot yet be intercepted or disabled through a public API.').fontSize(13);
          } else if (this.model.screen === DevMenuScreen.SourceMap) {
            this.sourceExplorer();
          } else {
            this.main();
          }
          if (this.model.error.length > 0) {
            Text(this.model.error)
              .fontColor($r('sys.color.font_emphasize'))
              .fontSize(13);
          }
          if (this.model.copied.length > 0) {
            Text(this.model.copied).fontSize(13);
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 24 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 12 })
    .onKeyEvent((event: KeyEvent): void => {
      if (this.model.handleKey(event)) event.stopPropagation();
    })
    .parallelGesture(LongPressGesture({ fingers: 3, duration: 500, repeat: false }).onAction((): void => this.model.touchMenu()));
  }
}

@Builder
function buildExpoDevMenuDialog(model: DevMenuDialogModel): void {
  ExpoDevMenuDialog({ model });
}

export class ExpoDevMenuPresenter {
  private content?: ComponentContent<DevMenuDialogModel>;
  private ui?: UIContext;
  private model?: DevMenuDialogModel;
  private opening?: Promise<void>;
  private closing?: Promise<void>;
  private disposed: boolean = false;

  private readonly onVisibility: () => void;
  private readonly report: (error: Error) => void;
  private dismissed?: Promise<void>;
  private resolveDismissed?: () => void;
  constructor(onVisibility: () => void, report: (error: Error) => void) {
    this.onVisibility = onVisibility;
    this.report = report;
  }
  get isVisible(): boolean {
    return this.content !== undefined;
  }
  get currentScreen(): DevMenuScreen | undefined {
    return this.model?.screen;
  }

  async open(ui: UIContext, model: DevMenuDialogModel): Promise<boolean> {
    let attachedContent: ComponentContent<DevMenuDialogModel> | undefined;
    let pending: Promise<void> | undefined;

    try {
      if (this.closing !== undefined) await this.closing;
      if (this.disposed || this.content !== undefined) {
        model.dispose();
        return false;
      }

      const content = new ComponentContent<DevMenuDialogModel>(ui, wrapBuilder(buildExpoDevMenuDialog), model);
      attachedContent = content;
      this.content = content;
      this.ui = ui;
      this.model = model;
      this.dismissed = new Promise<void>((resolve: () => void): void => {
        this.resolveDismissed = resolve;
      });
      this.onVisibility();

      pending = ui.openBindSheet(content, {
        height: SheetSize.MEDIUM,
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        dragBar: true,
        showClose: false,
        onDisappear: (): void => this.release(content),
      });
      this.opening = pending;
      await pending;

      return this.content === content;
    } catch (error) {
      if (attachedContent === undefined) model.dispose();
      else this.release(attachedContent);
      throw new ExpoModuleError(
        error instanceof ExpoModuleError ? error.code : 'ERR_DEV_MENU_WINDOW',
        error instanceof Error ? error.message : String(error),
        error as Object,
      );
    } finally {
      if (this.opening === pending) this.opening = undefined;
    }
  }

  update(items: DevMenuDialogItem[]): void {
    this.model?.refresh(items);
  }
  updateConfiguration(): void {
    this.content?.updateConfiguration();
  }

  async close(): Promise<void> {
    if (this.opening !== undefined) {
      try {
        await this.opening;
      } catch (_error) {
        return;
      } // open() owns reporting/rejection and releases the failed content.
    }
    if (this.closing !== undefined) return await this.closing;

    const content = this.content;
    const ui = this.ui;
    if (content === undefined || ui === undefined) return;

    const dismissed = this.dismissed;
    const pending = Promise.resolve()
      .then((): Promise<void> => ui.closeBindSheet(content))
      .then(async (): Promise<void> => {
        await dismissed;
      })
      .catch((error: BusinessError): void => {
        // A detached window or native gesture may already have removed this sheet.
        if (error.code === 120003) this.release(content);
        else throw new ExpoModuleError('ERR_DEV_MENU_WINDOW', error.message, error);
      });
    this.closing = pending;
    try {
      await pending;
    } finally {
      if (this.closing === pending) this.closing = undefined;
    }
    // onDisappear owns disposal after the sheet's native dismissal animation.
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.model?.dispose();
    this.close().catch((error: Error): void => {
      this.report(error);
      if (this.content !== undefined) this.release(this.content);
    });
  }

  private release(content: ComponentContent<DevMenuDialogModel>): void {
    if (this.content !== content) return;
    this.model?.dispose();
    this.content = undefined;
    this.ui = undefined;
    this.model = undefined;
    this.resolveDismissed?.();
    this.resolveDismissed = undefined;
    this.dismissed = undefined;
    try {
      content.dispose();
    } finally {
      this.onVisibility();
    }
  }
}
