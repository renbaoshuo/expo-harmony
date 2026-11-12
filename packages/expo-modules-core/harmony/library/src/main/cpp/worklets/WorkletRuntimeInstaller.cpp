/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include "WorkletRuntimeInstaller.h"

#if WORKLETS_ENABLED
#include <ReactCommon/CallInvoker.h>
#include <worklets/Compat/StableApi.h>
#include <worklets/Compat/Holders.h>
#include <worklets/WorkletRuntime/WorkletRuntime.h>
#include <worklets/WorkletRuntime/RuntimeData.h>
#endif

#include "errors/CodedError.h"
#if WORKLETS_ENABLED
#include "modules/ExpoModulesCoreTurboModule.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/RnohSyncTask.h"
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
    if (taskExecutor_) {
      runRnohSyncTask(*taskExecutor_, rnoh::TaskThread::MAIN, std::move(body));
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
    const std::shared_ptr<RuntimeContext> &mainContext,
    const jsi::Value &runtimeHolder) {
#if WORKLETS_ENABLED
  if (!runtimeHolder.isObject() ||
      !runtimeHolder.getObject(mainRuntime).hasNativeState<worklets::WorkletRuntimeHolder>(mainRuntime)) {
    throw CodedError(
        "ERR_INVALID_WORKLET_RUNTIME",
        "installOnUIRuntime() expects the result of react-native-worklets.getUIRuntimeHolder().");
  }

  auto workletRuntime = worklets::getWorkletRuntimeFromHolder(
      mainRuntime, runtimeHolder.getObject(mainRuntime));
  if (!workletRuntime) {
    throw CodedError(
        "ERR_INVALID_WORKLET_RUNTIME",
        "The supplied Worklets runtime holder is invalid or its runtime has been destroyed.");
  }

  auto *uiRuntime = &worklets::getJSIRuntimeFromWorkletRuntime(workletRuntime);
  if (uiRuntime == &mainRuntime) {
    throw CodedError(
        "ERR_INVALID_WORKLET_RUNTIME",
        "The Worklets runtime holder must identify a separate UI runtime.");
  }

  auto coreModule = mainContext->turboModule();
  auto weakWorkletRuntime = std::weak_ptr<worklets::WorkletRuntime>(workletRuntime);
  auto taskExecutor = mainContext->taskExecutor();
  if (!taskExecutor) {
    throw CodedError(
        "ERR_WORKLET_RUNTIME_UNAVAILABLE",
        "The RNOH main-thread executor is unavailable for the UI runtime.");
  }

  std::vector<ModuleDefinition> definitions;
  for (const auto &name : mainContext->moduleRegistry().names()) {
    const auto *definition = mainContext->moduleRegistry().find(name);
    if (definition && !definition->classes.empty()) definitions.push_back(*definition);
  }

  runRnohSyncTask(
      *taskExecutor,
      rnoh::TaskThread::MAIN,
      [coreModule, mainContext, weakWorkletRuntime, workletRuntime, taskExecutor, definitions = std::move(definitions)]() mutable {
        workletRuntime->runSync(
            [coreModule, mainContext, weakWorkletRuntime, taskExecutor, definitions = std::move(definitions)](jsi::Runtime &runtime) mutable {
              const auto kind = runtime.global().getProperty(runtime, worklets::RuntimeData::runtimeKindBindingName);
              if (!kind.isNumber() || kind.getNumber() != static_cast<int>(worklets::RuntimeData::RuntimeKind::UI)) {
                throw CodedError("ERR_INVALID_WORKLET_RUNTIME", "installOnUIRuntime() requires a Worklets UI runtime holder.");
              }
              if (!mainContext->isAlive() || !mainContext->isAcceptingTasks()) {
                throw CodedError("ERR_RUNTIME_DESTROYED", "Cannot install a worklet context after its React Native runtime retired.");
              }

              if (auto existing = RuntimeInstaller::installedContext(runtime, false)) {
                if (existing->isAcceptingTasks()) {
                  if (!existing->isWorkletContext() || existing->bridgeRuntimeEpochString() != mainContext->runtimeEpochString()) {
                    throw CodedError("ERR_WORKLET_RUNTIME_IN_USE", "This Worklets runtime belongs to another Expo AppContext.");
                  }
                  existing->attachTurboModule(coreModule);
                  coreModule->registerRuntimeContext(runtime, existing);
                  return;
                }

                // Reload can leave the UI runtime alive after its owner retired.
                existing->invalidate();
                if (RuntimeInstaller::installedContext(runtime, false)) {
                  throw CodedError("ERR_WORKLET_RUNTIME_IN_USE", "The previous Expo worklet context is still being destroyed.");
                }
              }

              auto uiContext = RuntimeContext::create(
                  runtime,
                  std::make_shared<WorkletCallInvoker>(
                      weakWorkletRuntime, taskExecutor),
                  nullptr,
                  coreModule);
              uiContext->initializeWorkletModuleRegistry(mainContext, std::move(definitions));

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
  (void)runtimeHolder;
  throw CodedError(
      "ERR_WORKLET_RUNTIME_UNAVAILABLE",
      "The optional Harmony Worklets integration is not compiled. Install "
      "react-native-worklets and its Harmony adapter, then rebuild the app.");
#endif
}

}  // namespace expo::harmony
