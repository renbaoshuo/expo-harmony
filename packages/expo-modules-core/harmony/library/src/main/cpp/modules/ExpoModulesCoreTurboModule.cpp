#include "ExpoModulesCoreTurboModule.h"

#include <jsi/JSIDynamic.h>

#include <hilog/log.h>

#include "common/EventEmitter.h"
#include "common/LazyObject.h"
#include "errors/CodedError.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"
#include "runtime/RuntimeInstaller.h"

namespace jsi = facebook::jsi;
namespace react = facebook::react;

namespace expo::harmony {

namespace {

constexpr unsigned int kExpoModulesLogDomain = 0xD003900;
constexpr const char *kExpoModulesLogTag = "ExpoModulesCore";

jsi::Value installModulesHostFunction(
    jsi::Runtime &runtime,
    react::TurboModule &turboModule,
    const jsi::Value *,
    size_t) {
  try {
    return static_cast<ExpoModulesCoreTurboModule &>(turboModule).install(runtime);
  } catch (const jsi::JSError &) {
    throw;
  } catch (const CodedError &error) {
    throw makeJSError(runtime, error);
  } catch (const std::exception &error) {
    throw makeJSError(
        runtime,
        "ERR_RUNTIME_INSTALLATION",
        "Expo Modules could not install the native runtime: " + std::string(error.what()));
  } catch (...) {
    throw makeJSError(
        runtime,
        "ERR_RUNTIME_INSTALLATION",
        "Expo Modules could not install the native runtime because native code threw an unknown exception.");
  }
}

}  // namespace

ExpoModulesCoreTurboModule::ExpoModulesCoreTurboModule(
    rnoh::ArkTSTurboModule::Context context,
    const std::string &name)
    : rnoh::ArkTSMessageHub::Observer(context.arkTSMessageHub),
      rnoh::TurboModule(context, name),
      jsInvoker_(context.jsInvoker),
      taskExecutor_(context.taskExecutor),
      safeInstance_(context.safeInstance),
      platformBridge_(
          std::make_unique<rnoh::ArkTSTurboModule>(std::move(context), name)) {
  methodMap_["installModules"] = MethodMetadata{0, installModulesHostFunction};
}

ExpoModulesCoreTurboModule::~ExpoModulesCoreTurboModule() noexcept {
  // Runtime-owned native state performs JSI cleanup on the owning JS executor.
  // The TurboModule must not destroy retained JSI values from RNOH's teardown thread.
  std::scoped_lock lock(contextsMutex_);
  contexts_.clear();
}

std::shared_ptr<RuntimeContext> ExpoModulesCoreTurboModule::runtimeContext(
    jsi::Runtime &runtime) {
  std::scoped_lock lock(contextsMutex_);
  auto iterator = contexts_.find(&runtime);
  if (iterator != contexts_.end()) {
    if (auto existing = iterator->second.lock()) {
      return existing;
    }
  }
  auto context = std::make_shared<RuntimeContext>(
      runtime, jsInvoker_, taskExecutor_, weak_from_this());
  contexts_[&runtime] = context;
  return context;
}

bool ExpoModulesCoreTurboModule::hasRuntimeContext(jsi::Runtime *runtime) {
  if (!runtime) {
    return false;
  }
  std::scoped_lock lock(contextsMutex_);
  auto iterator = contexts_.find(runtime);
  if (iterator == contexts_.end()) {
    return false;
  }
  auto context = iterator->second.lock();
  if (!context || !context->isAlive()) {
    contexts_.erase(iterator);
    return false;
  }
  return true;
}

void ExpoModulesCoreTurboModule::registerRuntimeContext(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context) {
  std::scoped_lock lock(contextsMutex_);
  contexts_[&runtime] = context;
}

jsi::Value ExpoModulesCoreTurboModule::install(jsi::Runtime &runtime) {
  auto context = runtimeContext(runtime);
  RuntimeInstaller::install(runtime, context, false);
  return jsi::Value(true);
}

jsi::Value ExpoModulesCoreTurboModule::callPlatformSync(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount) {
  // This boundary is deliberately restricted to JSON-like platform values.
  // JSI wrappers and module bodies never pass through ArkTSTurboModule.
  return platformBridge_->call(
      runtime, methodName, arguments, argumentCount);
}

jsi::Value ExpoModulesCoreTurboModule::callPlatformAsync(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount) {
  return platformBridge_->callAsync(
      runtime, methodName, arguments, argumentCount);
}

void ExpoModulesCoreTurboModule::postMessageToArkTS(
    const std::string &name,
    const folly::dynamic &payload) {
  auto instance = safeInstance_.lock();
  if (!instance) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot send a platform message after the RNOH instance was destroyed.");
  }
  instance->postMessageToArkTS(name, payload);
}

void ExpoModulesCoreTurboModule::onMessageReceived(
    const rnoh::ArkTSMessage &message) {
  if (message.name == protocol::kViewEvent && message.payload.isObject()) {
    auto phase = message.payload.getDefault("phase", "").asString();
    auto componentName = message.payload.getDefault("componentName", "").asString();
    auto tag = message.payload.getDefault("tag", 0).asInt();
    auto props = message.payload.getDefault("props", folly::dynamic::object());
    std::vector<std::weak_ptr<RuntimeContext>> contexts;
    {
      std::scoped_lock lock(contextsMutex_);
      for (const auto &[runtime, context] : contexts_) {
        contexts.push_back(context);
      }
    }
    for (const auto &weakContext : contexts) {
      auto context = weakContext.lock();
      if (!context || !context->isAlive() || !context->hasModuleRegistry()) {
        continue;
      }
      const auto *view = context->moduleRegistry().findView(componentName);
      if (!view) {
        continue;
      }
      try {
        if (phase == protocol::kViewPhaseCreate && view->onCreate) {
          view->onCreate(*context, tag, componentName);
        } else if (phase == protocol::kViewPhaseProps && props.isObject()) {
          context->updateViewProps(*view, tag, componentName, props);
        } else if (phase == protocol::kViewPhaseDestroy) {
          context->forgetView(tag);
          if (view->onDestroy) {
            view->onDestroy(*context, tag, componentName);
          }
        }
      } catch (const std::exception &error) {
        OH_LOG_Print(
            LOG_APP,
            LOG_ERROR,
            kExpoModulesLogDomain,
            kExpoModulesLogTag,
            "Expo view callback failed for %{public}s#%{public}lld in phase %{public}s: %{public}s",
            componentName.c_str(),
            static_cast<long long>(tag),
            phase.c_str(),
            error.what());
      } catch (...) {
        OH_LOG_Print(
            LOG_APP,
            LOG_ERROR,
            kExpoModulesLogDomain,
            kExpoModulesLogTag,
            "Expo view callback failed for %{public}s#%{public}lld in phase %{public}s",
            componentName.c_str(),
            static_cast<long long>(tag),
            phase.c_str());
      }
    }
    return;
  }
  if (message.name == protocol::kLifecycleEvent && message.payload.isObject()) {
    auto eventName = message.payload.getDefault("eventName", "").asString();
    auto payload = message.payload.getDefault("payload", nullptr);
    std::vector<std::weak_ptr<RuntimeContext>> contexts;
    {
      std::scoped_lock lock(contextsMutex_);
      for (const auto &[runtime, context] : contexts_) {
        contexts.push_back(context);
      }
    }
    jsInvoker_->invokeAsync(
        [contexts = std::move(contexts),
         eventName = std::move(eventName),
         payload = std::move(payload)](
            jsi::Runtime &runtime) {
          for (const auto &weakContext : contexts) {
            auto context = weakContext.lock();
            if (!context || !context->isAlive()) {
              continue;
            }
            if (eventName == protocol::kLifecycleDestroy) {
              context->invalidate();
            } else if (context->hasModuleRegistry() && &context->runtime() == &runtime) {
              context->moduleRegistry().dispatchLifecycle(eventName, payload);
            }
          }
        });
    return;
  }
  if (message.name != protocol::kModuleEvent || !message.payload.isObject()) {
    return;
  }
  auto moduleName = message.payload.getDefault("moduleName", "").asString();
  auto eventName = message.payload.getDefault("eventName", "").asString();
  auto arguments = message.payload.getDefault("arguments", folly::dynamic::array());
  if (moduleName.empty() || eventName.empty() || !arguments.isArray()) {
    return;
  }

  std::vector<std::weak_ptr<RuntimeContext>> contexts;
  {
    std::scoped_lock lock(contextsMutex_);
    contexts.reserve(contexts_.size());
    for (const auto &[runtime, context] : contexts_) {
      contexts.push_back(context);
    }
  }
  auto invoker = jsInvoker_;
  invoker->invokeAsync(
      [contexts = std::move(contexts),
       moduleName = std::move(moduleName),
       eventName = std::move(eventName),
       arguments = std::move(arguments)](jsi::Runtime &runtime) mutable {
        for (const auto &weakContext : contexts) {
          auto context = weakContext.lock();
          if (!context || !context->isAlive() || !context->hasModuleRegistry() || &context->runtime() != &runtime) {
            continue;
          }
          auto moduleValue = context->getModule(moduleName);
          if (!moduleValue.isObject()) {
            continue;
          }
          auto moduleWrapper = moduleValue.getObject(runtime);
          const auto &unwrappedModule = expo::LazyObject::unwrapObjectIfNecessary(runtime, moduleWrapper);
          auto module = jsi::Value(runtime, unwrappedModule).getObject(runtime);
          std::vector<jsi::Value> values;
          values.reserve(arguments.size());
          for (const auto &argument : arguments) {
            values.push_back(jsi::valueFromDynamic(runtime, argument));
          }
          expo::EventEmitter::emitEvent(
              runtime,
              module,
              eventName,
              values);
        }
      });
}

}  // namespace expo::harmony
