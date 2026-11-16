/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "EXDevLauncherTurboModule.h"

namespace expo::harmony {

namespace {
constexpr auto kManifestString = "manifestString";
constexpr auto kManifestUrl = "manifestURL";
}  // namespace

EXDevLauncherTurboModule::EXDevLauncherTurboModule(
    const ArkTSTurboModule::Context context,
    const std::string name)
    : ArkTSTurboModule(context, name) {
  methodMap_ = {ARK_METHOD_METADATA(getConstants, 0)};
}

facebook::jsi::Value EXDevLauncherTurboModule::get(
    facebook::jsi::Runtime &runtime,
    const facebook::jsi::PropNameID &name) {
  const auto property = name.utf8(runtime);

  if (property == kManifestString || property == kManifestUrl) {
    auto constants = call(runtime, "getConstants", nullptr, 0).asObject(runtime);
    return constants.getProperty(runtime, name);
  }

  return ArkTSTurboModule::get(runtime, name);
}

std::vector<facebook::jsi::PropNameID> EXDevLauncherTurboModule::getPropertyNames(facebook::jsi::Runtime &runtime) {
  auto names = ArkTSTurboModule::getPropertyNames(runtime);
  names.push_back(facebook::jsi::PropNameID::forAscii(runtime, kManifestString));
  names.push_back(facebook::jsi::PropNameID::forAscii(runtime, kManifestUrl));

  return names;
}

}  // namespace expo::harmony
