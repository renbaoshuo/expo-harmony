#include "RuntimeContext.h"

#include <algorithm>
#include <exception>
#include <limits>
#include <optional>

#include <jsi/JSIDynamic.h>

#include <common/EventEmitter.h>
#include <common/JSI/JSIUtils.h>
#include <common/SharedObject.h>
#include <hilog/log.h>

#include "api/Promise.h"
#include "errors/CodedError.h"
#include "modules/ExpoModulesCoreTurboModule.h"
#include "modules/internal/ModuleDefinition.h"
#include "runtime/ModuleRegistry.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

constexpr unsigned int kExpoModulesLogDomain = 0xD003900;
constexpr const char *kExpoModulesLogTag = "ExpoModulesCore";

// invokeAsync may silently discard callbacks during teardown.
class ScheduledCallbackGuard final {
public:
  explicit ScheduledCallbackGuard(std::function<void()> onDropped)
      : onDropped_(std::move(onDropped)) {}

  ~ScheduledCallbackGuard() noexcept {
    if (delivered_.load(std::memory_order_acquire) || !onDropped_) {
      return;
    }
    try {
      onDropped_();
    } catch (...) {
    }
  }

  void markDelivered() noexcept {
    delivered_.store(true, std::memory_order_release);
  }

private:
  std::atomic_bool delivered_{false};
  std::function<void()> onDropped_;
};

void logModulesExecutorError(std::string message) noexcept {
  OH_LOG_Print(
      LOG_APP,
      LOG_ERROR,
      kExpoModulesLogDomain,
      kExpoModulesLogTag,
      "Expo Modules executor task failed: %{public}s",
      message.c_str());
}

void logSharedObjectReleaseError(
    long objectId,
    const char *phase,
    const char *message = nullptr) noexcept {
  if (message) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Expo SharedObject %{public}ld failed during %{public}s: %{public}s",
        objectId,
        phase,
        message);
    return;
  }

  OH_LOG_Print(
      LOG_APP,
      LOG_ERROR,
      kExpoModulesLogDomain,
      kExpoModulesLogTag,
      "Expo SharedObject %{public}ld failed during %{public}s with a native exception",
      objectId,
      phase);
}

void runInvalidationCompletion(std::function<void()> completion) noexcept {
  try {
    if (completion) {
      completion();
    }
  } catch (...) {
  }
}

}  // namespace

SharedObjectInvocationLeaseBundle::SharedObjectInvocationLeaseBundle(
    std::shared_ptr<RuntimeContext> context,
    std::vector<Entry> entries) noexcept
    : context_(std::move(context)), entries_(std::move(entries)) {}

SharedObjectInvocationLeaseBundle::SharedObjectInvocationLeaseBundle(
    SharedObjectInvocationLeaseBundle &&other) noexcept
    : context_(std::move(other.context_)),
      entries_(std::move(other.entries_)) {}

SharedObjectInvocationLeaseBundle &
SharedObjectInvocationLeaseBundle::operator=(
    SharedObjectInvocationLeaseBundle &&other) noexcept {
  if (this == &other) {
    return *this;
  }
  reset();
  context_ = std::move(other.context_);
  entries_ = std::move(other.entries_);
  return *this;
}

SharedObjectInvocationLeaseBundle::~SharedObjectInvocationLeaseBundle() noexcept {
  reset();
}

void SharedObjectInvocationLeaseBundle::reset() noexcept {
  auto context = std::move(context_);
  auto entries = std::move(entries_);
  if (context && !entries.empty()) {
    context->releaseSharedObjectInvocations(std::move(entries));
  }
}

RuntimeInvocationLease::RuntimeInvocationLease(
    std::shared_ptr<RuntimeContext> context) noexcept
    : context_(std::move(context)) {}

RuntimeInvocationLease::RuntimeInvocationLease(
    RuntimeInvocationLease &&other) noexcept
    : context_(std::move(other.context_)) {}

RuntimeInvocationLease::~RuntimeInvocationLease() noexcept {
  if (context_) {
    context_->releaseDispatchedInvocation();
  }
}

std::shared_ptr<RuntimeContext> RuntimeContext::create(
    jsi::Runtime &runtime,
    std::shared_ptr<facebook::react::CallInvoker> jsInvoker,
    rnoh::TaskExecutor::Shared taskExecutor,
    std::weak_ptr<ExpoModulesCoreTurboModule> turboModule) {
  auto deletionInvoker = jsInvoker;
  const auto runtimeThread = std::this_thread::get_id();
  return std::shared_ptr<RuntimeContext>(
      new RuntimeContext(
          runtime,
          std::move(jsInvoker),
          std::move(taskExecutor),
          std::move(turboModule)),
      [deletionInvoker = std::move(deletionInvoker), runtimeThread](
          RuntimeContext *context) noexcept {
        if (std::this_thread::get_id() == runtimeThread) {
          delete context;
          return;
        }
        if (deletionInvoker) {
          try {
            auto delivery = std::make_shared<ScheduledCallbackGuard>([] {
              OH_LOG_Print(
                  LOG_APP,
                  LOG_FATAL,
                  kExpoModulesLogDomain,
                  kExpoModulesLogTag,
                  "Leaking RuntimeContext because its JS executor discarded teardown");
            });
            deletionInvoker->invokeAsync(
                [context, delivery = std::move(delivery)](jsi::Runtime &) {
                  delivery->markDelivered();
                  delete context;
                });
            return;
          } catch (...) {
            // std::function construction may throw before invokeAsync.
          }
        }
        // Do not release JSI values from this executor thread.
        OH_LOG_Print(
            LOG_APP,
            LOG_FATAL,
            kExpoModulesLogDomain,
            kExpoModulesLogTag,
            "Leaking RuntimeContext because its JS executor cannot accept teardown");
      });
}

RuntimeContext::RuntimeContext(
    jsi::Runtime &runtime,
    std::shared_ptr<facebook::react::CallInvoker> jsInvoker,
    rnoh::TaskExecutor::Shared taskExecutor,
    std::weak_ptr<ExpoModulesCoreTurboModule> turboModule)
    : runtimeEpoch_(allocateRuntimeEpoch()),
      runtime_(&runtime),
      jsInvoker_(std::move(jsInvoker)),
      taskExecutor_(std::move(taskExecutor)),
      turboModule_(std::move(turboModule)),
      runtimeThread_(std::this_thread::get_id()),
      modulesExecutor_(logModulesExecutorError) {}

RuntimeContext::~RuntimeContext() {
  invalidate();
}

jsi::Runtime &RuntimeContext::runtime() const {
  assertRuntimeThread();
  if (!isAlive() || runtime_ == nullptr) {
    throw CodedError("ERR_RUNTIME_DESTROYED", "The Expo JavaScript runtime has been destroyed.");
  }
  return *runtime_;
}

std::shared_ptr<facebook::react::CallInvoker> RuntimeContext::jsInvoker() const {
  return jsInvoker_;
}

rnoh::TaskExecutor::Shared RuntimeContext::taskExecutor() const {
  return taskExecutor_;
}

std::shared_ptr<ExpoModulesCoreTurboModule> RuntimeContext::turboModule() const {
  std::scoped_lock lock(mutex_);
  auto module = turboModule_.lock();
  if (!module || !isAlive()) {
    throw CodedError("ERR_RUNTIME_DESTROYED", "Expo Modules Core is no longer attached to a runtime.");
  }
  return module;
}

void RuntimeContext::attachTurboModule(
    std::weak_ptr<ExpoModulesCoreTurboModule> turboModule) {
  if (!isAlive() || !isAcceptingTasks()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot attach Expo Modules Core to a runtime that is being destroyed.");
  }
  std::scoped_lock lock(mutex_);
  turboModule_ = std::move(turboModule);
}

bool RuntimeContext::isAlive() const noexcept {
  return alive_.load(std::memory_order_acquire);
}

bool RuntimeContext::isAcceptingTasks() const noexcept {
  return acceptingTasks_.load(std::memory_order_acquire);
}

bool RuntimeContext::isRuntimeThread() const noexcept {
  return runtimeThread_ == std::this_thread::get_id();
}

RuntimeEpoch RuntimeContext::runtimeEpoch() const noexcept {
  return runtimeEpoch_;
}

std::string RuntimeContext::runtimeEpochString() const {
  return encodeRuntimeEpoch(runtimeEpoch_);
}

void RuntimeContext::assertRuntimeThread() const {
  if (!isRuntimeThread()) {
    throw CodedError(
        "ERR_WRONG_THREAD",
        "Hermes JSI values may only be accessed on the owning JavaScript executor.");
  }
}

void RuntimeContext::invalidate(std::function<void()> completion) noexcept {
  if (completion) {
    bool alreadyInvalidated = false;
    try {
      std::scoped_lock lock(mutex_);
      alreadyInvalidated = !alive_.load(std::memory_order_acquire);
      if (!alreadyInvalidated) {
        invalidationCompletions_.push_back(std::move(completion));
      }
    } catch (...) {
      // Keep teardown noexcept; timeout callers retain their resources.
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Unable to retain Expo runtime invalidation completion");
      completion = nullptr;
    }
    if (alreadyInvalidated) {
      runInvalidationCompletion(std::move(completion));
      return;
    }
  }
  if (!isAlive()) {
    return;
  }
  acceptingTasks_.store(false, std::memory_order_release);
  if (!isRuntimeThread()) {
    if (invalidationScheduled_.exchange(true, std::memory_order_acq_rel)) {
      return;
    }
    std::shared_ptr<RuntimeContext> retainedContext;
    try {
      retainedContext = shared_from_this();
    } catch (...) {
      invalidationScheduled_.store(false, std::memory_order_release);
      return;
    }
    if (jsInvoker_) {
      try {
        auto delivery = std::make_shared<ScheduledCallbackGuard>(
            [context = retainedContext] {
              context->invalidationScheduled_.store(
                  false, std::memory_order_release);
              OH_LOG_Print(
                  LOG_APP,
                  LOG_ERROR,
                  kExpoModulesLogDomain,
                  kExpoModulesLogTag,
                  "Expo runtime invalidation was discarded by its JS executor");
            });
        jsInvoker_->invokeAsync(
            [context = std::move(retainedContext),
             delivery = std::move(delivery)](jsi::Runtime &) {
              delivery->markDelivered();
              context->invalidationScheduled_.store(
                  false, std::memory_order_release);
              context->invalidate();
            });
      } catch (...) {
        invalidationScheduled_.store(false, std::memory_order_release);
        OH_LOG_Print(
            LOG_APP,
            LOG_ERROR,
            kExpoModulesLogDomain,
            kExpoModulesLogTag,
            "Unable to allocate Expo runtime invalidation callback");
      }
    } else {
      invalidationScheduled_.store(false, std::memory_order_release);
    }
    return;
  }
  if (invalidating_.exchange(true, std::memory_order_acq_rel)) {
    return;
  }
  try {
    std::scoped_lock lock(mutex_);
    // Retain the context until teardown barriers finish.
    invalidationLease_ = shared_from_this();
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to retain Expo runtime during asynchronous invalidation");
    return;
  }
  // Reject pending promises before starting native teardown.
  cancelAndRejectPendingPromises();
  scheduleMountedViewTeardown();
}

void RuntimeContext::invalidateAfterViewTeardown() noexcept {
  if (!isRuntimeThread()) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Expo View teardown did not return to its owning JavaScript executor");
    return;
  }
  {
    std::scoped_lock lock(mutex_);
    if (invalidationViewTeardownCompleted_) {
      return;
    }
    invalidationViewTeardownCompleted_ = true;
  }

  auto context = invalidationLease_;
  auto invoker = jsInvoker_;
  const bool stopped = modulesExecutor_.shutdown(
      std::chrono::milliseconds(250),
      [context = std::move(context), invoker = std::move(invoker)]() noexcept {
        if (!context || !invoker) {
          return;
        }
        try {
          auto delivery = std::make_shared<ScheduledCallbackGuard>([] {
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Expo modules executor stopped, but its JS teardown continuation was discarded");
          });
          invoker->invokeAsync(
              [context, delivery = std::move(delivery)](jsi::Runtime &) {
                delivery->markDelivered();
                context->continueInvalidationAfterExecutorStop();
              });
        } catch (...) {
          OH_LOG_Print(
              LOG_APP,
              LOG_ERROR,
              kExpoModulesLogDomain,
              kExpoModulesLogTag,
              "Unable to schedule Expo modules executor teardown continuation");
        }
      });
  if (stopped) {
    continueInvalidationAfterExecutorStop();
  }
}

void RuntimeContext::continueInvalidationAfterExecutorStop() noexcept {
  if (!isRuntimeThread()) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Expo modules executor teardown resumed on the wrong thread");
    return;
  }
  bool ready = false;
  {
    std::scoped_lock lock(mutex_);
    if (invalidationExecutorStopped_) {
      return;
    }
    invalidationExecutorStopped_ = true;
    ready = runtimeInvocations_.requestDrain();
  }
  if (ready) {
    continueInvalidationAfterDispatchedInvocations();
  }
}

void RuntimeContext::continueInvalidationAfterDispatchedInvocations() noexcept {
  if (!isRuntimeThread()) {
    return;
  }
  {
    std::scoped_lock lock(mutex_);
    invalidationContinuationScheduled_ = false;
    if (!invalidationExecutorStopped_ || !runtimeInvocations_.isReady()) {
      return;
    }
  }

  // Keep the registry alive until active native bodies retire.
  releaseAllSharedObjects();
  maybeFinishInvalidationAfterSharedObjects();
}

void RuntimeContext::scheduleInvalidationAfterDispatchedInvocations() noexcept {
  std::shared_ptr<RuntimeContext> context;
  std::shared_ptr<facebook::react::CallInvoker> invoker;
  try {
    std::scoped_lock lock(mutex_);
    if (!invalidating_.load(std::memory_order_acquire) || !invalidationExecutorStopped_ || !runtimeInvocations_.isReady() || invalidationContinuationScheduled_) {
      return;
    }
    invalidationContinuationScheduled_ = true;
    context = invalidationLease_;
    invoker = jsInvoker_;
  } catch (...) {
    return;
  }
  if (!context || !invoker) {
    return;
  }
  try {
    auto delivery = std::make_shared<ScheduledCallbackGuard>([] {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Expo invocation teardown continuation was discarded by its JS executor");
    });
    invoker->invokeAsync(
        [context = std::move(context), delivery = std::move(delivery)](
            jsi::Runtime &) {
          delivery->markDelivered();
          context->continueInvalidationAfterDispatchedInvocations();
        });
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to schedule Expo invocation teardown continuation");
  }
}

void RuntimeContext::maybeFinishInvalidationAfterSharedObjects() noexcept {
  if (!isRuntimeThread()) {
    return;
  }
  bool shouldFinish = false;
  {
    std::scoped_lock lock(mutex_);
    invalidationWaitingForSharedObjects_ = !nativeSharedObjects_.empty();
    if (!invalidationFinishing_ && invalidationExecutorStopped_ && runtimeInvocations_.isReady() && !invalidationWaitingForSharedObjects_ && !sharedObjectInvocations_.hasFinalizing() && !sharedObjectReleaseSweepActive_) {
      invalidationFinishing_ = true;
      shouldFinish = true;
    }
  }
  if (shouldFinish) {
    finishInvalidation();
  }
}

void RuntimeContext::finishInvalidation() noexcept {
  if (!isRuntimeThread()) {
    return;
  }
  drainModuleListeners();
  if (moduleRegistry_) {
    try {
      moduleRegistry_->destroy();
    } catch (...) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Expo module registry threw during runtime teardown");
    }
  }
  try {
    auto module = turboModule();
    if (!module->isDestroyScheduled()) {
      (void)callPlatformSync(
          "invalidateExpoModuleRuntime", {runtimeEpochString()});
    }
  } catch (const std::exception &error) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to invalidate ArkTS Expo module runtime scope: %{public}s",
        error.what());
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to invalidate ArkTS Expo module runtime scope");
  }
  try {
    clearJSIReferences();
  } catch (...) {
    // Do not ACK if retained JSI state was not released on its owner thread.
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to clear Expo runtime references during teardown");
    {
      std::scoped_lock lock(mutex_);
      invalidationFinishing_ = false;
    }
    return;
  }

  std::vector<std::function<void()>> completions;
  std::shared_ptr<RuntimeContext> teardownLease;
  {
    std::scoped_lock lock(mutex_);
    alive_.store(false, std::memory_order_release);
    runtime_ = nullptr;
    completions.swap(invalidationCompletions_);
    teardownLease = std::move(invalidationLease_);
  }
  for (auto &invalidationCompletion : completions) {
    runInvalidationCompletion(std::move(invalidationCompletion));
  }
}

void RuntimeContext::dispatchToJavaScript(std::function<void()> task) {
  if (!task) {
    return;
  }
  if (!isAlive() || !acceptingTasks_.load(std::memory_order_acquire)) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot dispatch Expo module work while the runtime is being destroyed.");
  }
  auto guarded = [weakContext = weak_from_this(), task = std::move(task)]() mutable {
    auto context = weakContext.lock();
    if (!context || !context->beginDispatchedInvocation()) {
      return;
    }
    RuntimeInvocationLease invocationLease(context);
    // Destroy task captures before the invocation lease retires.
    auto executingTask = std::move(task);
    executingTask();
  };
  if (!jsInvoker_) {
    throw CodedError("ERR_QUEUE_UNAVAILABLE", "The Harmony JavaScript queue is unavailable.");
  }
  jsInvoker_->invokeAsync(std::move(guarded));
}

bool RuntimeContext::beginDispatchedInvocation() noexcept {
  std::scoped_lock lock(mutex_);
  if (!alive_.load(std::memory_order_acquire) || !acceptingTasks_.load(std::memory_order_acquire) || runtimeInvocations_.isDrainRequested()) {
    return false;
  }
  runtimeInvocations_.acquire();
  return true;
}

void RuntimeContext::releaseDispatchedInvocation() noexcept {
  bool shouldSchedule = false;
  {
    std::scoped_lock lock(mutex_);
    shouldSchedule = runtimeInvocations_.release();
  }
  if (shouldSchedule) {
    // Schedule invalidation on the owning JS executor.
    scheduleInvalidationAfterDispatchedInvocations();
  }
}

facebook::jsi::Value RuntimeContext::callPlatformSync(
    std::string methodName,
    std::vector<folly::dynamic> arguments) {
  assertRuntimeThread();
  std::vector<jsi::Value> values;
  values.reserve(arguments.size());
  for (const auto &argument : arguments) {
    values.push_back(jsi::valueFromDynamic(runtime(), argument));
  }
  return turboModule()->callPlatformSync(
      runtime(), methodName, values.data(), values.size());
}

facebook::jsi::Value RuntimeContext::callPlatformSyncTyped(
    std::string methodName,
    std::vector<jsi::Value> arguments,
    SynchronousBinaryWriteBack *writeBack) {
  assertRuntimeThread();
  return turboModule()->callPlatformSync(
      runtime(), methodName, arguments.data(), arguments.size(), writeBack);
}

facebook::jsi::Value RuntimeContext::callPlatformAsync(
    std::string methodName,
    std::vector<folly::dynamic> arguments) {
  assertRuntimeThread();
  std::vector<jsi::Value> values;
  values.reserve(arguments.size());
  for (const auto &argument : arguments) {
    values.push_back(jsi::valueFromDynamic(runtime(), argument));
  }
  return turboModule()->callPlatformAsync(
      runtime(), methodName, values.data(), values.size());
}

facebook::jsi::Value RuntimeContext::callPlatformAsyncTyped(
    std::string methodName,
    std::vector<facebook::jsi::Value> arguments) {
  assertRuntimeThread();
  return turboModule()->callPlatformAsync(
      runtime(), methodName, arguments.data(), arguments.size());
}

void RuntimeContext::updateViewProps(
    const ViewDefinition &view,
    int64_t tag,
    const std::string &componentName,
    const folly::dynamic &props) {
  if (!props.isObject()) {
    return;
  }
  if (!isAcceptingTasks()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot update an Expo view while its runtime is being destroyed.");
  }

  requireMountedView(tag, componentName);

  struct ViewPropChange final {
    const ViewPropDefinition *definition;
    std::string name;
    folly::dynamic storedValue;
    folly::dynamic setterValue;
  };

  std::vector<ViewPropChange> changes;
  {
    std::scoped_lock lock(mutex_);
    const auto [propsIterator, inserted] = viewProps_.try_emplace(tag, folly::dynamic::object());
    auto &previousProps = propsIterator->second;
    for (const auto &prop : view.props) {
      if (!prop.setter) {
        continue;
      }
      const auto *currentValue = props.get_ptr(prop.name);
      // Null resets a prop; omission leaves it unchanged.
      if (currentValue == nullptr) {
        // Apply a declared default on the first omitted prop.
        if (inserted && prop.hasDefaultValue) {
          changes.push_back(ViewPropChange{
              .definition = &prop,
              .name = prop.name,
              .storedValue = nullptr,
              .setterValue = prop.defaultValue,
          });
        }
        continue;
      }
      const auto *previousValue = previousProps.get_ptr(prop.name);
      // Distinguish missing values from explicit null so nullable setters run.
      if (previousValue != nullptr && *currentValue == *previousValue) {
        continue;
      }
      auto storedValue = *currentValue;
      changes.push_back(ViewPropChange{
          .definition = &prop,
          .name = prop.name,
          .storedValue = storedValue,
          .setterValue = storedValue.isNull() && prop.hasDefaultValue
                           ? prop.defaultValue
                           : storedValue,
      });
    }
  }
  for (auto &change : changes) {
    change.definition->setter(*this, tag, componentName, change.setterValue);
    std::scoped_lock lock(mutex_);
    viewProps_.try_emplace(tag, folly::dynamic::object()).first->second[change.name] = std::move(change.storedValue);
  }
  if (view.onDidUpdateProps) {
    view.onDidUpdateProps(*this, tag, componentName, props);
  }
}

void RuntimeContext::mountView(
    int64_t tag,
    const std::string &componentName) {
  if (!isAcceptingTasks()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot mount an Expo view while its runtime is being destroyed.");
  }
  if (tag <= 0 || componentName.empty()) {
    throw CodedError(
        "ERR_INVALID_VIEW_HANDLE",
        "Expo view creation requires a positive tag and component name.");
  }
  std::scoped_lock lock(mutex_);
  const auto [iterator, inserted] = mountedViews_.emplace(tag, componentName);
  if (!inserted) {
    if (iterator->second == componentName) {
      throw CodedError(
          "ERR_VIEW_ALREADY_MOUNTED",
          "Expo view '" + componentName + "' with tag " + std::to_string(tag) + " was mounted more than once.");
    }
    throw CodedError(
        "ERR_VIEW_COMPONENT_MISMATCH",
        "Expo view tag " + std::to_string(tag) + " is already mounted as '" + iterator->second + "', not '" + componentName + "'.");
  }
  viewProps_.erase(tag);
}

void RuntimeContext::requireMountedView(
    int64_t tag,
    const std::string &componentName) const {
  std::scoped_lock lock(mutex_);
  const auto iterator = mountedViews_.find(tag);
  if (iterator == mountedViews_.end()) {
    throw CodedError(
        "ERR_VIEW_NOT_MOUNTED",
        "Expo view '" + componentName + "' with tag " + std::to_string(tag) + " is no longer mounted.");
  }
  if (iterator->second != componentName) {
    throw CodedError(
        "ERR_VIEW_COMPONENT_MISMATCH",
        "Expo view tag " + std::to_string(tag) + " belongs to '" + iterator->second + "', not '" + componentName + "'.");
  }
}

std::optional<std::string> RuntimeContext::mountedViewComponentNameIfPresent(
    int64_t tag) const {
  std::scoped_lock lock(mutex_);
  const auto iterator = mountedViews_.find(tag);
  if (iterator == mountedViews_.end()) {
    return std::nullopt;
  }
  return iterator->second;
}

bool RuntimeContext::unmountView(
    int64_t tag,
    const std::string &componentName) noexcept {
  std::scoped_lock lock(mutex_);
  const auto iterator = mountedViews_.find(tag);
  if (iterator == mountedViews_.end() || iterator->second != componentName) {
    return false;
  }
  mountedViews_.erase(iterator);
  viewProps_.erase(tag);
  return true;
}

void RuntimeContext::scheduleMountedViewTeardown() noexcept {
  if (!isRuntimeThread()) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Expo View teardown was requested off its owning JavaScript executor");
    return;
  }

  std::shared_ptr<RuntimeContext> context;
  std::shared_ptr<facebook::react::CallInvoker> invoker;
  try {
    std::scoped_lock lock(mutex_);
    context = invalidationLease_;
    invoker = jsInvoker_;
  } catch (...) {
    return;
  }
  if (!context) {
    return;
  }

  if (!taskExecutor_) {
    // Worklet runtimes have no MAIN queue; their empty view registry retires immediately.
    bool hasMountedViews = true;
    try {
      std::scoped_lock lock(mutex_);
      hasMountedViews = !mountedViews_.empty();
    } catch (...) {
      return;
    }
    if (hasMountedViews) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Cannot destroy mounted Expo views without a MAIN executor");
      return;
    }
    invalidateAfterViewTeardown();
    return;
  }
  if (!invoker) {
    return;
  }

  try {
    // MAIN queue ordering lets running callbacks finish before this snapshot.
    taskExecutor_->runTask(
        rnoh::TaskThread::MAIN,
        [context = std::move(context), invoker = std::move(invoker)]() {
          if (!context->destroyMountedViews()) {
            return;
          }
          try {
            auto delivery = std::make_shared<ScheduledCallbackGuard>([] {
              OH_LOG_Print(
                  LOG_APP,
                  LOG_ERROR,
                  kExpoModulesLogDomain,
                  kExpoModulesLogTag,
                  "Expo View teardown completed, but its JS continuation was discarded");
            });
            invoker->invokeAsync(
                [context = std::move(context),
                 delivery = std::move(delivery)](jsi::Runtime &) {
                  delivery->markDelivered();
                  context->invalidateAfterViewTeardown();
                });
          } catch (...) {
            OH_LOG_Print(
                LOG_APP,
                LOG_ERROR,
                kExpoModulesLogDomain,
                kExpoModulesLogTag,
                "Unable to schedule the Expo View teardown JS continuation");
          }
        });
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to schedule Expo View teardown on MAIN");
  }
}

bool RuntimeContext::destroyMountedViews() noexcept {
  try {
    if (!taskExecutor_ || !taskExecutor_->isOnTaskThread(rnoh::TaskThread::MAIN)) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Refusing to destroy Expo views outside the MAIN executor");
      return false;
    }
  } catch (...) {
    return false;
  }

  if (!moduleRegistry_) {
    try {
      std::scoped_lock lock(mutex_);
      if (mountedViews_.empty()) {
        return true;
      }
    } catch (...) {
    }
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Cannot destroy mounted Expo views without their module registry");
    return false;
  }

  std::vector<std::pair<int64_t, std::string>> mountedViews;
  try {
    std::scoped_lock lock(mutex_);
    mountedViews.reserve(mountedViews_.size());
    for (const auto &[tag, componentName] : mountedViews_) {
      mountedViews.emplace_back(tag, componentName);
    }
    mountedViews_.clear();
    viewProps_.clear();
  } catch (...) {
    // Do not ACK after losing the View callback snapshot.
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to snapshot mounted Expo views during runtime teardown");
    return false;
  }

  for (auto iterator = mountedViews.rbegin();
       iterator != mountedViews.rend();
       ++iterator) {
    const auto &[tag, componentName] = *iterator;
    const auto *view = moduleRegistry_->findView(componentName);
    if (!view || !view->onDestroy) {
      continue;
    }
    try {
      view->onDestroy(*this, tag, componentName);
    } catch (const CodedError &error) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Expo view %{public}s#%{public}lld failed during runtime teardown [%{public}s]: %{public}s",
          componentName.c_str(),
          static_cast<long long>(tag),
          error.code().c_str(),
          error.what());
    } catch (const std::exception &error) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Expo view %{public}s#%{public}lld failed during runtime teardown: %{public}s",
          componentName.c_str(),
          static_cast<long long>(tag),
          error.what());
    } catch (...) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Expo view %{public}s#%{public}lld failed during runtime teardown with an unknown native exception",
          componentName.c_str(),
          static_cast<long long>(tag));
    }
  }
  return true;
}

void RuntimeContext::initializeModuleRegistry() {
  assertRuntimeThread();
  if (!moduleRegistry_) {
    moduleRegistry_ = std::make_unique<ModuleRegistry>(shared_from_this());
    moduleRegistry_->initialize();
  }
}

bool RuntimeContext::hasModuleRegistry() const noexcept {
  return moduleRegistry_ != nullptr;
}

ModuleRegistry &RuntimeContext::moduleRegistry() const {
  if (!isAlive()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED", "The Expo module registry runtime was destroyed.");
  }
  if (!moduleRegistry_) {
    throw CodedError(
        "ERR_RUNTIME_NOT_INSTALLED", "Expo module registry is not initialized.");
  }
  return *moduleRegistry_;
}

long RuntimeContext::allocateSharedObjectId() {
  constexpr long kMaximumSharedObjectId = static_cast<long>(9007199254740991LL);
  auto candidate = nextObjectId_.load(std::memory_order_relaxed);

  while (true) {
    if (candidate <= 0 || candidate > kMaximumSharedObjectId) {
      throw CodedError(
          "ERR_SHARED_OBJECT_ID_EXHAUSTED",
          "The Expo SharedObject identity space for this runtime was exhausted.");
    }

    if (nextObjectId_.compare_exchange_weak(
            candidate,
            candidate + 1,
            std::memory_order_relaxed,
            std::memory_order_relaxed)) {
      return candidate;
    }
  }
}

long RuntimeContext::registerNativeSharedObject(
    std::shared_ptr<NativeSharedObject> object) {
  if (!object) {
    throw CodedError(
        "ERR_INVALID_SHARED_OBJECT", "Cannot register a null shared object.");
  }
  if (object->isReleaseRequested()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot materialize a native SharedObject after release was requested.");
  }
  std::scoped_lock lock(mutex_);
  if (!alive_.load(std::memory_order_acquire) || !acceptingTasks_.load(std::memory_order_acquire)) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot register a SharedObject while its runtime is being destroyed.");
  }
  auto existing = nativeSharedObjectIds_.find(object.get());
  if (existing != nativeSharedObjectIds_.end()) {
    if (sharedObjectInvocations_.isReleaseRequested(existing->second) || object->isReleaseRequested()) {
      throw CodedError(
          "ERR_SHARED_OBJECT_RELEASED",
          "Cannot materialize a native SharedObject after release was requested.");
    }
    return existing->second;
  }
  auto objectId = allocateSharedObjectId();
  object->bindToRuntime(weak_from_this(), objectId);
  nativeSharedObjectIds_[object.get()] = objectId;
  nativeSharedObjects_[objectId] = std::move(object);
  return objectId;
}

jsi::Value RuntimeContext::materializeNativeSharedObject(
    std::string moduleName,
    std::string className,
    std::shared_ptr<NativeSharedObject> nativeObject) {
  assertRuntimeThread();
  auto classValue = getClass(moduleName, className);
  if (!classValue.isObject() || !classValue.getObject(runtime()).isFunction(runtime())) {
    throw CodedError(
        "ERR_CLASS_NOT_FOUND",
        "Cannot materialize shared object class '" + moduleName + "." + className + "'.");
  }
  auto klass = classValue.getObject(runtime()).getFunction(runtime());
  auto prototype = klass.getPropertyAsObject(runtime(), "prototype");
  auto jsObject = expo::common::createObjectWithPrototype(runtime(), &prototype);
  return bindNativeSharedObject(
      std::move(moduleName),
      std::move(className),
      std::move(nativeObject),
      std::move(jsObject));
}

jsi::Value RuntimeContext::bindNativeSharedObject(
    std::string moduleName,
    std::string className,
    std::shared_ptr<NativeSharedObject> nativeObject,
    jsi::Object jsObject) {
  assertRuntimeThread();
  if (!nativeObject) {
    throw CodedError(
        "ERR_INVALID_SHARED_OBJECT", "Cannot bind a null shared object.");
  }
  const auto nativeRefType = nativeObject->nativeRefType();
  if (nativeRefType.empty()) {
    throw CodedError(
        "ERR_INVALID_SHARED_REF_TYPE",
        "A SharedRef nativeRefType must be a non-empty stable identifier.");
  }
  if (moduleName.empty() || className.empty()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        "A native SharedObject must have a registered Expo module and class.");
  }
  const bool isSharedRef = moduleRegistry().isSharedRefClass(moduleName, className);
  const bool nativeIsSharedRef = nativeRefType != "SharedObject";
  if (isSharedRef != nativeIsSharedRef) {
    // Validate before registration to avoid partial identity state.
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        isSharedRef
            ? "A SharedRef class must use a native object with a stable nativeRefType."
            : "A native SharedRef must be declared with the SharedRef JavaScript base class.");
  }
  auto objectId = registerNativeSharedObject(nativeObject);
  {
    std::scoped_lock lock(mutex_);
    auto [iterator, inserted] = nativeSharedObjectClasses_.emplace(
        objectId, std::make_pair(moduleName, className));
    if (!inserted && iterator->second != std::make_pair(moduleName, className)) {
      throw CodedError(
          "ERR_SHARED_OBJECT_TYPE",
          "A native object cannot be materialized as two unrelated Expo classes.");
    }
  }
  auto cached = getSharedObject(objectId);
  if (!cached.isUndefined()) {
    return cached;
  }
  jsObject.setNativeState(
      runtime(),
      std::make_shared<expo::SharedObject::NativeState>(
          objectId,
          [weakContext = weak_from_this()](long id) {
            if (auto context = weakContext.lock()) {
              context->scheduleSharedObjectRelease(id);
            }
          }));
  if (isSharedRef) {
    expo::common::defineProperty(
        runtime(),
        &jsObject,
        "nativeRefType",
        {
            .configurable = false,
            .enumerable = false,
            .writable = false,
            .value = jsi::String::createFromUtf8(runtime(), nativeRefType),
        });
  }
  const auto memoryPressure = nativeObject->getAdditionalMemoryPressure();
  if (memoryPressure > 0) {
    jsObject.setExternalMemoryPressure(runtime(), memoryPressure);
  }
  retainSharedObject(objectId, jsObject);
  return jsi::Value(runtime(), jsObject);
}

std::shared_ptr<NativeSharedObject> RuntimeContext::getNativeSharedObject(
    long objectId) const {
  std::scoped_lock lock(mutex_);
  auto iterator = nativeSharedObjects_.find(objectId);
  if (iterator == nativeSharedObjects_.end() || sharedObjectInvocations_.isReleaseRequested(objectId) || iterator->second->isReleaseRequested()) {
    const bool wasReleased = objectId > 0 && objectId < nextObjectId_.load(std::memory_order_acquire);
    throw CodedError(
        wasReleased ? "ERR_SHARED_OBJECT_RELEASED" : "ERR_INVALID_SHARED_OBJECT_ID",
        wasReleased
            ? "Cannot use shared object " + std::to_string(objectId) + " because it was already released."
            : "Shared object " + std::to_string(objectId) + " does not have a valid native object.");
  }
  return iterator->second;
}

std::shared_ptr<NativeSharedObject> RuntimeContext::getNativeSharedObject(
    long objectId,
    const std::string &moduleName,
    const std::string &className) const {
  std::scoped_lock lock(mutex_);
  auto nativeIterator = nativeSharedObjects_.find(objectId);
  auto classIterator = nativeSharedObjectClasses_.find(objectId);
  if (nativeIterator == nativeSharedObjects_.end() || classIterator == nativeSharedObjectClasses_.end() || sharedObjectInvocations_.isReleaseRequested(objectId) || nativeIterator->second->isReleaseRequested()) {
    const bool wasReleased = objectId > 0 && objectId < nextObjectId_.load(std::memory_order_acquire);
    throw CodedError(
        wasReleased ? "ERR_SHARED_OBJECT_RELEASED" : "ERR_INVALID_SHARED_OBJECT_ID",
        wasReleased
            ? "Cannot use shared object " + std::to_string(objectId) + " because it was already released."
            : "Shared object " + std::to_string(objectId) + " does not have a valid native object.");
  }
  const auto lineage = moduleRegistry_->sharedObjectClassLineage(
      classIterator->second.first, classIterator->second.second);
  if (sharedObjectClassIsAssignableTo(lineage, moduleName, className)) {
    return nativeIterator->second;
  }
  throw CodedError(
      "ERR_SHARED_OBJECT_TYPE",
      "SharedObject " + std::to_string(objectId) + " is not an instance of '" + moduleName + "." + className + "'.");
}

NativeSharedObjectIdentity RuntimeContext::nativeSharedObjectIdentity(
    const std::shared_ptr<NativeSharedObject> &object) const {
  if (!object) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot read the identity of a released SharedObject.");
  }
  std::scoped_lock lock(mutex_);
  const auto identity = nativeSharedObjectIds_.find(object.get());
  if (identity == nativeSharedObjectIds_.end() || !nativeSharedObjects_.contains(identity->second) || nativeSharedObjects_.at(identity->second) != object || sharedObjectInvocations_.isReleaseRequested(identity->second) || object->isReleaseRequested() || !object->isBoundToRuntime(this, identity->second)) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot read the identity of a released SharedObject.");
  }
  const auto klass = nativeSharedObjectClasses_.find(identity->second);
  if (klass == nativeSharedObjectClasses_.end()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_TYPE",
        "The SharedObject does not have a canonical Expo class binding.");
  }
  return NativeSharedObjectIdentity{
      .objectId = identity->second,
      .runtimeEpoch = runtimeEpochString(),
      .moduleName = klass->second.first,
      .className = klass->second.second,
      .nativeRefType = object->nativeRefType(),
      .classLineage = moduleRegistry_->sharedObjectClassLineage(
          klass->second.first, klass->second.second),
  };
}

NativeSharedObjectIdentity RuntimeContext::nativeSharedObjectIdentity(
    long objectId) const {
  return nativeSharedObjectIdentity(getNativeSharedObject(objectId));
}

SharedObjectInvocationIdentity RuntimeContext::captureSharedObjectInvocation(
    const std::shared_ptr<NativeSharedObject> &object) const {
  if (!object) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot queue work for a released SharedObject.");
  }
  std::scoped_lock lock(mutex_);
  auto identity = nativeSharedObjectIds_.find(object.get());
  if (!isAlive() || !isAcceptingTasks() || identity == nativeSharedObjectIds_.end() || sharedObjectInvocations_.isReleaseRequested(identity->second) || object->isReleaseRequested()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot queue work for a SharedObject after it was released.");
  }
  auto registered = nativeSharedObjects_.find(identity->second);
  if (registered == nativeSharedObjects_.end() || registered->second != object || !object->isBoundToRuntime(this, identity->second)) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot queue work for a SharedObject after it was released.");
  }
  return SharedObjectInvocationIdentity{
      .runtimeEpoch = runtimeEpoch_,
      .objectId = identity->second,
  };
}

SharedObjectInvocationLeaseBundle RuntimeContext::acquireSharedObjectInvocations(
    const std::vector<std::shared_ptr<NativeSharedObject>> &objects) {
  auto context = shared_from_this();
  std::vector<std::shared_ptr<NativeSharedObject>> uniqueObjects;
  uniqueObjects.reserve(objects.size());
  for (const auto &object : objects) {
    if (!object) {
      throw CodedError(
          "ERR_SHARED_OBJECT_RELEASED",
          "Cannot execute native work with a null SharedObject argument.");
    }
    if (std::none_of(
            uniqueObjects.begin(),
            uniqueObjects.end(),
            [&](const auto &candidate) {
              return candidate.get() == object.get();
            })) {
      uniqueObjects.push_back(object);
    }
  }

  std::vector<SharedObjectInvocationLeaseBundle::Entry> entries;
  entries.reserve(uniqueObjects.size());
  std::scoped_lock lock(mutex_);
  if (!isAlive() || !isAcceptingTasks()) {
    throw CodedError(
        "ERR_SHARED_OBJECT_RELEASED",
        "Cannot execute native work after its runtime started teardown.");
  }
  for (const auto &object : uniqueObjects) {
    const auto identity = nativeSharedObjectIds_.find(object.get());
    if (identity == nativeSharedObjectIds_.end() || sharedObjectInvocations_.isReleaseRequested(identity->second)) {
      throw CodedError(
          "ERR_SHARED_OBJECT_RELEASED",
          "Cannot execute native work because a SharedObject argument was released.");
    }
    const auto registered = nativeSharedObjects_.find(identity->second);
    if (registered == nativeSharedObjects_.end() || registered->second != object || object->isReleaseRequested() || !object->isBoundToRuntime(this, identity->second)) {
      throw CodedError(
          "ERR_SHARED_OBJECT_RELEASED",
          "Cannot execute native work because a SharedObject argument was released.");
    }
    entries.emplace_back(
        SharedObjectInvocationIdentity{
            .runtimeEpoch = runtimeEpoch_,
            .objectId = identity->second,
        },
        object);
  }

  size_t acquired = 0;
  try {
    for (const auto &[identity, object] : entries) {
      (void)object;
      if (!sharedObjectInvocations_.acquire(identity.objectId)) {
        throw CodedError(
            "ERR_SHARED_OBJECT_RELEASED",
            "Cannot execute native work because a SharedObject argument was released.");
      }
      ++acquired;
    }
  } catch (const CodedError &error) {
    for (size_t index = 0; index < acquired; ++index) {
      (void)sharedObjectInvocations_.release(entries[index].first.objectId);
    }
    throw CodedError(error);
  } catch (const std::exception &error) {
    for (size_t index = 0; index < acquired; ++index) {
      (void)sharedObjectInvocations_.release(entries[index].first.objectId);
    }
    throw std::runtime_error(error.what());
  } catch (...) {
    for (size_t index = 0; index < acquired; ++index) {
      (void)sharedObjectInvocations_.release(entries[index].first.objectId);
    }
    throw std::runtime_error(
        "Unknown native exception while acquiring SharedObject invocation leases.");
  }
  return SharedObjectInvocationLeaseBundle(
      std::move(context), std::move(entries));
}

void RuntimeContext::retainSharedObject(
    long objectId,
    const jsi::Object &object) {
  auto weakObject = std::make_shared<jsi::WeakObject>(runtime(), object);
  std::scoped_lock lock(mutex_);
  sharedObjects_[objectId] = std::move(weakObject);
}

void RuntimeContext::releaseSharedObject(long objectId) {
  assertRuntimeThread();
  std::shared_ptr<jsi::WeakObject> weakEmitter;
  {
    std::scoped_lock lock(mutex_);
    if (!nativeSharedObjects_.contains(objectId)) {
      return;
    }
    if (auto retained = sharedObjects_.find(objectId);
        retained != sharedObjects_.end()) {
      weakEmitter = retained->second;
    }
  }

  std::shared_ptr<jsi::Object> emitter;
  if (weakEmitter) {
    try {
      auto value = weakEmitter->lock(runtime());
      if (value.isObject()) {
        emitter = std::make_shared<jsi::Object>(
            value.getObject(runtime()));
        // Keep listener state for finalization after logical release.
        expo::EventEmitter::closeListenerAdmission(runtime(), *emitter);
      }
    } catch (...) {
      // Native observation state remains available if the JS object is gone.
    }
  }

  {
    std::scoped_lock lock(mutex_);
    if (!nativeSharedObjects_.contains(objectId)) {
      return;
    }
    (void)sharedObjectInvocations_.requestRelease(objectId);
    nativeSharedObjects_.at(objectId)->markReleaseRequested();
    if (!sharedObjectInvocations_.isReadyToFinalize(objectId)) {
      if (emitter) {
        deferredSharedObjectEmitters_.try_emplace(
            objectId, std::move(emitter));
      }
      return;
    }
  }
  finalizeSharedObjectRelease(objectId);
}

void RuntimeContext::finalizeSharedObjectRelease(long objectId) {
  assertRuntimeThread();
  std::shared_ptr<NativeSharedObject> released;
  std::shared_ptr<jsi::WeakObject> weakEmitter;
  std::shared_ptr<jsi::Object> emitter;
  {
    std::scoped_lock lock(mutex_);
    auto native = nativeSharedObjects_.find(objectId);
    if (native == nativeSharedObjects_.end() || !sharedObjectInvocations_.beginFinalization(objectId)) {
      return;
    }
    released = native->second;
    if (auto deferred = deferredSharedObjectEmitters_.find(objectId);
        deferred != deferredSharedObjectEmitters_.end()) {
      emitter = deferred->second;
    }
    if (auto retained = sharedObjects_.find(objectId);
        retained != sharedObjects_.end()) {
      weakEmitter = retained->second;
    }
  }

  std::optional<CodedError> releaseError;
  if (!emitter && weakEmitter) {
    try {
      auto value = weakEmitter->lock(runtime());
      if (value.isObject()) {
        emitter = std::make_shared<jsi::Object>(value.getObject(runtime()));
      }
    } catch (const CodedError &error) {
      releaseError.emplace(error);
    } catch (const std::exception &error) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED", error.what());
    } catch (...) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED",
          "Unable to lock the SharedObject event emitter during release.");
    }
  }

  if (emitter) {
    auto listenerError = expo::EventEmitter::drainListeners(
        runtime(),
        *emitter,
        [this, objectId](const std::string &eventName) {
          endObservingSharedObject(objectId, eventName);
        });
    if (!releaseError && listenerError) {
      releaseError.emplace(*listenerError);
    }
  }

  // Native observation state handles finalization after the JS object is gone.
  std::vector<SharedObjectObservationState::PendingStop> pendingStops;
  try {
    std::scoped_lock lock(mutex_);
    pendingStops = sharedObjectObservations_.drain(objectId);
  } catch (const CodedError &error) {
    if (!releaseError) {
      releaseError.emplace(error);
    }
  } catch (const std::exception &error) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED", error.what());
    }
  } catch (...) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED",
          "Unable to drain SharedObject observations during release.");
    }
  }

  for (auto &stop : pendingStops) {
    try {
      stop.hook(stop.eventName, stop.remainingEventCount);
    } catch (const CodedError &error) {
      if (!releaseError) {
        releaseError.emplace(error);
      }
    } catch (const std::exception &error) {
      if (!releaseError) {
        releaseError.emplace(
            "ERR_SHARED_OBJECT_RELEASE_FAILED", error.what());
      }
    } catch (...) {
      if (!releaseError) {
        releaseError.emplace(
            "ERR_SHARED_OBJECT_RELEASE_FAILED",
            "A SharedObject observation hook failed during release.");
      }
    }
  }

  // Retain a drained wrapper tombstone so released SharedObjects are recognized.
  try {
    released->sharedObjectWillRelease();
  } catch (const CodedError &error) {
    if (!releaseError) {
      releaseError.emplace(error);
    }
  } catch (const std::exception &error) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED", error.what());
    }
  } catch (...) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED",
          "SharedObject willRelease failed with a native exception.");
    }
  }

  try {
    // Retire ArkTS state before erasing native identity.
    callPlatformSync(
        "releaseExpoSharedObject", {runtimeEpochString(), objectId});
  } catch (const CodedError &error) {
    if (!releaseError) {
      releaseError.emplace(error);
    }
  } catch (const std::exception &error) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED", error.what());
    }
  } catch (...) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED",
          "Unable to retire the ArkTS SharedObject during release.");
    }
  }

  {
    std::scoped_lock lock(mutex_);
    sharedObjects_.erase(objectId);
    deferredSharedObjectEmitters_.erase(objectId);
    auto native = nativeSharedObjects_.find(objectId);
    if (native != nativeSharedObjects_.end() && native->second == released) {
      nativeSharedObjectIds_.erase(released.get());
      nativeSharedObjects_.erase(native);
    }
    nativeSharedObjectClasses_.erase(objectId);
  }

  try {
    released->sharedObjectDidRelease();
  } catch (const CodedError &error) {
    if (!releaseError) {
      releaseError.emplace(error);
    }
  } catch (const std::exception &error) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED", error.what());
    }
  } catch (...) {
    if (!releaseError) {
      releaseError.emplace(
          "ERR_SHARED_OBJECT_RELEASE_FAILED",
          "SharedObject didRelease failed with a native exception.");
    }
  }

  // Keep the runtime binding until release callbacks finish.
  released->unbindFromRuntime(this, objectId);
  {
    std::scoped_lock lock(mutex_);
    sharedObjectInvocations_.completeRelease(objectId);
  }
  maybeFinishInvalidationAfterSharedObjects();
  if (releaseError) {
    throw CodedError(*releaseError);
  }
}

void RuntimeContext::releaseSharedObjectInvocations(
    std::vector<SharedObjectInvocationLeaseBundle::Entry> entries) noexcept {
  {
    std::scoped_lock lock(mutex_);
    for (auto &[identity, object] : entries) {
      if (identity.runtimeEpoch != runtimeEpoch_ || identity.objectId <= 0) {
        identity.runtimeEpoch = kInvalidRuntimeEpoch;
        continue;
      }
      const auto registered = nativeSharedObjects_.find(identity.objectId);
      if (registered == nativeSharedObjects_.end() || registered->second != object || !sharedObjectInvocations_.release(identity.objectId)) {
        identity.runtimeEpoch = kInvalidRuntimeEpoch;
      }
    }
  }
  for (const auto &[identity, object] : entries) {
    (void)object;
    if (identity.runtimeEpoch == runtimeEpoch_) {
      scheduleSharedObjectReleaseFinalization(identity.objectId);
    }
  }
}

void RuntimeContext::scheduleSharedObjectReleaseFinalization(
    long objectId) noexcept {
  std::shared_ptr<RuntimeContext> context;
  try {
    context = shared_from_this();
  } catch (...) {
    return;
  }
  auto invoker = jsInvoker_;
  if (!invoker) {
    return;
  }
  try {
    auto delivery = std::make_shared<ScheduledCallbackGuard>([objectId] {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "SharedObject %{public}ld release continuation was discarded by its JS executor",
          objectId);
    });
    invoker->invokeAsync(
        [context = std::move(context), objectId, delivery = std::move(delivery)](jsi::Runtime &) {
          delivery->markDelivered();
          if (!context->isAlive()) {
            return;
          }
          try {
            context->releaseSharedObject(objectId);
          } catch (const CodedError &error) {
            logSharedObjectReleaseError(
                objectId, "deferred invocation release", error.what());
          } catch (const std::exception &error) {
            logSharedObjectReleaseError(
                objectId, "deferred invocation release", error.what());
          } catch (...) {
            logSharedObjectReleaseError(
                objectId, "deferred invocation release");
          }
        });
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to schedule SharedObject %{public}ld release continuation",
        objectId);
  }
}

void RuntimeContext::scheduleSharedObjectRelease(long objectId) noexcept {
  if (!isAlive()) {
    return;
  }
  if (isRuntimeThread()) {
    try {
      releaseSharedObject(objectId);
    } catch (const CodedError &error) {
      logSharedObjectReleaseError(
          objectId, "explicit/finalizer release", error.what());
    } catch (const std::exception &error) {
      logSharedObjectReleaseError(
          objectId, "explicit/finalizer release", error.what());
    } catch (...) {
      logSharedObjectReleaseError(
          objectId, "explicit/finalizer release");
    }
    return;
  }
  if (!jsInvoker_) {
    return;
  }
  scheduleSharedObjectReleaseFinalization(objectId);
}

jsi::Value RuntimeContext::getSharedObject(long objectId) {
  assertRuntimeThread();
  std::shared_ptr<jsi::WeakObject> weakObject;
  {
    std::scoped_lock lock(mutex_);
    const auto native = nativeSharedObjects_.find(objectId);
    auto iterator = sharedObjects_.find(objectId);
    if (iterator == sharedObjects_.end() || native == nativeSharedObjects_.end() || sharedObjectInvocations_.isReleaseRequested(objectId) || native->second->isReleaseRequested()) {
      return jsi::Value::undefined();
    }
    weakObject = iterator->second;
  }
  auto value = weakObject->lock(runtime());
  if (value.isUndefined()) {
    std::scoped_lock lock(mutex_);
    auto iterator = sharedObjects_.find(objectId);
    if (iterator != sharedObjects_.end() && iterator->second == weakObject) {
      sharedObjects_.erase(iterator);
    }
  }
  return value;
}

size_t RuntimeContext::beginObservingSharedObject(
    long objectId,
    std::string eventName,
    SharedObjectObservationState::StopHook stopHook) {
  std::scoped_lock lock(mutex_);
  if (!nativeSharedObjects_.contains(objectId) || sharedObjectInvocations_.isReleaseRequested(objectId)) {
    return 0;
  }
  return sharedObjectObservations_.begin(
      objectId, std::move(eventName), std::move(stopHook));
}

bool RuntimeContext::endObservingSharedObject(
    long objectId,
    const std::string &eventName) {
  std::optional<SharedObjectObservationState::PendingStop> pending;
  {
    std::scoped_lock lock(mutex_);
    pending = sharedObjectObservations_.take(objectId, eventName);
  }
  if (!pending) {
    return false;
  }
  pending->hook(pending->eventName, pending->remainingEventCount);
  return true;
}

bool RuntimeContext::isObservingSharedObject(
    long objectId,
    const std::string &eventName) const noexcept {
  std::scoped_lock lock(mutex_);
  return sharedObjectObservations_.contains(objectId, eventName);
}

void RuntimeContext::retainClass(
    std::string moduleName,
    std::string className,
    const jsi::Function &klass) {
  std::scoped_lock lock(mutex_);
  auto key = std::move(moduleName) + "\n" + std::move(className);
  classes_[std::move(key)] = std::make_unique<jsi::Function>(
      jsi::Value(runtime(), klass).getObject(runtime()).getFunction(runtime()));
}

jsi::Value RuntimeContext::getClass(
    const std::string &moduleName,
    const std::string &className) {
  std::scoped_lock lock(mutex_);
  auto iterator = classes_.find(moduleName + "\n" + className);
  if (iterator == classes_.end()) {
    return jsi::Value::undefined();
  }
  return jsi::Value(runtime(), *iterator->second);
}

void RuntimeContext::retainModule(
    std::string name,
    const jsi::Object &module) {
  std::scoped_lock lock(mutex_);
  modules_[std::move(name)] = std::make_unique<jsi::Object>(
      jsi::Value(runtime(), module).getObject(runtime()));
}

jsi::Value RuntimeContext::getModule(const std::string &name) {
  std::scoped_lock lock(mutex_);
  auto iterator = modules_.find(name);
  if (iterator == modules_.end()) {
    return jsi::Value::undefined();
  }
  return jsi::Value(runtime(), *iterator->second);
}

void RuntimeContext::drainModuleListeners() noexcept {
  std::vector<std::pair<std::string, jsi::Object>> modules;
  try {
    std::scoped_lock lock(mutex_);
    modules.reserve(modules_.size());
    for (const auto &[moduleName, module] : modules_) {
      modules.emplace_back(
          moduleName,
          jsi::Value(runtime(), *module).getObject(runtime()));
    }
  } catch (...) {
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to snapshot Expo module listeners during runtime teardown");
    return;
  }

  for (auto &[moduleName, module] : modules) {
    auto error = expo::EventEmitter::drainListeners(runtime(), module, {});
    if (error) {
      OH_LOG_Print(
          LOG_APP,
          LOG_ERROR,
          kExpoModulesLogDomain,
          kExpoModulesLogTag,
          "Expo module %{public}s failed to stop observing during runtime teardown: %{public}s",
          moduleName.c_str(),
          error->what());
    }
  }
}

void RuntimeContext::clearJSIReferences() {
  assertRuntimeThread();
  {
    std::scoped_lock lock(mutex_);
    for (const auto &[pointer, promise] : promises_) {
      (void)pointer;
      promise->invalidate();
    }
    promises_.clear();
  }
  releaseAllSharedObjects();
  {
    std::scoped_lock lock(mutex_);
    if (!nativeSharedObjects_.empty() || sharedObjectInvocations_.hasFinalizing()) {
      throw CodedError(
          "ERR_SHARED_OBJECT_BUSY",
          "Cannot clear Expo runtime references while SharedObject invocations are still active.");
    }
    sharedObjects_.clear();
    deferredSharedObjectEmitters_.clear();
    nativeSharedObjects_.clear();
    nativeSharedObjectIds_.clear();
    nativeSharedObjectClasses_.clear();
    sharedObjectInvocations_.clear();
    sharedObjectObservations_.clear();
    runtimeInvocations_.clear();
    modules_.clear();
    classes_.clear();
    viewProps_.clear();
    mountedViews_.clear();
  }
}

void RuntimeContext::releaseAllSharedObjects() noexcept {
  std::vector<long> objectIds;
  try {
    std::scoped_lock lock(mutex_);
    if (sharedObjectReleaseSweepActive_) {
      return;
    }
    sharedObjectReleaseSweepActive_ = true;
    objectIds.reserve(nativeSharedObjects_.size());
    for (const auto &[objectId, object] : nativeSharedObjects_) {
      (void)object;
      // Defer re-entrant invalidation until this object is erased.
      if (!sharedObjectInvocations_.isFinalizing(objectId)) {
        objectIds.push_back(objectId);
      }
    }
  } catch (...) {
    try {
      std::scoped_lock lock(mutex_);
      sharedObjectReleaseSweepActive_ = false;
    } catch (...) {
    }
    OH_LOG_Print(
        LOG_APP,
        LOG_ERROR,
        kExpoModulesLogDomain,
        kExpoModulesLogTag,
        "Unable to snapshot SharedObjects during runtime teardown");
    return;
  }

  for (const auto objectId : objectIds) {
    try {
      releaseSharedObject(objectId);
    } catch (const CodedError &error) {
      logSharedObjectReleaseError(
          objectId, "runtime teardown", error.what());
    } catch (const std::exception &error) {
      logSharedObjectReleaseError(
          objectId, "runtime teardown", error.what());
    } catch (...) {
      logSharedObjectReleaseError(objectId, "runtime teardown");
    }
  }
  {
    std::scoped_lock lock(mutex_);
    sharedObjectReleaseSweepActive_ = false;
  }
  maybeFinishInvalidationAfterSharedObjects();
}

void RuntimeContext::retainPromise(const std::shared_ptr<Promise> &promise) {
  if (!promise) {
    return;
  }
  assertRuntimeThread();
  std::scoped_lock lock(mutex_);
  promises_[promise.get()] = promise;
}

void RuntimeContext::releasePromise(const Promise *promise) {
  assertRuntimeThread();
  std::scoped_lock lock(mutex_);
  promises_.erase(promise);
}

void RuntimeContext::cancelAndRejectPendingPromises() noexcept {
  decltype(promises_) promises;
  {
    std::scoped_lock lock(mutex_);
    promises.swap(promises_);
  }
  for (const auto &[pointer, promise] : promises) {
    (void)pointer;
    promise->cancelAndReject();
  }
}

}  // namespace expo::harmony
