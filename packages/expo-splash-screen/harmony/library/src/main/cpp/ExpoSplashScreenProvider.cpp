#include "ExpoSplashScreenProvider.h"

#include <atomic>
#include <cmath>
#include <cstddef>
#include <memory>
#include <string>
#include <utility>

#include <jsi/JSIDynamic.h>

#include <RNOH/Performance/RNOHMarker.h>

namespace expo::harmony::splashscreen {
namespace {

constexpr const char *kModuleName = "ExpoSplashScreen";
constexpr const char *kServiceName = "ExpoSplashScreenService";

struct SplashScreenOptions final {
  double duration{400.0};
  bool fade{true};
};

SplashScreenOptions readOptions(Invocation &call) {
  call.requireArgumentCount(0, 1);

  SplashScreenOptions opts;
  if (call.argumentCount() == 0 || call.argument(0).isUndefined() || call.argument(0).isNull()) {
    return opts;
  }

  auto &runtime = call.runtime();
  const auto &value = call.argument(0);
  if (!value.isObject()) {
    throw CodedError("ERR_SPLASH_SCREEN_OPTIONS", "ExpoSplashScreen.setOptions expected an options object.");
  }

  auto input = value.getObject(runtime);
  if (input.isArray(runtime)) {
    throw CodedError("ERR_SPLASH_SCREEN_OPTIONS", "ExpoSplashScreen.setOptions expected an options object.");
  }

  auto duration = input.getProperty(runtime, "duration");
  if (!duration.isUndefined() && !duration.isNull()) {
    if (!duration.isNumber() || !std::isfinite(duration.getNumber()) || duration.getNumber() < 0) {
      throw CodedError("ERR_SPLASH_SCREEN_OPTIONS", "Splash screen duration must be a non-negative finite number.");
    }

    opts.duration = duration.getNumber();
  }

  auto fade = input.getProperty(runtime, "fade");
  if (!fade.isUndefined() && !fade.isNull()) {
    if (!fade.isBool()) {
      throw CodedError("ERR_SPLASH_SCREEN_OPTIONS", "Splash screen fade must be a boolean.");
    }

    opts.fade = fade.getBool();
  }

  return opts;
}

facebook::jsi::Value invokeAsync(Invocation &call, std::string method, folly::dynamic args = folly::dynamic::array()) {
  return call.context().invokePlatformService(kServiceName, std::move(method), std::move(args));
}

void invokeSync(RuntimeContext &ctx, std::string method, folly::dynamic args = folly::dynamic::array()) {
  ctx.invokePlatformServiceSync(kServiceName, std::move(method), std::move(args));
}

bool isAbilityDestroyed(RuntimeContext &ctx) {
  auto value = ctx.invokePlatformServiceSync(kServiceName, "isAbilityDestroyed");

  if (!value.isBool()) {
    throw CodedError("ERR_SPLASH_SCREEN_ABILITY_STATE", "Harmony returned an invalid splash screen UIAbility lifecycle state.");
  }

  return value.getBool();
}

FunctionDefinition asyncPlatformFunction(std::string name, std::string method, folly::dynamic args = folly::dynamic::array()) {
  return FunctionDefinition{
      .name = std::move(name),
      .arity = 0,
      .requiredArity = 0,
      .async = true,
      .queue = FunctionQueue::JavaScript,
      .body = [method = std::move(method),
               args = std::move(args)](Invocation &call) mutable {
        return invokeAsync(call, method, args);
      }};
}

size_t runtimeId(const std::shared_ptr<RuntimeContext> &ctx) {
  auto value = ctx->callPlatformSync("getRuntimeId");

  if (!value.isNumber()) {
    throw CodedError("ERR_SPLASH_SCREEN_RUNTIME_ID", "ExpoModulesCore returned an invalid RNInstance id.");
  }

  const auto id = value.getNumber();
  if (!std::isfinite(id) || id < 0 || std::floor(id) != id) {
    throw CodedError("ERR_SPLASH_SCREEN_RUNTIME_ID", "ExpoModulesCore returned an invalid RNInstance id.");
  }

  return static_cast<size_t>(id);
}

class ContentAppearedListener final
    : public rnoh::RNOHMarker::RNOHMarkerListener {
public:
  ContentAppearedListener(std::weak_ptr<RuntimeContext> ctx, size_t id)
      : ctx_(std::move(ctx)), id_(id) {}

  void onMarkerReceived(
      rnoh::RNOHMarker::RNOHMarkerId markerId,
      size_t instanceId,
      const std::string &,
      double,
      uint64_t) override {
    if (!active_.load() || delivered_.load() || markerId != rnoh::RNOHMarker::RNOHMarkerId::CONTENT_APPEARED || instanceId != id_) {
      return;
    }
    if (delivered_.exchange(true)) {
      return;
    }

    auto ctx = ctx_.lock();
    if (!ctx || !ctx->isAlive()) {
      return;
    }

    ctx->dispatch(
        FunctionQueue::JavaScript,
        [weak = ctx_]() {
          auto ctx = weak.lock();
          if (!ctx || !ctx->isAlive()) {
            return;
          }

          invokeSync(*ctx, "contentAppeared");
        });
  }

  void deactivate() noexcept {
    active_.store(false);
  }

private:
  std::weak_ptr<RuntimeContext> ctx_;
  size_t id_;
  std::atomic_bool active_{true};
  std::atomic_bool delivered_{false};
};

void unregisterListener(const std::shared_ptr<ContentAppearedListener> &listener) noexcept {
  if (!listener) {
    return;
  }
  listener->deactivate();
  rnoh::RNOHMarker::removeListener(listener);
}

class ExpoSplashScreenModule final : public ExpoModule {
public:
  explicit ExpoSplashScreenModule(const std::shared_ptr<RuntimeContext> &ctx) {
    const auto id = runtimeId(ctx);

    listener_ = std::make_shared<ContentAppearedListener>(ctx, id);
    rnoh::RNOHMarker::addListener(listener_);
  }

  ~ExpoSplashScreenModule() override {
    unregisterListener(listener_);
  }

  ModuleDefinition definition() override {
    ModuleBuilder module(kModuleName);
    module.function(FunctionDefinition{
        .name = "setOptions",
        .arity = 1,
        .requiredArity = 0,
        .body = [](Invocation &call) {
          const auto opts = readOptions(call);

          invokeSync(
              call.context(),
              "setOptions",
              folly::dynamic::array(opts.duration, opts.fade));

          return facebook::jsi::Value::undefined();
        }});
    module.function(FunctionDefinition{
        .name = "hide",
        .arity = 0,
        .requiredArity = 0,
        .body = [](Invocation &call) {
          invokeSync(call.context(), "hide");
          return facebook::jsi::Value::undefined();
        }});
    module.function(asyncPlatformFunction("hideAsync", "hideAsync"));
    module.function(asyncPlatformFunction(
        "preventAutoHideAsync", "preventAutoHideAsync"));
    module.function(asyncPlatformFunction(
        "internalPreventAutoHideAsync", "internalPreventAutoHideAsync"));
    module.function(asyncPlatformFunction(
        "internalMaybeHideAsync", "internalMaybeHideAsync"));

    auto listener = listener_;

    module.onDestroy([listener](RuntimeContext &ctx) {
      unregisterListener(listener);
      invokeSync(ctx, "runtimeWillDestroy");
    });
    module.onActivityDestroy([listener](RuntimeContext &ctx) {
      try {
        if (!isAbilityDestroyed(ctx)) {
          return;
        }

        unregisterListener(listener);
        invokeSync(ctx, "abilityWillDestroy");
      } catch (...) {
        // Activity and runtime teardown can race. onDestroy owns the remaining
        // listener cleanup, and lifecycle dispatch must never escape here.
      }
    });

    return std::move(module).build();
  }

private:
  std::shared_ptr<ContentAppearedListener> listener_;
};

}  // namespace

std::vector<std::shared_ptr<ExpoModule>> ExpoSplashScreenProvider::modules(const std::shared_ptr<RuntimeContext> &ctx) {
  return {std::make_shared<ExpoSplashScreenModule>(ctx)};
}
}  // namespace expo::harmony::splashscreen
