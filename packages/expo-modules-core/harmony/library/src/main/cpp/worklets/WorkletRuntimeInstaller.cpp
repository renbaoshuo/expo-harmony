#include "WorkletRuntimeInstaller.h"

#include <cstring>

#if WORKLETS_ENABLED
#include <ReactCommon/CallInvoker.h>
#include <worklets/WorkletRuntime/WorkletRuntime.h>
#endif

#include "errors/CodedError.h"
#if WORKLETS_ENABLED
#include "modules/ExpoModulesCoreTurboModule.h"
#include "runtime/RuntimeContext.h"
#include "runtime/RuntimeInstaller.h"
#endif

namespace jsi = facebook::jsi;
#if WORKLETS_ENABLED
namespace react = facebook::react;
#endif

namespace expo::harmony {

#if WORKLETS_ENABLED
namespace {

class WorkletCallInvoker final : public react::CallInvoker {
public:
  WorkletCallInvoker(
      std::weak_ptr<worklets::WorkletRuntime> runtime,
      rnoh::TaskExecutor::Shared taskExecutor)
      : runtime_(std::move(runtime)),
        taskExecutor_(std::move(taskExecutor)) {}

  void invokeAsync(react::CallFunc &&function) noexcept override {
    if (auto runtime = runtime_.lock()) {
      runtime->schedule(std::move(function));
    }
  }

  void invokeSync(react::CallFunc &&function) override {
    auto runtime = runtime_.lock();
    if (!runtime) {
      return;
    }
    auto body = [runtime, function = std::move(function)]() mutable {
      runtime->runSync(
          [function = std::move(function)](jsi::Runtime &rt) mutable {
            function(rt);
          });
    };
    if (taskExecutor_ && !taskExecutor_->isOnTaskThread(rnoh::TaskThread::MAIN)) {
      taskExecutor_->runSyncTask(
          rnoh::TaskThread::MAIN, std::move(body));
      return;
    }
    body();
  }

private:
  std::weak_ptr<worklets::WorkletRuntime> runtime_;
  rnoh::TaskExecutor::Shared taskExecutor_;
};

}  // namespace
#endif

void WorkletRuntimeInstaller::install(
    jsi::Runtime &mainRuntime,
    const std::shared_ptr<RuntimeContext> &mainContext) {
#if WORKLETS_ENABLED
  auto holder = mainRuntime.global().getProperty(mainRuntime, "_WORKLET_RUNTIME");
  if (!holder.isObject() || !holder.getObject(mainRuntime).isArrayBuffer(mainRuntime)) {
    throw CodedError(
        "ERR_WORKLET_RUNTIME_UNAVAILABLE",
        "UI Runtime is not available. Install and import react-native-reanimated before calling installOnUIRuntime().");
  }

  auto buffer = holder.getObject(mainRuntime).getArrayBuffer(mainRuntime);
  if (buffer.size(mainRuntime) != sizeof(jsi::Runtime *)) {
    throw CodedError(
        "ERR_INVALID_WORKLET_RUNTIME",
        "_WORKLET_RUNTIME must be an ArrayBuffer containing exactly one runtime pointer.");
  }

  jsi::Runtime *uiRuntime = nullptr;
  std::memcpy(&uiRuntime, buffer.data(mainRuntime), sizeof(uiRuntime));
  if (uiRuntime == nullptr) {
    throw CodedError(
        "ERR_INVALID_WORKLET_RUNTIME",
        "_WORKLET_RUNTIME contains a null runtime pointer.");
  }

  auto coreModule = mainContext->turboModule();
  if (coreModule->hasRuntimeContext(uiRuntime)) {
    return;
  }

  auto weakWorkletRuntime = worklets::WorkletRuntime::getWeakRuntimeFromJSIRuntime(*uiRuntime);
  auto workletRuntime = weakWorkletRuntime.lock();
  if (!workletRuntime) {
    throw CodedError(
        "ERR_WORKLET_RUNTIME_DESTROYED",
        "The Worklets UI runtime has already been destroyed.");
  }

  auto taskExecutor = mainContext->taskExecutor();
  if (!taskExecutor) {
    throw CodedError(
        "ERR_WORKLET_RUNTIME_UNAVAILABLE",
        "The RNOH main-thread executor is unavailable for the UI runtime.");
  }

  taskExecutor->runSyncTask(
      rnoh::TaskThread::MAIN,
      [coreModule, weakWorkletRuntime, workletRuntime, taskExecutor]() {
        workletRuntime->runSync(
            [coreModule, weakWorkletRuntime, taskExecutor](jsi::Runtime &runtime) {
              if (auto existing = RuntimeInstaller::installedContext(runtime)) {
                existing->attachTurboModule(coreModule);
                coreModule->registerRuntimeContext(runtime, existing);
                return;
              }
              auto uiContext = RuntimeContext::create(
                  runtime,
                  std::make_shared<WorkletCallInvoker>(
                      weakWorkletRuntime, taskExecutor),
                  nullptr,
                  coreModule);
              if (RuntimeInstaller::install(runtime, uiContext, true)) {
                coreModule->registerRuntimeContext(runtime, uiContext);
              } else {
                uiContext->invalidate();
                throw CodedError(
                    "ERR_RUNTIME_INSTALLATION",
                    "The Worklet runtime contains an unusable Expo RuntimeContext marker.");
              }
            });
      });
#else
  (void)mainRuntime;
  (void)mainContext;
  throw CodedError(
      "ERR_WORKLET_RUNTIME_UNAVAILABLE",
      "The optional Harmony Worklets integration is not compiled. Install "
      "react-native-reanimated and its Harmony Worklets dependency, then rebuild the app.");
#endif
}

}  // namespace expo::harmony
