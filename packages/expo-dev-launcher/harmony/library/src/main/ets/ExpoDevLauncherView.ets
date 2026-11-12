/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type { ReactRootViewContext } from '@expo-harmony/expo-modules-core';
import { DevMenuPreference } from '@expo-harmony/expo-dev-menu';
import { DevLauncherController, DevLauncherViewState } from './DevLauncherController';
import { DiscoveredServer } from './DevServerDiscovery';
import { RecentApp } from './RecentApps';
@Builder
export function buildExpoDevLauncherRoot(context: ReactRootViewContext): void {
  if (context.ready) {
    context.defaultRoot.builder(context);
  } else {
    ExpoDevLauncherView({ controller: DevLauncherController.get(context.core.uiAbilityContext.getApplicationContext()) });
  }
}
@Component
export struct ExpoDevLauncherView {
  @Require public controller!: DevLauncherController;
  @State private state: DevLauncherViewState = new DevLauncherViewState(false, 0, undefined, [], []);
  @State private address: string = '';
  @State private slug: string = '';
  private unsubscribe?: () => void;

  aboutToAppear(): void {
    this.unsubscribe = this.controller.subscribe((state: DevLauncherViewState): void => {
      this.state = state;
    });
    this.slug = this.state.filterBySlug;
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private open(url: string): void {
    this.address = url;
    this.controller.load(url).catch((): void => {});
  }

  @Builder
  private preference(label: string, key: DevMenuPreference): void {
    Row({ space: 12 }) {
      Text(label).fontSize(15).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.state.settings[key] ?? false })
        .enabled(!this.state.loading)
        .onChange((value: boolean): void => {
          this.controller.setPreference(key, value).catch((): void => {});
        })
    }.width('100%')
  }

  build(): void {
    Scroll() {
      Column({ space: 16 }) {
        Text('Expo Dev Launcher')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#111827')
          .width('100%')
        Text('Open a Harmony development server or a compatible published update.')
          .fontSize(15)
          .fontColor('#6B7280')
          .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.address, placeholder: 'http://192.168.1.2:8081' })
            .type(InputType.URL)
            .enterKeyType(EnterKeyType.Go)
            .onSubmit((): void => {
              if (!this.state.loading && this.address.trim().length > 0) this.open(this.address);
            })
            .onChange((value: string): void => {
              this.address = value;
            })
            .enabled(!this.state.loading)
            .layoutWeight(1)
            .height(48)
          Button('Open')
            .enabled(!this.state.loading && this.address.trim().length > 0)
            .onClick((): void => this.open(this.address))
        }.width('100%')

        Button('Scan QR code', { type: ButtonType.Normal })
          .width('100%')
          .enabled(!this.state.loading)
          .onClick((): void => {
            this.controller.scan().catch((): void => {});
          })

        if (this.state.hasEmbeddedBundle) {
          Button('Load embedded bundle', { type: ButtonType.Normal })
            .width('100%')
            .enabled(!this.state.loading)
            .onClick((): void => {
              this.controller.loadEmbeddedBundle().catch((): void => {});
            })
        }

        if (this.state.loading) {
          Column({ space: 8 }) {
            Text('Loading project…')
              .fontSize(14)
              .fontColor('#374151')
            Progress({ value: Math.round(this.state.progress * 100), total: 100, type: ProgressType.Linear }).width('100%')
          }
          .padding(16)
          .borderRadius(12)
          .backgroundColor('#F3F4F6')
          .width('100%');
        }

        if (this.state.error !== undefined) {
          Text(this.state.error)
            .fontSize(14)
            .fontColor('#B91C1C')
            .backgroundColor('#FEF2F2')
            .borderRadius(12)
            .padding(16)
            .width('100%');
          Row({ space: 12 }) {
            if (this.state.canRetry) {
              Button('Retry', { type: ButtonType.Normal })
                .enabled(!this.state.loading)
                .onClick((): void => {
                  this.controller.retry().catch((): void => {});
                });
            }
            Button('Copy error', { type: ButtonType.Normal })
              .onClick((): void => {
                this.controller.copyError().catch((): void => {});
              });
          }.width('100%');
        }

        Row() {
          Text('Development servers')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
          Button('Refresh', { type: ButtonType.Normal })
            .enabled(!this.state.loading)
            .onClick((): void => this.controller.refreshServers())
        }.width('100%')
        if (this.state.discoveryError !== undefined) {
          Text(this.state.discoveryError).fontSize(14).fontColor('#B91C1C').width('100%');
        } else if (this.state.servers.length === 0) {
          Text(this.state.searching ? 'Searching for development servers…' : 'No development servers found.')
            .fontSize(14).fontColor('#6B7280').width('100%');
        }
        if (this.state.servers.length > 0) {
          ForEach(
            this.state.servers,
            (server: DiscoveredServer): void => {
              Button(`${server.name}\n${server.url}`, { type: ButtonType.Normal })
                .width('100%')
                .enabled(!this.state.loading)
                .onClick((): void => this.open(server.url));
            },
            (server: DiscoveredServer): string => server.id,
          );
        }

        Text('Settings').fontSize(18).fontWeight(FontWeight.Medium).width('100%')
        this.preference('Auto-launch most recent project', DevMenuPreference.TryToLaunchLastBundle)
        this.preference('Show Dev Menu at launch', DevMenuPreference.ShowsAtLaunch)
        this.preference('Show floating tools button', DevMenuPreference.ShowFab)
        this.preference('Touch gesture to open Dev Menu', DevMenuPreference.TouchGesture)
        Row({ space: 8 }) {
          TextInput({ text: this.slug, placeholder: 'Filter servers by project slug (optional)' })
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.slug = value;
            })
          Button('Apply', { type: ButtonType.Normal })
            .enabled(!this.state.loading)
            .onClick((): void => {
              this.controller.setDiscoveryFilter(this.slug).catch((): void => {});
            })
        }.width('100%')

        if (this.state.recent.length > 0) {
          Row() {
            Text('Recently opened')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
            Button('Clear', { type: ButtonType.Normal })
              .enabled(!this.state.loading)
              .onClick((): void => {
                this.controller.clearHistory().catch((): void => {});
              })
          }.width('100%');
          ForEach(
            this.state.recent,
            (app: RecentApp): void => {
              Button(`${app.name}\n${app.url}`, { type: ButtonType.Normal })
                .width('100%')
                .enabled(!this.state.loading)
                .onClick((): void => this.open(app.url));
            },
            (app: RecentApp): string => app.url,
          );
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 48, bottom: 48 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF');
  }
}
