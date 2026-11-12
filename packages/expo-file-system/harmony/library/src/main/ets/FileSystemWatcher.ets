/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoModuleContext, ExpoSharedObject, fileUriFromPath } from '@expo-harmony/expo-modules-core';
import fs, { WatchEvent } from '@ohos.file.fs';
import { ExpoFileSystemError } from './NetworkPolicy';

export const DEFAULT_WATCH_DEBOUNCE_MS: number = 100;
const MAX_TIMER_INTERVAL_MS: number = 2147483647;

// fs.createWatcher uses the documented Linux inotify masks, including rename cookies.
enum WatchFlag {
  Modify = 0x00000002,
  Attribute = 0x00000004,
  MoveFrom = 0x00000040,
  MoveTo = 0x00000080,
  Create = 0x00000100,
  Delete = 0x00000200,
  DeleteSelf = 0x00000400,
  MoveSelf = 0x00000800,
  IsDirectory = 0x40000000,
}

enum WatchEventType {
  Created = 'created',
  Modified = 'modified',
  Deleted = 'deleted',
  Renamed = 'renamed',
}

class WatchEventPayload {
  type: WatchEventType;
  path: string;
  isDirectory: boolean;
  nativeEventFlags: number;
  newPath?: string;
  newPathIsDirectory?: boolean;

  constructor(type: WatchEventType, path: string, directory: boolean, flags: number) {
    this.type = type;
    this.path = fileUriFromPath(path);
    this.isDirectory = directory;
    this.nativeEventFlags = flags;
  }
}

export class FileSystemWatcher extends ExpoSharedObject {
  readonly path: string;
  private directory: boolean = false;
  private readonly debounce: number;
  private readonly eventTypes?: string[];
  private readonly watchers: Set<FileSystemWatcher>;
  private watcher?: fs.Watcher;
  private generation: number = 0;
  private timer?: number;
  private readonly childDirectories: Set<string> = new Set();
  private readonly pending: Map<string, WatchEventPayload> = new Map();
  private readonly movedFrom: Map<number, WatchEventPayload> = new Map();
  private readonly movedTo: Map<number, WatchEventPayload> = new Map();

  constructor(context: ExpoModuleContext, path: string, debounce: number, eventTypes: string[] | undefined, watchers: Set<FileSystemWatcher>) {
    super(context);
    if (!Number.isSafeInteger(debounce) || debounce < 0 || debounce > MAX_TIMER_INTERVAL_MS) {
      throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', 'Watcher debounce must be a non-negative timer interval');
    }
    if (eventTypes?.some((type: string): boolean =>
      type !== WatchEventType.Created && type !== WatchEventType.Modified && type !== WatchEventType.Deleted && type !== WatchEventType.Renamed,
    )) {
      throw new ExpoFileSystemError('ERR_INVALID_ARGUMENT_TYPE', 'Unknown watcher event type');
    }

    this.path = path;
    this.debounce = debounce;
    this.eventTypes = eventTypes;
    this.watchers = watchers;
  }

  start(): void {
    if (this.watcher !== undefined) return;
    const mask = WatchFlag.Modify | WatchFlag.Attribute | WatchFlag.MoveFrom | WatchFlag.MoveTo |
      WatchFlag.Create | WatchFlag.Delete | WatchFlag.DeleteSelf | WatchFlag.MoveSelf;
    const generation = ++this.generation;

    try {
      this.directory = fs.lstatSync(this.path).isDirectory();
      if (this.directory) {
        // The system callback can mask out IN_ISDIR. Snapshot existing children so
        // deletes and moves out of the directory retain the type of their old path.
        for (const name of fs.listFileSync(this.path)) {
          const child = `${this.path}/${name}`;
          if (this.isDirectoryAtPath(child)) this.childDirectories.add(child);
        }
      }

      this.watcher = fs.createWatcher(this.path, mask, (event: WatchEvent): void => {
        if (this.generation === generation) this.receive(event);
      });
      this.watcher.start();
      this.watchers.add(this);
    } catch (error) {
      this.stop();
      throw new ExpoFileSystemError('ERR_FILE_SYSTEM_WATCHER_SETUP', 'Could not start the file system watcher', error as Object);
    }
  }

  stop(): void {
    const watcher = this.watcher;
    this.watcher = undefined;
    this.generation++;

    this.watchers.delete(this);
    if (this.timer !== undefined) clearTimeout(this.timer);
    this.timer = undefined;
    this.pending.clear();
    this.movedFrom.clear();
    this.movedTo.clear();
    this.childDirectories.clear();

    try {
      watcher?.stop();
    } catch (error) {
      this.context.logger.warn(`Could not stop Expo file watcher: ${String(error)}`);
    }
  }

  override sharedObjectWillRelease(): void {
    this.stop();
  }

  private receive(event: WatchEvent): void {
    if (this.watcher === undefined) return;

    const flags = event.event;
    if ((flags & (WatchFlag.DeleteSelf | WatchFlag.MoveSelf)) !== 0) {
      try {
        this.emit(new WatchEventPayload(
          (flags & WatchFlag.DeleteSelf) !== 0 ? WatchEventType.Deleted : WatchEventType.Renamed,
          this.path, this.directory, flags,
        ), true);
      } finally {
        this.stop();
      }
      return;
    }

    const path = event.fileName.length === 0 ? this.path : event.fileName.startsWith('/')
      ? event.fileName : `${this.path}/${event.fileName}`;
    const directory = this.eventIsDirectory(path, flags);

    if ((flags & (WatchFlag.MoveFrom | WatchFlag.MoveTo)) !== 0) {
      const payload = new WatchEventPayload(WatchEventType.Renamed, path, directory, flags);
      if (event.cookie !== 0) {
        if ((flags & WatchFlag.MoveFrom) !== 0) this.movedFrom.set(event.cookie, payload);
        else this.movedTo.set(event.cookie, payload);
      } else this.enqueue(payload);
    }
    if ((flags & WatchFlag.Create) !== 0) this.enqueue(new WatchEventPayload(WatchEventType.Created, path, directory, flags));
    if ((flags & WatchFlag.Delete) !== 0) this.enqueue(new WatchEventPayload(WatchEventType.Deleted, path, directory, flags));
    if ((flags & (WatchFlag.Modify | WatchFlag.Attribute)) !== 0) {
      this.enqueue(new WatchEventPayload(WatchEventType.Modified, path, directory, flags));
    }

    if (this.timer !== undefined) clearTimeout(this.timer);
    const generation = this.generation;
    this.timer = setTimeout((): void => {
      if (this.generation === generation) this.flush();
    }, this.debounce);
  }

  private isDirectoryAtPath(path: string): boolean {
    try {
      return fs.lstatSync(path).isDirectory();
    } catch (_) {
      // A child may be gone by the time the notification reaches ArkTS.
      return false;
    }
  }

  private eventIsDirectory(path: string, flags: number): boolean {
    if (path === this.path) return this.directory;

    const isDirectory = (flags & WatchFlag.IsDirectory) !== 0;
    if ((flags & (WatchFlag.Delete | WatchFlag.MoveFrom)) !== 0) {
      return this.childDirectories.delete(path) || isDirectory;
    }

    const directory = isDirectory || this.isDirectoryAtPath(path);
    if (directory) this.childDirectories.add(path);

    return directory;
  }

  private enqueue(event: WatchEventPayload): void {
    const key = `${event.type}:${event.path}`;
    const previous = this.pending.get(key);
    if (previous !== undefined) event.nativeEventFlags |= previous.nativeEventFlags;
    this.pending.set(key, event);
  }

  private flush(): void {
    this.timer = undefined;
    this.movedFrom.forEach((source: WatchEventPayload, cookie: number): void => {
      const destination = this.movedTo.get(cookie);
      if (destination !== undefined) {
        const directory = source.isDirectory || destination.isDirectory;
        source.isDirectory = directory;
        source.newPath = destination.path;
        source.newPathIsDirectory = directory;
        source.nativeEventFlags |= destination.nativeEventFlags;
        this.movedTo.delete(cookie);
      }
      this.enqueue(source);
    });
    this.movedTo.forEach((destination: WatchEventPayload): void => this.enqueue(destination));
    this.movedFrom.clear();
    this.movedTo.clear();
    const events = Array.from(this.pending.values());
    this.pending.clear();
    events.forEach((event: WatchEventPayload): void => {
      if (this.watcher !== undefined) this.emit(event);
    });
  }

  private emit(event: WatchEventPayload, terminal: boolean = false): void {
    // The upstream JS wrapper filters the callback and still removes its native subscription.
    if (terminal || this.eventTypes === undefined || this.eventTypes.includes(event.type)) this.sendEvent('change', event);
  }
}
