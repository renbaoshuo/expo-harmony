#pragma once

#include <jsi/jsi.h>
#include <memory>

namespace expo::harmony {

class RuntimeContext;

class WorkletRuntimeInstaller final {
 public:
  static void install(
      facebook::jsi::Runtime& mainRuntime,
      const std::shared_ptr<RuntimeContext>& mainContext);
};

} // namespace expo::harmony
