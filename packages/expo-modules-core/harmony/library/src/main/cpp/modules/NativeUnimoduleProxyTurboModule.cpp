#include "NativeUnimoduleProxyTurboModule.h"

#include <utility>

namespace expo::harmony {

using rnoh::ArkTSTurboModule;

NativeUnimoduleProxyTurboModule::NativeUnimoduleProxyTurboModule(
    ArkTSTurboModule::Context context,
    const std::string &name)
    : ArkTSTurboModule(std::move(context), name) {
  methodMap_ = {
      ARK_METHOD_METADATA(getConstants, 0),
  };
}

}  // namespace expo::harmony
