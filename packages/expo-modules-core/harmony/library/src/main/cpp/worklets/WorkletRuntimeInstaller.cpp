#include "WorkletRuntimeInstaller.h"

#include <ReactCommon/CallInvoker.h>
#include <worklets/WorkletRuntime/WorkletRuntime.h>
#include <cstring>
#include "errors/CodedError.h"
#include "modules/ExpoModulesCoreTurboModule.h"
#include "runtime/RuntimeContext.h"
#include "runtime/RuntimeInstaller.h"

namespace jsi = facebook::jsi;
namespace react = facebook::react;

namespace expo::harmony {

namespace {

class WorkletCallInvoker final : public react::CallInvoker {
 public:
  explicit WorkletCallInvoker(std::weak_ptr<worklets::WorkletRuntime> runtime)
      : runtime_(std::move(runtime)) {}

  void invokeAsync(react::CallFunc&& function) noexcept override {
    if (auto runtime = runtime_.lock()) {
      runtime->schedule(std::move(function));
    }
  }

  void invokeSync(react::CallFunc&& function) override {
    auto runtime = runtime_.lock();
    if (!runtime) return;
    runtime->runSync([function = std::move(function)](jsi::Runtime& rt) mutable {
      function(rt);
    });
  }

 private:
  std::weak_ptr<worklets::WorkletRuntime> runtime_;
};

} // namespace

void WorkletRuntimeInstaller::install(
    jsi::Runtime& mainRuntime,
    const std::shared_ptr<RuntimeContext>& mainContext) {
  auto holder = mainRuntime.global().getProperty(mainRuntime, "_WORKLET_RUNTIME");
  if (!holder.isObject() || !holder.getObject(mainRuntime).isArrayBuffer(mainRuntime)) {
    throw makeJSError(
        mainRuntime,
        "ERR_WORKLET_RUNTIME_UNAVAILABLE",
        "UI Runtime is not available. Install and import react-native-worklets before calling installOnUIRuntime().");
  }
  auto buffer = holder.getObject(mainRuntime).getArrayBuffer(mainRuntime);
  if (buffer.size(mainRuntime) != sizeof(jsi::Runtime*)) {
    throw makeJSError(
        mainRuntime,
        "ERR_INVALID_WORKLET_RUNTIME",
        "_WORKLET_RUNTIME must be an ArrayBuffer containing exactly one runtime pointer.");
  }
  jsi::Runtime* uiRuntime = nullptr;
  std::memcpy(&uiRuntime, buffer.data(mainRuntime), sizeof(uiRuntime));
  if (uiRuntime == nullptr) {
    throw makeJSError(
        mainRuntime,
        "ERR_INVALID_WORKLET_RUNTIME",
        "_WORKLET_RUNTIME contains a null runtime pointer.");
  }

  auto coreModule = mainContext->turboModule();
  if (coreModule->hasRuntimeContext(uiRuntime)) {
    return;
  }

  auto weakWorkletRuntime =
      worklets::WorkletRuntime::getWeakRuntimeFromJSIRuntime(*uiRuntime);
  auto workletRuntime = weakWorkletRuntime.lock();
  if (!workletRuntime) {
    throw makeJSError(
        mainRuntime,
        "ERR_WORKLET_RUNTIME_DESTROYED",
        "The Worklets UI runtime has already been destroyed.");
  }
  workletRuntime->runSync(
      [coreModule, weakWorkletRuntime](jsi::Runtime& runtime) {
        auto uiContext = std::make_shared<RuntimeContext>(
            runtime,
            std::make_shared<WorkletCallInvoker>(weakWorkletRuntime),
            nullptr,
            coreModule);
        if (RuntimeInstaller::install(runtime, uiContext, true)) {
          coreModule->registerRuntimeContext(runtime, uiContext);
        }
      });
}

} // namespace expo::harmony
