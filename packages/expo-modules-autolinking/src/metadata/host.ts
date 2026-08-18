import { HarmonyAutolinkingError } from '../errors';
import { sortedUniqueStrings } from '../utilities/values';

const ArkTsIdentifierPattern = /^[A-Za-z_$][A-Za-z0-9_$]*$/;
const HostMetadataFields = Object.freeze([
  'abilityLifecycleSubscribers',
  'reactInstanceLifecycleListeners',
  'rootViewComponents',
]);

function normalizeIdentifiers(value, field, packageName) {
  if (value === undefined) return [];

  if (!Array.isArray(value)) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', `expo-module.config.json#harmony.${field} must be an array.`, {
      packageName,
      stage: 'metadata',
    });
  }
  const values = value.map((item, index) => {
    if (typeof item !== 'string' || !ArkTsIdentifierPattern.test(item)) {
      throw new HarmonyAutolinkingError('INVALID_METADATA', `harmony.${field}[${index}] must be a valid ArkTS identifier.`, {
        packageName,
        stage: 'metadata',
      });
    }
    return item;
  });

  return sortedUniqueStrings(values);
}

function normalizeHostMetadata(harmony, record) {
  if (harmony.host !== undefined) {
    throw new HarmonyAutolinkingError('INVALID_METADATA', 'expo-module.config.json#harmony.host is no longer supported; declare lifecycle subscriber and handler class names instead.', { packageName: record.packageName, stage: 'metadata' });
  }

  return Object.fromEntries(HostMetadataFields.map(field => [
    field,
    normalizeIdentifiers(harmony[field], field, record.packageName),
  ]));
}

export {
  HostMetadataFields,
  normalizeHostMetadata,
};
