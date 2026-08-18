#include "ExpoLinkingProvider.h"

#include <cmath>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

#include "LinkingRegistry.h"

namespace expo::harmony::linking {
namespace {

constexpr const char *kModuleName = "ExpoLinking";
constexpr const char *kEventName = "onURLReceived";
constexpr const char *kServiceName = "ExpoLinkingService";

facebook::jsi::Value currentURL(RuntimeContext &context) {
  auto value = context.invokePlatformServiceSync(kServiceName, "getURL");
  if (value.isUndefined() || value.isNull()) {
    return facebook::jsi::Value::null();
  }
  if (!value.isString()) {
    throw CodedError("ERR_LINKING_INITIAL_URL", "Harmony returned an invalid initial URL.");
  }
  return value;
}

uint64_t requireRevision(
    RuntimeContext &context,
    std::string method,
    folly::dynamic arguments = folly::dynamic::array()) {
  auto value = context.invokePlatformServiceSync(
      kServiceName, std::move(method), std::move(arguments));
  if (!value.isNumber()) {
    throw CodedError("ERR_LINKING_REVISION", "Harmony returned an invalid Linking lifecycle revision.");
  }
  const auto revision = value.getNumber();
  if (!std::isfinite(revision) || revision < 0 || std::floor(revision) != revision) {
    throw CodedError("ERR_LINKING_REVISION", "Harmony returned an invalid Linking lifecycle revision.");
  }
  return static_cast<uint64_t>(revision);
}

std::optional<uint64_t> dispatchedRevision(
    RuntimeContext &context,
    const std::string &url,
    uint64_t afterRevision) {
  auto value = context.invokePlatformServiceSync(
      kServiceName,
      "getDispatchedRevision",
      folly::dynamic::array(url, afterRevision));
  if (value.isUndefined() || value.isNull()) {
    return std::nullopt;
  }
  if (!value.isNumber()) {
    throw CodedError("ERR_LINKING_REVISION", "Harmony returned an invalid Linking lifecycle revision.");
  }
  const auto revision = value.getNumber();
  if (!std::isfinite(revision) || revision < 0 || std::floor(revision) != revision) {
    throw CodedError("ERR_LINKING_REVISION", "Harmony returned an invalid Linking lifecycle revision.");
  }
  return static_cast<uint64_t>(revision);
}

bool isAbilityDestroyed(RuntimeContext &context) {
  auto value = context.invokePlatformServiceSync(
      kServiceName, "isAbilityDestroyed");
  if (!value.isBool()) {
    throw CodedError("ERR_LINKING_ABILITY_STATE", "Harmony returned an invalid Linking UIAbility lifecycle state.");
  }
  return value.getBool();
}

void unregisterRuntime(RuntimeContext &context) noexcept {
  try {
    context.invokePlatformServiceSync(kServiceName, "runtimeWillDestroy");
  } catch (...) {
    // RNInstance can invalidate this bridge before native module teardown.
    // ExpoModulesCore's ArkTS __onDestroy__ independently destroys its local
    // platform-service scope, whose Linking service unregisters this runtime.
  }
}

std::optional<std::string> urlFromWant(const folly::dynamic &want) {
  if (!want.isObject()) {
    return std::nullopt;
  }
  const auto *value = want.get_ptr("uri");
  if (!value || !value->isString() || value->asString().empty()) {
    return std::nullopt;
  }
  return value->asString();
}

class ExpoLinkingModule final : public ExpoModule {
public:
  explicit ExpoLinkingModule(const std::shared_ptr<RuntimeContext> &context)
      : state_(std::make_shared<LinkingRegistry>(
            requireRevision(*context, "getRevision"))) {}

  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);
    module.events({kEventName});
    module.function(FunctionDefinition{
        .name = "getLinkingURL",
        .arity = 0,
        .requiredArity = 0,
        .queue = FunctionQueue::JavaScript,
        .body = [](Invocation &invocation) {
          return currentURL(invocation.context());
        }});
    module.function(FunctionDefinition{
        .name = "clearInitialURL",
        .arity = 0,
        .requiredArity = 0,
        .queue = FunctionQueue::JavaScript,
        .body = [](Invocation &invocation) {
          (void)requireRevision(invocation.context(), "clearURL");
          return facebook::jsi::Value::undefined();
        }});
    module.onStartObserving(
        kEventName,
        [state = state_](RuntimeContext &) { state->startObserving(); });
    module.onStopObserving(
        kEventName,
        [state = state_](RuntimeContext &) { state->stopObserving(); });
    module.onNewIntent(
        [state = state_](RuntimeContext &context, const folly::dynamic &want) {
          auto url = urlFromWant(want);
          if (!url) {
            return;
          }
          const auto revision = dispatchedRevision(
              context, *url, state->lastSeenRevision());
          if (!revision || !state->receive(*revision)) {
            return;
          }
          if (state->isObserving()) {
            context.emitModuleEvent(
                kModuleName,
                kEventName,
                {folly::dynamic::object("url", *url)});
          }
        });
    module.onDestroy(
        [state = state_](RuntimeContext &context) {
          unregisterRuntime(context);
          state->destroy();
        });
    module.onActivityDestroy(
        [state = state_](RuntimeContext &context) {
          try {
            if (!isAbilityDestroyed(context)) {
              return;
            }
          } catch (...) {
            // Teardown may invalidate the ArkTS bridge before this callback.
            // Never let an Ability-destroy notification escape the registry.
          }
          unregisterRuntime(context);
          state->destroy();
        });
    return std::move(module).build();
  }

private:
  std::shared_ptr<LinkingRegistry> state_;
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoLinkingProvider::modules(
    const std::shared_ptr<RuntimeContext> &context) {
  return {std::make_shared<ExpoLinkingModule>(context)};
}
}  // namespace expo::harmony::linking
