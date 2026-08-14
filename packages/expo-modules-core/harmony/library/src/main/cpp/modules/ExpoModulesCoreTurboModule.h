#pragma once

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>

#include <jsi/jsi.h>

#include <RNOH/ArkTSMessageHub.h>
#include <RNOH/ArkTSTurboModule.h>
#include <RNOH/TurboModule.h>

namespace expo::harmony {

class RuntimeContext;

class ExpoModulesCoreTurboModule final
    : public rnoh::ArkTSMessageHub::Observer,
      public rnoh::TurboModule,
      public std::enable_shared_from_this<ExpoModulesCoreTurboModule> {
public:
  ExpoModulesCoreTurboModule(
      rnoh::ArkTSTurboModule::Context context,
      const std::string &name);
  ~ExpoModulesCoreTurboModule() noexcept override;

  facebook::jsi::Value install(facebook::jsi::Runtime &runtime);
  std::shared_ptr<RuntimeContext> runtimeContext(
      facebook::jsi::Runtime &runtime);
  bool hasRuntimeContext(facebook::jsi::Runtime *runtime);
  void registerRuntimeContext(
      facebook::jsi::Runtime &runtime,
      const std::shared_ptr<RuntimeContext> &context);

  facebook::jsi::Value callPlatformSync(
      facebook::jsi::Runtime &runtime,
      const std::string &methodName,
      const facebook::jsi::Value *arguments,
      size_t argumentCount);
  facebook::jsi::Value callPlatformAsync(
      facebook::jsi::Runtime &runtime,
      const std::string &methodName,
      const facebook::jsi::Value *arguments,
      size_t argumentCount);
  void postMessageToArkTS(
      const std::string &name,
      const folly::dynamic &payload);

  void onMessageReceived(const rnoh::ArkTSMessage &message) override;

private:
  std::shared_ptr<facebook::react::CallInvoker> jsInvoker_;
  rnoh::TaskExecutor::Shared taskExecutor_;
  rnoh::RNInstance::SafeWeak safeInstance_;
  std::unique_ptr<rnoh::ArkTSTurboModule> platformBridge_;
  std::mutex contextsMutex_;
  std::unordered_map<
      facebook::jsi::Runtime *,
      std::weak_ptr<RuntimeContext>>
      contexts_;
};

}  // namespace expo::harmony
