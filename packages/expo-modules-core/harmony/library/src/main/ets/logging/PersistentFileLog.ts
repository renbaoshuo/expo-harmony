/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import fs from '@ohos.file.fs';
import util from '@ohos.util';

export class PersistentFileLog {
  private static tail: Promise<unknown> = Promise.resolve();
  private readonly path: string;
  private readonly lockPath: string;
  private readonly temp: string;

  constructor(category: string, filesDirectory: string) {
    if (!category || /[/\\\0]/.test(category)) throw new Error('A log category must be a nonempty file name.');

    this.path = `${filesDirectory}/dev.expo.modules.core.logging.${category}`;
    this.lockPath = `${filesDirectory}/dev.expo.modules.core.logging-lock.${category}`;
    this.temp = `${filesDirectory}/dev.expo.modules.core.logging-temp.${category}`;
  }

  readEntries(): string[] {
    const lock = fs.openSync(this.lockPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    try {
      lock.tryLock(false);
      try { return this.read(); }
      finally { lock.unlock(); }
    } finally { fs.closeSync(lock); }
  }

  readEntriesAsync(): Promise<string[]> { return this.enqueue(() => this.read()); }

  appendEntry(entry: string): Promise<void> {
    return this.enqueue(() => {
      const file = fs.openSync(this.path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      try { this.write(file, (fs.statSync(file.fd).size > 0 ? '\n' : '') + entry); }
      finally { fs.closeSync(file); }
    });
  }

  purgeEntriesNotMatchingFilter(filter: (entry: string) => boolean): Promise<void> {
    return this.updateEntries(entries => entries.filter(filter));
  }

  clearEntries(): Promise<void> {
    return this.enqueue(() => { if (fs.accessSync(this.path)) fs.unlinkSync(this.path); });
  }

  updateEntries(transform: (entries: string[]) => string[] | undefined): Promise<void> {
    return this.enqueue(() => {
      const entries = transform(this.read());
      if (entries !== undefined) this.replace(entries);
    });
  }

  private read(): string[] {
    if (!fs.accessSync(this.path)) return [];
    return fs.readTextSync(this.path).split('\n').filter(line => line.length > 0);
  }

  private write(file: fs.File, value: string): void {
    const bytes = new util.TextEncoder().encode(value);
    let offset = 0;
    while (offset < bytes.byteLength) {
      const count = fs.writeSync(file.fd, bytes.buffer.slice(offset));
      if (count <= 0) throw new Error('Log write made no progress.');
      offset += count;
    }
    fs.fsyncSync(file.fd);
  }

  private replace(entries: string[]): void {
    try {
      const file = fs.openSync(this.temp, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try { this.write(file, entries.join('\n')); }
      finally { fs.closeSync(file); }

      fs.renameSync(this.temp, this.path);
    } finally {
      if (fs.accessSync(this.temp)) fs.unlinkSync(this.temp);
    }
  }

  private enqueue<T>(body: () => T): Promise<T> {
    const run = PersistentFileLog.tail.then(async () => {
      // A stable sidecar lock also serializes ExtensionAbility processes across atomic file replacement.
      const lock = fs.openSync(this.lockPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        await lock.lock(true);
        try { return body(); }
        finally { lock.unlock(); }
      } finally { fs.closeSync(lock); }
    });
    PersistentFileLog.tail = run.catch(() => undefined);
    return run;
  }
}
