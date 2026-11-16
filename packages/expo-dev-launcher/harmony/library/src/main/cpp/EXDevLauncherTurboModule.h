/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <RNOH/ArkTSTurboModule.h>

namespace expo::harmony {

class EXDevLauncherTurboModule final : public rnoh::ArkTSTurboModule {
public:
  EXDevLauncherTurboModule(const ArkTSTurboModule::Context context, const std::string name);

  facebook::jsi::Value get(facebook::jsi::Runtime &runtime, const facebook::jsi::PropNameID &name) override;
  std::vector<facebook::jsi::PropNameID> getPropertyNames(facebook::jsi::Runtime &runtime) override;
};

}  // namespace expo::harmony
