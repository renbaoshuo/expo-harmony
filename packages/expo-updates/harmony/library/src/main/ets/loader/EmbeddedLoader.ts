/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import type common from '@ohos.app.ability.common';
import { UpdatesConfiguration } from '../UpdatesConfiguration';
import { UpdatesDownloader } from '../UpdatesDownloader';
import { UpdatesStorage, decode } from '../UpdatesStorage';
import { UpdateRecord, parseEmbeddedUpdate } from '../UpdatesProtocol';

export class EmbeddedLoader {
  private loaded?: UpdateRecord;
  constructor(private readonly context: common.ApplicationContext, private readonly storage: UpdatesStorage,
    private readonly downloader: UpdatesDownloader, private readonly original: UpdatesConfiguration) {}

  get update(): UpdateRecord | undefined { return this.loaded; }

  async load(config: UpdatesConfiguration): Promise<UpdateRecord | undefined> {
    if (!config.embedded) return undefined;
    if (this.loaded) return this.loaded;

    const manifest = JSON.parse(decode(await this.context.resourceManager.getRawFileContent('expo-updates/manifest.json')));
    const update = parseEmbeddedUpdate(manifest, this.original.scope, this.original.runtime, this.original.url, this.original.headers);
    const stored = await this.storage.update(update.id);
    if (stored && stored.runtime === update.runtime) {
      update.time = Math.max(update.time, stored.time);
      update.successful = stored.successful;
      update.failed = stored.failed;
    }

    for (let index = 0; index < update.assets.length; index++) {
      update.assets[index] = await this.downloader.asset(update.assets[index], {}, () => {});
    }

    await this.storage.finish(update);
    this.loaded = update;

    return update;
  }
}
