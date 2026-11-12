/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

const PACKAGER_CLIENT_STORAGE_KEY: string = 'jsPackagerClient';

export class RnohPackagerClient {
  private readonly client: ESObject = AppStorage.get(PACKAGER_CLIENT_STORAGE_KEY);

  isCurrent(): boolean {
    return this.client === AppStorage.get(PACKAGER_CLIENT_STORAGE_KEY);
  }

  restore(): void {
    if (this.client === undefined) AppStorage.delete(PACKAGER_CLIENT_STORAGE_KEY);
    else AppStorage.setOrCreate(PACKAGER_CLIENT_STORAGE_KEY, this.client);
  }

  destroy(release: () => void): void {
    const previous = new RnohPackagerClient();
    this.restore();
    try {
      release();
    } finally {
      // RNOH destroys the AppStorage client when it tears down a coordinator.
      if (previous.client === this.client) AppStorage.delete(PACKAGER_CLIENT_STORAGE_KEY);
      else previous.restore();
    }
  }
}
