#pragma once

#include <memory>

#include <jsi/jsi.h>

namespace expo::harmony {

class RuntimeContext;

class RuntimeInstaller final {
public:
  static bool install(
      facebook::jsi::Runtime &runtime,
      const std::shared_ptr<RuntimeContext> &context,
      bool workletRuntime);
};

}  // namespace expo::harmony
