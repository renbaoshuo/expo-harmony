/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import { ExpoFunction, ExpoModuleDefinition, ExpoValueTypes } from '@expo-harmony/expo-modules-core';
import { BusinessError } from '@kit.BasicServicesKit';
import { MediaLibraryPermissionResponse } from './MediaLibraryPermissions';
import { MediaLibraryRepository } from './MediaLibraryRepository';

export const CHANGE_EVENT_NAME: string = 'mediaLibraryDidChange';

export function mediaLibraryDefinition(repository: MediaLibraryRepository, name: string, definition: ExpoModuleDefinition = new ExpoModuleDefinition()): ExpoModuleDefinition {
  return definition
    .name(name)
    .events([CHANGE_EVENT_NAME])
    .asyncFunction('getPermissionsAsync', ExpoFunction.typed1(
      ExpoValueTypes.boolean().optional(),
      (write?: boolean): Promise<MediaLibraryPermissionResponse> =>
        repository.run(async (): Promise<MediaLibraryPermissionResponse> => await repository.permissions.get(write ?? false)),
    ))
    .asyncFunction('requestPermissionsAsync', ExpoFunction.typed1(
      ExpoValueTypes.boolean().optional(),
      (write?: boolean): Promise<MediaLibraryPermissionResponse> => repository.run(async (): Promise<MediaLibraryPermissionResponse> => {
        const response = await repository.permissions.request(write ?? false);

        repository.permissionsChanged();

        return response;
      }),
    ))
    .onStartObserving(CHANGE_EVENT_NAME, () => repository.startObserving())
    .onStopObserving(CHANGE_EVENT_NAME, () => repository.stopObserving())
    .onForeground((): void => repository.setForeground(true))
    .onBackground((): void => repository.setForeground(false))
    .onPrepareForReload((): Promise<void> => repository.destroy())
    .onDestroy((): void => {
      const logger = repository.context.logger;
      repository.destroy().catch((error: BusinessError): void => logger.warn(`Unable to release MediaLibrary: ${error.message}`));
    });
}
