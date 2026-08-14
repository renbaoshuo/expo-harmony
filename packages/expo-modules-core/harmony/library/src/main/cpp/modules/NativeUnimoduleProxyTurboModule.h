#pragma once

#include <RNOH/ArkTSTurboModule.h>

namespace expo::harmony {

class NativeUnimoduleProxyTurboModule final : public rnoh::ArkTSTurboModule {
public:
  NativeUnimoduleProxyTurboModule(
      rnoh::ArkTSTurboModule::Context context,
      const std::string &name);
};

}  // namespace expo::harmony
