/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { UpdatesDownloader } from '../UpdatesDownloader';
import { UpdatesStorage, isVerifiedAsset } from '../UpdatesStorage';
import { UpdatesConfiguration } from '../UpdatesConfiguration';
import { UpdateRecord } from '../UpdatesProtocol';
import { UpdatesSelectionPolicy } from '../selectionpolicy/UpdatesSelectionPolicy';

export type AssetHeaders = (update: UpdateRecord) => Promise<Record<string, string>>;

export class UpdatesDatabaseLauncher {
  constructor(private readonly storage: UpdatesStorage, private readonly downloader: UpdatesDownloader,
    private readonly policy: UpdatesSelectionPolicy, private readonly embedded: () => UpdateRecord | undefined) {}

  async launch(config: UpdatesConfiguration, headers: AssetHeaders): Promise<UpdateRecord | undefined> {
    const candidates = (await this.storage.launchable(config.scope)).filter(value => {
      // Older versions marked copied embedded updates as ready.
      if (!config.embedded && typeof value.manifest.launchAsset?.packagerHash === 'string') return false;
      return value.status !== 'embedded' || (config.embedded && value.id === this.embedded()?.id);
    });
    const update = this.policy.select(candidates, await this.storage.metadata(config.scope, 'filters'));
    if (!update) return undefined;

    // Leave rollback decisions after an asset failure to error recovery.
    return this.launchUpdate(update, config, headers);
  }

  async launchUpdate(update: UpdateRecord, config: UpdatesConfiguration, headers: AssetHeaders): Promise<UpdateRecord | undefined> {
    let available = update.assets.some(asset => asset.launch);

    for (let index = 0; index < update.assets.length; index++) {
      const asset = update.assets[index];
      if (await isVerifiedAsset(this.storage.directory, asset)) continue;

      const embedded = this.embedded()?.assets.find(value => asset.key !== null && value.key === asset.key && (!asset.hash || value.hash === asset.hash));

      try {
        update.assets[index] = await this.downloader.asset({ ...asset, embedded: embedded?.embedded }, await headers(update), () => {}, {
          headers: config.headers, timeout: Math.max(config.wait, 10000),
        });
      } catch (error) {
        update.assets[index] = { ...asset, path: undefined };
        this.storage.logger.log(`Unable to repair asset ${asset.key}: ${String(error)}`, 'AssetsFailedToLoad', 'warn', update.id, asset.key ?? undefined);

        if (asset.launch) available = false;
      }
    }

    if (available) {
      try {
        await this.storage.prepareDomAssets(update);
      } catch (error) {
        this.storage.logger.log(`Unable to prepare DOM assets: ${String(error)}`, 'AssetsFailedToLoad', 'warn', update.id);
        return undefined;
      }

      await this.storage.markAccessed(update.id);

      return update;
    }

    this.storage.logger.log(`Update ${update.id} has missing or corrupt assets.`, 'UpdateAssetsNotAvailable', 'warn', update.id);

    return undefined;
  }
}
