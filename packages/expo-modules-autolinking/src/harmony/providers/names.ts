import { sha256 } from '../../utilities/values';

function providerAlias(provider) {
  return `ExpoHarmonyProvider_${sha256(`${provider.identifier}\0${provider.className}`).slice(0, 16)}`;
}

export { providerAlias };
