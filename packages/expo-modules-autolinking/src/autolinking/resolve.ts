import type { ModuleDescriptor, ResolveOptions } from '../types';
import { searchModulesAsync } from './search';
import { createDescriptorFromSearchRecordAsync } from '../metadata/descriptor';
import { compareText, emitLog } from '../utilities/values';

function compareModuleDescriptors(left, right) {
  return compareText(left.packageName, right.packageName)
    || compareText(left.packageVersion, right.packageVersion)
    || compareText(left.packageRoot, right.packageRoot);
}

async function resolveModulesAsync(options: ResolveOptions = {}): Promise<ModuleDescriptor[]> {
  const searchResult = options.searchResult || await searchModulesAsync(options);

  const records = [...searchResult.modules].sort(compareModuleDescriptors);
  const descriptors = [];

  for (const record of records) {
    descriptors.push(await createDescriptorFromSearchRecordAsync(record));
  }

  const result = descriptors.sort(compareModuleDescriptors);

  emitLog(options.logger, 'debug', 'Harmony module resolution completed.', {
    moduleCount: descriptors.length,
  });
  return result;
}

export {
  compareModuleDescriptors,
  resolveModulesAsync,
};
