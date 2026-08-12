#pragma once

#include <jsi/jsi.h>
#include <memory>

namespace expo::harmony {

class RuntimeContext;

class RuntimeInstaller final {
 public:
  static bool install(
      facebook::jsi::Runtime& runtime,
      const std::shared_ptr<RuntimeContext>& context,
      bool workletRuntime);
};

} // namespace expo::harmony
