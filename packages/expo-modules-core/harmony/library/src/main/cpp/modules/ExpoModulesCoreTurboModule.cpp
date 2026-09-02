#include "ExpoModulesCoreTurboModule.h"

#include <cmath>
#include <exception>
#include <functional>
#include <limits>
#include <optional>

#include <jsi/JSIDynamic.h>

#include <RNOH/Performance/RNOHMarker.h>

#include <hilog/log.h>

#include "common/EventEmitter.h"
#include "common/LazyObject.h"
#include "errors/CodedError.h"
#include "modules/ArkTSModuleAdapter.h"
#include "modules/ArkTSTypedBridge.h"
#include "runtime/InvalidationBarrier.h"
#include "runtime/ModuleRegistry.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"
#include "runtime/RuntimeIdentity.h"
#include "runtime/RuntimeInstaller.h"

namespace jsi = facebook::jsi;
namespace react = facebook::react;

namespace expo::harmony {

class ContentAppearedMarkerListener final
    : public rnoh::RNOHMarker::RNOHMarkerListener {
public:
  using Handler = std::function<void(size_t)>;

  explicit ContentAppearedMarkerListener(Handler handler)
      : handler_(std::move(handler)) {}

  void onMarkerReceived(
      rnoh::RNOHMarker::RNOHMarkerId markerId,
      size_t rnInstanceId,
      const std::string &,
      double,
      uint64_t) override {
    if (markerId == rnoh::RNOHMarker::RNOHMarkerId::CONTENT_APPEARED) {
      handler_(rnInstanceId);
    }
  }

private:
  Handler handler_;
};

namespace {

constexpr unsigned int kExpoModulesLogDomain = 0xD003900;
constexpr const char *kExpoModulesLogTag = "ExpoModulesCore";
constexpr double kMaxSafeTransportInteger = 9007199254740991.0;

std::optional<long> readPositiveTransportLong(const folly::dynamic &value) {
  if (value.isInt()) {
    return value.asInt() > 0 ? std::optional<long>(value.asInt()) : std::nullopt;
  }
  if (!value.isDouble()) {
    return std::nullopt;
  }
  const auto number = value.asDouble();
  if (!std::isfinite(number) || std::trunc(number) != number || number <= 0 || number > kMaxSafeTransportInteger || number > static_cast<double>(std::numeric_limits<long>::max())) {
    return std::nullopt;
  }
  return static_cast<long>(number);
}

std::optional<long> readTypedEventTransportId(
    const folly::dynamic &payload) {
  if (!payload.isObject() || !payload.count("transportId")) {
    return std::nullopt;
  }
  return readPositiveTransportLong(payload.at("transportId"));
}

std::vector<jsi::Value> takeTypedEventArguments(
    const std::shared_ptr<RuntimeContext> &context,
    long transportId) {
  auto &runtime = context->runtime();
  std::vector<jsi::Value> arguments;
  arguments.reserve(2);
  arguments.emplace_back(jsi::String::createFromUtf8(
      runtime, context->runtimeEpochString()));
  arguments.emplace_back(static_cast<double>(transportId));
  auto value = context->callPlatformSyncTyped(
      "takeExpoTypedEventArguments", std::move(arguments));
  return ArkTSModuleAdapter::decodeTypedValues(context, value);
}

void discardTypedEventArguments(
    const std::shared_ptr<RuntimeContext> &context,
    long transportId) noexcept {
  try {
    auto &runtime = context->runtime();
    std::vector<jsi::Value> arguments;
    arguments.reserve(2);
    arguments.emplace_back(jsi::String::createFromUtf8(
        runtime, context->runtimeEpochString()));
    arguments.emplace_back(static_cast<double>(transportId));
    (void)context->callPlatformSyncTyped(
        "discardExpoTypedEventArguments", std::move(arguments));
  } catch (...) {
  }
}

jsi::Value installModulesHostFunction(
    jsi::Runtime &runtime,
    react::TurboModule &turboModule,
    const jsi::Value *,
    size_t) {
  try {
    return static_cast<ExpoModulesCoreTurboModule &>(turboModule).install(runtime);
  } catch (const jsi::JSError &error) {
    throw jsi::JSError(error);
  } catch (const CodedError &error) {
    throw CodedJSError(runtime, error);
  } catch (const std::exception &error) {
    throw CodedJSError(
        runtime,
        "ERR_RUNTIME_INSTALLATION",
        "Expo Modules could not install the native runtime: " + std::string(error.what()));
  } catch (...) {
    throw CodedJSError(
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
      typedPlatformBridge_(std::make_unique<ArkTSTypedBridge>(context)) {
  methodMap_["installModules"] = MethodMetadata{0, installModulesHostFunction};
}

ExpoModulesCoreTurboModule::~ExpoModulesCoreTurboModule() noexcept {
  // Clean up JSI state on the owning JS executor.
  std::shared_ptr<ContentAppearedMarkerListener> contentAppearedListener;
  {
    std::scoped_lock lock(contextsMutex_);
    contentAppearedListener = std::move(contentAppearedListener_);
    activeRuntimeContext_.reset();
    contentAppearedRuntime_.reset();
    contexts_.clear();
  }
  if (contentAppearedListener) {
    rnoh::RNOHMarker::removeListener(contentAppearedListener);
  }
}

std::shared_ptr<RuntimeContext> ExpoModulesCoreTurboModule::runtimeContext(
    jsi::Runtime &runtime) {
  std::scoped_lock lock(contextsMutex_);
  auto iterator = contexts_.find(&runtime);
  if (iterator != contexts_.end()) {
    if (auto existing = iterator->second.lock()) {
      if (existing->isAlive() && existing->isAcceptingTasks()) {
        return existing;
      }
    }
    contexts_.erase(iterator);
  }
  auto context = RuntimeContext::create(
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
  if (!context || !context->isAlive() || !context->isAcceptingTasks()) {
    contexts_.erase(iterator);
    return false;
  }
  return true;
}

bool ExpoModulesCoreTurboModule::isDestroyScheduled() const noexcept {
  return destroyScheduled_.load(std::memory_order_acquire);
}

void ExpoModulesCoreTurboModule::registerRuntimeContext(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context) {
  if (!context || !context->isAlive() || !context->isAcceptingTasks()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot register an Expo RuntimeContext that is being destroyed.");
  }
  std::scoped_lock lock(contextsMutex_);
  contexts_[&runtime] = context;
}

void ExpoModulesCoreTurboModule::activateRuntimeContext(
    jsi::Runtime &runtime,
    const std::shared_ptr<RuntimeContext> &context) {
  if (!context || !context->isAlive() || !context->isAcceptingTasks()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot activate an Expo RuntimeContext that is being destroyed.");
  }
  std::scoped_lock lock(contextsMutex_);
  contexts_[&runtime] = context;
  activeRuntimeContext_ = context;
}

void ExpoModulesCoreTurboModule::ensureContentAppearedListener() {
  std::shared_ptr<ContentAppearedMarkerListener> listener;
  {
    std::scoped_lock lock(contextsMutex_);
    if (contentAppearedListener_) {
      return;
    }
    auto weakSelf = weak_from_this();
    listener = std::make_shared<ContentAppearedMarkerListener>(
        [weakSelf](size_t rnInstanceId) {
          if (auto self = weakSelf.lock()) {
            self->handleContentAppeared(rnInstanceId);
          }
        });
    contentAppearedListener_ = listener;
  }
  rnoh::RNOHMarker::addListener(std::move(listener));
}

void ExpoModulesCoreTurboModule::handleContentAppeared(size_t rnInstanceId) {
  auto instance = safeInstance_.lock();
  if (!instance || instance->getId() != rnInstanceId || isDestroyScheduled() || !jsInvoker_) {
    return;
  }

  auto weakSelf = weak_from_this();
  try {
    jsInvoker_->invokeAsync([weakSelf](jsi::Runtime &runtime) {
      auto self = weakSelf.lock();
      if (!self || self->isDestroyScheduled()) {
        return;
      }

      std::shared_ptr<RuntimeContext> context;
      {
        std::scoped_lock lock(self->contextsMutex_);
        context = self->activeRuntimeContext_.lock();
        if (!context || !context->isAlive() || !context->isAcceptingTasks() || !context->hasModuleRegistry() || &context->runtime() != &runtime) {
          return;
        }
        auto delivered = self->contentAppearedRuntime_.lock();
        if (delivered && delivered.get() == context.get()) {
          return;
        }
        self->contentAppearedRuntime_ = context;
      }

      try {
        self->postMessageToArkTS(
            protocol::kContentAppeared,
            folly::dynamic::object(
                "runtimeEpoch", context->runtimeEpochString()));
      } catch (const std::exception &error) {
        OH_LOG_Print(
            LOG_APP,
            LOG_ERROR,
            kExpoModulesLogDomain,
            kExpoModulesLogTag,
            "Unable to deliver the content-appeared lifecycle event: %{public}s",
            error.what());
      } catch (...) {
        OH_LOG_Print(
            LOG_APP,
            LOG_ERROR,
            kExpoModulesLogDomain,
            kExpoModulesLogTag,
            "Unable to deliver the content-appeared lifecycle event");
      }
    });
  } catch (const std::exception &error) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to schedule the content-appeared lifecycle event: %{public}s",
        error.what());
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to schedule the content-appeared lifecycle event");
  }
}

jsi::Value ExpoModulesCoreTurboModule::install(jsi::Runtime &runtime) {
  auto context = RuntimeInstaller::installedContext(runtime);
  if (context) {
    context->attachTurboModule(weak_from_this());
    registerRuntimeContext(runtime, context);
  } else {
    context = runtimeContext(runtime);
    if (!RuntimeInstaller::install(runtime, context, false)) {
      throw CodedError(
          "ERR_RUNTIME_INSTALLATION",
          "Expo Modules found an installed runtime without recoverable native state.");
    }
  }
  // Only the JS runtime selects the View target.
  activateRuntimeContext(runtime, context);
  ensureContentAppearedListener();
  return jsi::Value(true);
}

jsi::Value ExpoModulesCoreTurboModule::callPlatformSync(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount) {
  return typedPlatformBridge_->call(
      runtime, methodName, arguments, argumentCount);
}

jsi::Value ExpoModulesCoreTurboModule::callPlatformAsync(
    jsi::Runtime &runtime,
    const std::string &methodName,
    const jsi::Value *arguments,
    size_t argumentCount) {
  return typedPlatformBridge_->callAsync(
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
    const auto encodedPhase = message.payload.getDefault("phase", "");
    const auto encodedComponentName = message.payload.getDefault("componentName", "");
    const auto encodedTag = message.payload.getDefault("tag", 0);
    auto props = message.payload.getDefault("props", folly::dynamic::object());
    if (!encodedPhase.isString() || !encodedComponentName.isString() || !encodedTag.isInt()) {
      return;
    }
    auto phase = encodedPhase.asString();
    auto componentName = encodedComponentName.asString();
    auto tag = encodedTag.asInt();
    std::weak_ptr<RuntimeContext> weakContext;
    {
      std::scoped_lock lock(contextsMutex_);
      weakContext = activeRuntimeContext_;
    }
    auto context = weakContext.lock();
    if (!context || !context->isAlive() || !context->isAcceptingTasks() || !context->hasModuleRegistry()) {
      return;
    }
    const auto *view = context->moduleRegistry().findView(componentName);
    if (!view) {
      return;
    }
    try {
      if (phase == protocol::kViewPhaseCreate) {
        context->mountView(tag, componentName);
        const auto rollbackCreation = [&] {
          if (!context->unmountView(tag, componentName) || !view->onDestroy) {
            return;
          }

          try {
            view->onDestroy(*context, tag, componentName);
          } catch (const std::exception &cleanupError) {
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Expo view rollback failed for %{public}s#%{public}lld: %{public}s",
                componentName.c_str(),
                static_cast<long long>(tag),
                cleanupError.what());
          } catch (...) {
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Expo view rollback failed for %{public}s#%{public}lld",
                componentName.c_str(),
                static_cast<long long>(tag));
          }
        };

        try {
          if (view->onCreate) {
            view->onCreate(*context, tag, componentName);
          }
        } catch (const std::exception &error) {
          // Roll back mount state if author creation fails.
          rollbackCreation();

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
          return;
        } catch (...) {
          rollbackCreation();

          OH_LOG_Print(
              LOG_APP,
              LOG_ERROR,
              kExpoModulesLogDomain,
              kExpoModulesLogTag,
              "Expo view callback failed for %{public}s#%{public}lld in phase %{public}s",
              componentName.c_str(),
              static_cast<long long>(tag),
              phase.c_str());
          return;
        }
      } else if (phase == protocol::kViewPhaseProps && props.isObject()) {
        context->updateViewProps(*view, tag, componentName, props);
      } else if (phase == protocol::kViewPhaseDestroy) {
        if (context->unmountView(tag, componentName) && view->onDestroy) {
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
    return;
  }
  if (message.name == protocol::kLifecycleEvent && message.payload.isObject()) {
    const auto encodedEventName = message.payload.getDefault("eventName", "");
    if (!encodedEventName.isString()) {
      return;
    }
    if (encodedEventName.asString() != protocol::kLifecycleDestroy) {
      return;
    }
    auto payload = message.payload.getDefault("payload", nullptr);
    std::string destroyRequestId;
    if (payload.isObject()) {
      const auto requestId = payload.getDefault("requestId", "");
      if (requestId.isString()) {
        destroyRequestId = requestId.asString();
      }
    }
    bool expected = false;
    if (!destroyScheduled_.compare_exchange_strong(
            expected,
            true,
            std::memory_order_acq_rel,
            std::memory_order_acquire)) {
      return;
    }
    std::vector<std::shared_ptr<RuntimeContext>> contexts;
    {
      std::scoped_lock lock(contextsMutex_);
      for (auto iterator = contexts_.begin(); iterator != contexts_.end();) {
        auto context = iterator->second.lock();
        if (!context || !context->isAlive()) {
          iterator = contexts_.erase(iterator);
          continue;
        }
        contexts.push_back(context);
        ++iterator;
      }
    }
    auto acknowledgeDestroy =
        [mainJSInvoker = jsInvoker_,
         safeInstance = safeInstance_,
         requestId = std::move(destroyRequestId)]() noexcept {
          if (!mainJSInvoker) {
            return;
          }
          try {
            mainJSInvoker->invokeAsync(
                [safeInstance,
                 requestId](jsi::Runtime &) noexcept {
                  auto instance = safeInstance.lock();
                  if (instance && !requestId.empty()) {
                    try {
                      instance->postMessageToArkTS(
                          protocol::kLifecycleDestroyAck,
                          folly::dynamic::object("requestId", requestId));
                    } catch (const std::exception &error) {
                      OH_LOG_Print(
                          LOG_APP,
                          LOG_ERROR,
                          kExpoModulesLogDomain,
                          kExpoModulesLogTag,
                          "Unable to acknowledge Expo runtime destruction: %{public}s",
                          error.what());
                    } catch (...) {
                      OH_LOG_Print(
                          LOG_APP,
                          LOG_ERROR,
                          kExpoModulesLogDomain,
                          kExpoModulesLogTag,
                          "Unable to acknowledge Expo runtime destruction");
                    }
                  }
                });
          } catch (...) {
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Unable to schedule Expo runtime destruction acknowledgement");
          }
        };
    if (contexts.empty()) {
      acknowledgeDestroy();
      return;
    }
    auto barrier = InvalidationBarrier::create(
        contexts.size(), std::move(acknowledgeDestroy));
    // Close the View gate before asynchronous teardown.
    for (const auto &context : contexts) {
      context->invalidate([barrier] { barrier->arrive(); });
    }
    return;
  }
  if (message.name == protocol::kSharedObjectEvent && message.payload.isObject()) {
    auto encodedRuntimeEpoch = message.payload.getDefault("runtimeEpoch", "");
    auto encodedObjectId = message.payload.getDefault("objectId", 0);
    auto encodedModuleName = message.payload.getDefault("moduleName", "");
    auto encodedClassName = message.payload.getDefault("className", "");
    auto encodedEventName = message.payload.getDefault("eventName", "");
    const bool hasTypedTransport = message.payload.count("transportId") > 0;
    auto transportId = readTypedEventTransportId(message.payload);
    auto arguments = message.payload.getDefault("arguments", folly::dynamic::array());
    if (!encodedRuntimeEpoch.isString() || !readPositiveTransportLong(encodedObjectId) || !encodedModuleName.isString() || !encodedClassName.isString() || !encodedEventName.isString() || (hasTypedTransport && !transportId) || (!hasTypedTransport && !arguments.isArray())) {
      return;
    }
    auto runtimeEpoch = decodeRuntimeEpoch(encodedRuntimeEpoch.asString());
    auto objectId = *readPositiveTransportLong(encodedObjectId);
    auto moduleName = encodedModuleName.asString();
    auto className = encodedClassName.asString();
    auto eventName = encodedEventName.asString();
    if (!runtimeEpoch || objectId <= 0 || moduleName.empty() || className.empty() || eventName.empty()) {
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
    for (const auto &weakContext : contexts) {
      auto context = weakContext.lock();
      if (!context || !context->isAlive() || !context->isAcceptingTasks() || context->runtimeEpoch() != *runtimeEpoch) {
        continue;
      }
      auto invoker = context->jsInvoker();
      invoker->invokeAsync(
          [weakContext,
           runtimeEpoch = *runtimeEpoch,
           objectId,
           moduleName,
           className,
           eventName,
           transportId,
           arguments](jsi::Runtime &runtime) mutable {
            auto context = weakContext.lock();
            if (!context || !context->isAlive() || !context->isAcceptingTasks() || context->runtimeEpoch() != runtimeEpoch || !context->hasModuleRegistry() || &context->runtime() != &runtime) {
              return;
            }
            bool valuesHandled = false;
            auto discardPendingValues = [&] {
              if (valuesHandled) {
                return;
              }
              valuesHandled = true;
              if (transportId) {
                discardTypedEventArguments(context, *transportId);
              } else {
                ArkTSModuleAdapter::discardValues(context, arguments);
              }
            };
            try {
              (void)context->getNativeSharedObject(
                  objectId, moduleName, className);
              auto objectValue = context->getSharedObject(objectId);
              if (!objectValue.isObject()) {
                discardPendingValues();
                return;
              }
              std::vector<jsi::Value> values;
              if (transportId) {
                values = takeTypedEventArguments(context, *transportId);
                valuesHandled = true;
              } else {
                valuesHandled = true;
                values = ArkTSModuleAdapter::decodeValues(context, arguments);
              }
              auto object = objectValue.getObject(runtime);
              expo::EventEmitter::emitEvent(
                  runtime,
                  object,
                  eventName,
                  values);
            } catch (const CodedError &) {
              discardPendingValues();
              // Drop events for released or stale runtimes.
            } catch (const std::exception &error) {
              discardPendingValues();
              OH_LOG_Print(
                  LOG_APP,
                  LOG_ERROR,
                  kExpoModulesLogDomain,
                  kExpoModulesLogTag,
                  "Expo SharedObject event %{public}s failed: %{public}s",
                  eventName.c_str(),
                  error.what());
            } catch (...) {
              discardPendingValues();
              OH_LOG_Print(
                  LOG_APP,
                  LOG_ERROR,
                  kExpoModulesLogDomain,
                  kExpoModulesLogTag,
                  "Expo SharedObject event %{public}s failed",
                  eventName.c_str());
            }
          });
    }
    return;
  }
  if (message.name != protocol::kModuleEvent || !message.payload.isObject()) {
    return;
  }
  const auto encodedRuntimeEpoch = message.payload.getDefault("runtimeEpoch", "");
  const auto encodedModuleName = message.payload.getDefault("moduleName", "");
  const auto encodedEventName = message.payload.getDefault("eventName", "");
  const bool hasTypedTransport = message.payload.count("transportId") > 0;
  auto transportId = readTypedEventTransportId(message.payload);
  auto arguments = message.payload.getDefault("arguments", folly::dynamic::array());
  if (!encodedRuntimeEpoch.isString() || !encodedModuleName.isString() || !encodedEventName.isString() || (hasTypedTransport && !transportId) || (!hasTypedTransport && !arguments.isArray())) {
    return;
  }
  auto runtimeEpoch = decodeRuntimeEpoch(encodedRuntimeEpoch.asString());
  auto moduleName = encodedModuleName.asString();
  auto eventName = encodedEventName.asString();
  if (!runtimeEpoch || moduleName.empty() || eventName.empty()) {
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
  for (const auto &weakContext : contexts) {
    auto context = weakContext.lock();
    if (!context || !context->isAlive() || !context->isAcceptingTasks() || context->runtimeEpoch() != *runtimeEpoch) {
      continue;
    }
    auto invoker = context->jsInvoker();
    invoker->invokeAsync(
        [weakContext,
         runtimeEpoch = *runtimeEpoch,
         moduleName,
         eventName,
         transportId,
         arguments](jsi::Runtime &runtime) mutable {
          auto context = weakContext.lock();
          if (!context || !context->isAlive() || !context->isAcceptingTasks() || context->runtimeEpoch() != runtimeEpoch || !context->hasModuleRegistry() || &context->runtime() != &runtime) {
            return;
          }
          bool valuesHandled = false;
          auto discardPendingValues = [&] {
            if (valuesHandled) {
              return;
            }
            valuesHandled = true;
            if (transportId) {
              discardTypedEventArguments(context, *transportId);
            } else {
              ArkTSModuleAdapter::discardValues(context, arguments);
            }
          };
          try {
            auto moduleValue = context->getModule(moduleName);
            if (!moduleValue.isObject()) {
              discardPendingValues();
              return;
            }
            auto moduleWrapper = moduleValue.getObject(runtime);
            const auto &unwrappedModule = expo::LazyObject::unwrapObjectIfNecessary(runtime, moduleWrapper);
            auto module = jsi::Value(runtime, unwrappedModule).getObject(runtime);
            std::vector<jsi::Value> values;
            if (transportId) {
              values = takeTypedEventArguments(context, *transportId);
              valuesHandled = true;
            } else {
              valuesHandled = true;
              values = ArkTSModuleAdapter::decodeValues(context, arguments);
            }
            expo::EventEmitter::emitEvent(
                runtime,
                module,
                eventName,
                values);
          } catch (const CodedError &) {
            discardPendingValues();
            // Drop events for released or stale runtimes.
          } catch (const std::exception &error) {
            discardPendingValues();
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Expo module event %{public}s failed: %{public}s",
                eventName.c_str(),
                error.what());
          } catch (...) {
            discardPendingValues();
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Expo module event %{public}s failed",
                eventName.c_str());
          }
        });
  }
}

}  // namespace expo::harmony
