#pragma once

#include <memory>

#include <jsi/jsi.h>

namespace expo::harmony {

class RuntimeContext;

class WorkletRuntimeInstaller final {
public:
  static void install(
      facebook::jsi::Runtime &mainRuntime,
      const std::shared_ptr<RuntimeContext> &mainContext);
};

}  // namespace expo::harmony
