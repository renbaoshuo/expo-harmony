#include "RuntimeContext.h"

#include <algorithm>
#include <cstring>
#include <exception>
#include <optional>

#include <jsi/JSIDynamic.h>

#include <common/EventEmitter.h>
#include <common/JSI/JSIUtils.h>
#include <common/LazyObject.h>
#include <common/SharedObject.h>
#include <common/SharedRef.h>
#include <worklets/WorkletRuntime/WorkletRuntime.h>

#include "api/ModuleDefinition.h"
#include "api/Promise.h"
#include "errors/CodedError.h"
#include "modules/ExpoModulesCoreTurboModule.h"
#include "runtime/ModuleRegistry.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

jsi::Value unwrapPlatformServiceResult(
    jsi::Runtime &runtime,
    const jsi::Value &result) {
  if (!result.isObject()) {
    throw makeJSError(
        runtime,
        "ERR_PLATFORM_ADAPTER",
        "The Harmony platform service returned an invalid result.");
  }
  auto object = result.getObject(runtime);
  auto ok = object.getProperty(runtime, "ok");
  if (!ok.isBool()) {
    throw makeJSError(
        runtime,
        "ERR_PLATFORM_ADAPTER",
        "The Harmony platform service result is missing its status.");
  }
  if (ok.getBool()) {
    return object.getProperty(runtime, "value");
  }

  auto codeValue = object.getProperty(runtime, "code");
  auto messageValue = object.getProperty(runtime, "message");
  const auto code = codeValue.isString()
                      ? codeValue.getString(runtime).utf8(runtime)
                      : std::string("ERR_PLATFORM_ADAPTER");
  const auto message = messageValue.isString()
                         ? messageValue.getString(runtime).utf8(runtime)
                         : std::string("The Harmony platform service failed.");
  throw makeJSError(runtime, code, message);
}

}  // namespace

RuntimeContext::RuntimeContext(
    jsi::Runtime &runtime,
    std::shared_ptr<facebook::react::CallInvoker> jsInvoker,
    rnoh::TaskExecutor::Shared taskExecutor,
    std::weak_ptr<ExpoModulesCoreTurboModule> turboModule)
    : runtime_(&runtime),
      jsInvoker_(std::move(jsInvoker)),
      taskExecutor_(std::move(taskExecutor)),
      turboModule_(std::move(turboModule)),
      runtimeThread_(std::this_thread::get_id()) {}

RuntimeContext::~RuntimeContext() {
  invalidate();
}

jsi::Runtime &RuntimeContext::runtime() const {
  if (!isAlive() || runtime_ == nullptr) {
    throw CodedError("ERR_RUNTIME_DESTROYED", "The Expo JavaScript runtime has been destroyed.");
  }
  return *runtime_;
}

std::shared_ptr<facebook::react::CallInvoker> RuntimeContext::jsInvoker() const {
  return jsInvoker_;
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
  if (!isAlive()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot attach Expo Modules Core to a destroyed runtime.");
  }
  std::scoped_lock lock(mutex_);
  turboModule_ = std::move(turboModule);
}

bool RuntimeContext::isAlive() const noexcept {
  return alive_.load(std::memory_order_acquire);
}

bool RuntimeContext::isRuntimeThread() const noexcept {
  return runtimeThread_ == std::this_thread::get_id();
}

void RuntimeContext::assertRuntimeThread() const {
  if (!isRuntimeThread()) {
    throw CodedError(
        "ERR_WRONG_THREAD",
        "Hermes JSI values may only be accessed on the owning JavaScript executor.");
  }
}

void RuntimeContext::invalidate() noexcept {
  if (!isAlive()) {
    return;
  }
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
      jsInvoker_->invokeAsync(
          [context = std::move(retainedContext)](jsi::Runtime &) {
            context->invalidationScheduled_.store(
                false, std::memory_order_release);
            context->invalidate();
          });
    } else {
      invalidationScheduled_.store(false, std::memory_order_release);
    }
    return;
  }
  if (invalidating_.exchange(true, std::memory_order_acq_rel)) {
    return;
  }
  if (moduleRegistry_) {
    moduleRegistry_->destroy();
  }
  clearJSIReferences();
  alive_.store(false, std::memory_order_release);
  runtime_ = nullptr;
}

void RuntimeContext::dispatch(FunctionQueue queue, std::function<void()> task) {
  if (!task || !isAlive()) {
    return;
  }
  auto guarded = [weakContext = weak_from_this(), task = std::move(task)]() mutable {
    auto context = weakContext.lock();
    if (context && context->isAlive()) {
      task();
    }
  };
  switch (queue) {
    case FunctionQueue::JavaScript:
      if (!jsInvoker_) {
        throw CodedError("ERR_QUEUE_UNAVAILABLE", "The Harmony JavaScript queue is unavailable.");
      }
      jsInvoker_->invokeAsync(std::move(guarded));
      return;
    case FunctionQueue::Main:
      if (!taskExecutor_) {
        throw CodedError("ERR_QUEUE_UNAVAILABLE", "The Harmony main queue is unavailable.");
      }
      taskExecutor_->runTask(rnoh::TaskThread::MAIN, std::move(guarded));
      return;
    case FunctionQueue::Modules:
      if (!jsInvoker_) {
        throw CodedError("ERR_QUEUE_UNAVAILABLE", "The Harmony modules queue is unavailable.");
      }
      jsInvoker_->invokeAsync(std::move(guarded));
      return;
    case FunctionQueue::Background:
      if (!taskExecutor_) {
        throw CodedError("ERR_QUEUE_UNAVAILABLE", "The Harmony worker queue is unavailable.");
      }
      taskExecutor_->runTask(rnoh::TaskThread::WORKER, std::move(guarded));
      return;
    case FunctionQueue::UI: {
      assertRuntimeThread();
      auto holder = runtime().global().getProperty(runtime(), "_WORKLET_RUNTIME");
      if (!holder.isObject() || !holder.getObject(runtime()).isArrayBuffer(runtime())) {
        throw CodedError(
            "ERR_WORKLET_RUNTIME_UNAVAILABLE",
            "The UI Runtime is unavailable. Install and import react-native-worklets first.");
      }
      auto buffer = holder.getObject(runtime()).getArrayBuffer(runtime());
      if (buffer.size(runtime()) != sizeof(jsi::Runtime *)) {
        throw CodedError(
            "ERR_INVALID_WORKLET_RUNTIME",
            "_WORKLET_RUNTIME does not contain one runtime pointer.");
      }
      jsi::Runtime *uiRuntime = nullptr;
      std::memcpy(&uiRuntime, buffer.data(runtime()), sizeof(uiRuntime));
      if (!uiRuntime) {
        throw CodedError(
            "ERR_INVALID_WORKLET_RUNTIME", "_WORKLET_RUNTIME contains a null pointer.");
      }
      auto workletRuntime = worklets::WorkletRuntime::getWeakRuntimeFromJSIRuntime(*uiRuntime).lock();
      if (!workletRuntime) {
        throw CodedError(
            "ERR_WORKLET_RUNTIME_DESTROYED", "The UI Runtime has been destroyed.");
      }
      workletRuntime->schedule(std::move(guarded));
      return;
    }
  }
}

void RuntimeContext::emitModuleEvent(
    std::string moduleName,
    std::string eventName,
    std::vector<folly::dynamic> arguments) {
  auto task = [weakContext = weak_from_this(),
               moduleName = std::move(moduleName),
               eventName = std::move(eventName),
               arguments = std::move(arguments)]() mutable {
    auto context = weakContext.lock();
    if (!context || !context->isAlive()) {
      return;
    }
    context->assertRuntimeThread();
    auto moduleValue = context->getModule(moduleName);
    if (!moduleValue.isObject()) {
      return;
    }
    auto moduleWrapper = moduleValue.getObject(context->runtime());
    const auto &unwrappedModule = expo::LazyObject::unwrapObjectIfNecessary(
        context->runtime(), moduleWrapper);
    auto module = jsi::Value(context->runtime(), unwrappedModule)
                      .getObject(context->runtime());
    std::vector<jsi::Value> values;
    values.reserve(arguments.size());
    for (const auto &argument : arguments) {
      values.push_back(jsi::valueFromDynamic(context->runtime(), argument));
    }
    expo::EventEmitter::emitEvent(
        context->runtime(), module, eventName, values);
  };
  if (isRuntimeThread()) {
    task();
  } else if (jsInvoker_) {
    jsInvoker_->invokeAsync(std::move(task));
  }
}

void RuntimeContext::emitSharedObjectEvent(
    long objectId,
    std::string eventName,
    std::vector<folly::dynamic> arguments) {
  auto task = [weakContext = weak_from_this(),
               objectId,
               eventName = std::move(eventName),
               arguments = std::move(arguments)]() mutable {
    auto context = weakContext.lock();
    if (!context || !context->isAlive()) {
      return;
    }
    context->assertRuntimeThread();
    auto objectValue = context->getSharedObject(objectId);
    if (!objectValue.isObject()) {
      return;
    }
    auto object = objectValue.getObject(context->runtime());
    std::vector<jsi::Value> values;
    values.reserve(arguments.size());
    for (const auto &argument : arguments) {
      values.push_back(jsi::valueFromDynamic(context->runtime(), argument));
    }
    expo::EventEmitter::emitEvent(
        context->runtime(), object, eventName, values);
  };
  if (isRuntimeThread()) {
    task();
  } else if (jsInvoker_) {
    jsInvoker_->invokeAsync(std::move(task));
  }
}

void RuntimeContext::emitSharedObjectEvent(
    long objectId,
    std::string eventName,
    std::vector<SharedObjectEventArgument> arguments) {
  auto task = [weakContext = weak_from_this(),
               objectId,
               eventName = std::move(eventName),
               arguments = std::move(arguments)]() mutable {
    auto context = weakContext.lock();
    if (!context || !context->isAlive()) {
      return;
    }
    context->assertRuntimeThread();
    auto objectValue = context->getSharedObject(objectId);
    if (!objectValue.isObject()) {
      return;
    }
    auto object = objectValue.getObject(context->runtime());
    std::vector<jsi::Value> values;
    values.reserve(arguments.size());
    try {
      for (auto &argument : arguments) {
        values.push_back(argument
                             ? argument(context)
                             : jsi::Value::undefined());
      }
      expo::EventEmitter::emitEvent(
          context->runtime(), object, eventName, values);
    } catch (...) {
      // Events are best-effort and must not terminate the JavaScript executor
      // when a native-to-JS argument conversion fails.
    }
  };
  if (isRuntimeThread()) {
    task();
  } else if (jsInvoker_) {
    jsInvoker_->invokeAsync(std::move(task));
  }
}

void RuntimeContext::postPlatformMessage(
    std::string name,
    folly::dynamic payload) {
  turboModule()->postMessageToArkTS(name, payload);
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

facebook::jsi::Value RuntimeContext::invokePlatformService(
    std::string serviceName,
    std::string methodName,
    folly::dynamic arguments) {
  if (!arguments.isArray()) {
    throw CodedError(
        "ERR_PLATFORM_ADAPTER",
        "Platform service arguments must be a copy-value array.");
  }
  auto result = callPlatformAsync(
      "invokePlatformService",
      {
          std::move(serviceName),
          std::move(methodName),
          std::move(arguments),
      });
  if (!result.isObject()) {
    throw CodedError(
        "ERR_PLATFORM_ADAPTER",
        "The Harmony platform bridge did not return a Promise.");
  }
  auto promise = result.getObject(runtime());
  auto thenValue = promise.getProperty(runtime(), "then");
  if (!thenValue.isObject() || !thenValue.getObject(runtime()).isFunction(runtime())) {
    throw CodedError(
        "ERR_PLATFORM_ADAPTER",
        "The Harmony platform bridge did not return a Promise.");
  }
  auto unwrap = jsi::Function::createFromHostFunction(
      runtime(),
      jsi::PropNameID::forAscii(runtime(), "unwrapExpoPlatformServiceResult"),
      1,
      [](jsi::Runtime &runtime,
         const jsi::Value &,
         const jsi::Value *arguments,
         size_t count) -> jsi::Value {
        if (count == 0) {
          throw makeJSError(
              runtime,
              "ERR_PLATFORM_ADAPTER",
              "The Harmony platform service returned no result.");
        }
        return unwrapPlatformServiceResult(runtime, arguments[0]);
      });
  return thenValue.getObject(runtime())
      .getFunction(runtime())
      .callWithThis(runtime(), promise, unwrap);
}

facebook::jsi::Value RuntimeContext::invokePlatformServiceSync(
    std::string serviceName,
    std::string methodName,
    folly::dynamic arguments) {
  if (!arguments.isArray()) {
    throw CodedError(
        "ERR_PLATFORM_ADAPTER",
        "Platform service arguments must be a copy-value array.");
  }
  auto result = callPlatformSync(
      "invokePlatformServiceSync",
      {
          std::move(serviceName),
          std::move(methodName),
          std::move(arguments),
      });
  try {
    return unwrapPlatformServiceResult(runtime(), result);
  } catch (const jsi::JSError &) {
    throw;
  }
}

void RuntimeContext::updateViewProps(
    const ViewDefinition &view,
    int64_t tag,
    const std::string &componentName,
    const folly::dynamic &props) {
  if (!props.isObject()) {
    return;
  }

  struct ViewPropChange final {
    const ViewPropDefinition *definition;
    std::string name;
    folly::dynamic storedValue;
    folly::dynamic setterValue;
  };

  std::vector<ViewPropChange> changes;
  {
    std::scoped_lock lock(mutex_);
    auto &previousProps = viewProps_.try_emplace(tag, folly::dynamic::object()).first->second;
    for (const auto &prop : view.props) {
      if (!prop.setter) {
        continue;
      }
      const auto *currentValue = props.get_ptr(prop.name);
      // Fabric raw props use an explicit null to reset a prop. An omitted key
      // means that this descriptor update does not change the prop.
      if (currentValue == nullptr) {
        continue;
      }
      const auto *previousValue = previousProps.get_ptr(prop.name);
      const bool currentIsNil = currentValue->isNull();
      const bool previousIsNil = previousValue == nullptr || previousValue->isNull();
      if ((currentIsNil && previousIsNil) || (previousValue != nullptr && *currentValue == *previousValue)) {
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

void RuntimeContext::forgetView(int64_t tag) noexcept {
  std::scoped_lock lock(mutex_);
  viewProps_.erase(tag);
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
  return nextObjectId_.fetch_add(1, std::memory_order_relaxed);
}

long RuntimeContext::registerNativeSharedObject(
    std::shared_ptr<NativeSharedObject> object) {
  if (!object) {
    throw CodedError(
        "ERR_INVALID_SHARED_OBJECT", "Cannot register a null shared object.");
  }
  std::scoped_lock lock(mutex_);
  auto existing = nativeSharedObjectIds_.find(object.get());
  if (existing != nativeSharedObjectIds_.end()) {
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

jsi::Value RuntimeContext::materializeNativeSharedObject(
    std::shared_ptr<NativeSharedObject> nativeObject) {
  assertRuntimeThread();
  if (!nativeObject) {
    throw CodedError(
        "ERR_INVALID_SHARED_OBJECT",
        "Cannot materialize a null shared object.");
  }

  std::optional<std::pair<std::string, std::string>> registeredClass;
  {
    std::scoped_lock lock(mutex_);
    NativeSharedObject &nativeReference = *nativeObject;
    auto iterator = nativeClasses_.find(std::type_index(typeid(nativeReference)));
    if (iterator != nativeClasses_.end()) {
      registeredClass = iterator->second;
    }
  }
  if (registeredClass) {
    return materializeNativeSharedObject(
        registeredClass->first,
        registeredClass->second,
        std::move(nativeObject));
  }

  const bool isSharedRef = nativeObject->nativeRefType() != "SharedObject";
  auto baseClass = isSharedRef
                     ? expo::SharedRef::getBaseClass(runtime())
                     : expo::SharedObject::getBaseClass(runtime());
  auto prototype = baseClass.getPropertyAsObject(runtime(), "prototype");
  auto jsObject = expo::common::createObjectWithPrototype(runtime(), &prototype);
  return bindNativeSharedObject(
      {},
      isSharedRef ? "SharedRef" : "SharedObject",
      std::move(nativeObject),
      std::move(jsObject));
}

jsi::Value RuntimeContext::bindNativeSharedObject(
    std::string moduleName,
    std::string className,
    std::shared_ptr<NativeSharedObject> nativeObject,
    jsi::Object jsObject) {
  assertRuntimeThread();
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
  expo::common::defineProperty(
      runtime(),
      &jsObject,
      "__expo_shared_object_id__",
      {
          .configurable = false,
          .enumerable = false,
          .writable = false,
          .value = static_cast<double>(objectId),
      });
  jsObject.setNativeState(
      runtime(),
      std::make_shared<expo::SharedObject::NativeState>(
          objectId,
          [weakContext = weak_from_this()](long id) {
            if (auto context = weakContext.lock()) {
              context->scheduleSharedObjectRelease(id);
            }
          }));
  const bool isSharedRef = (moduleName.empty() && className == "SharedRef") || (!moduleName.empty() && moduleRegistry().isSharedRefClass(moduleName, className));
  if (isSharedRef) {
    expo::common::defineProperty(
        runtime(),
        &jsObject,
        "nativeRefType",
        {
            .configurable = false,
            .enumerable = false,
            .writable = false,
            .value = jsi::String::createFromUtf8(runtime(), nativeObject->nativeRefType()),
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
  if (iterator == nativeSharedObjects_.end()) {
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
  if (nativeIterator == nativeSharedObjects_.end() || classIterator == nativeSharedObjectClasses_.end()) {
    const bool wasReleased = objectId > 0 && objectId < nextObjectId_.load(std::memory_order_acquire);
    throw CodedError(
        wasReleased ? "ERR_SHARED_OBJECT_RELEASED" : "ERR_INVALID_SHARED_OBJECT_ID",
        wasReleased
            ? "Cannot use shared object " + std::to_string(objectId) + " because it was already released."
            : "Shared object " + std::to_string(objectId) + " does not have a valid native object.");
  }
  auto actualModule = classIterator->second.first;
  auto actualClass = classIterator->second.second;
  for (size_t depth = 0; depth < 64; ++depth) {
    if (actualModule == moduleName && actualClass == className) {
      return nativeIterator->second;
    }
    const auto *moduleDefinition = moduleRegistry_->find(actualModule);
    if (!moduleDefinition) {
      break;
    }
    auto definition = std::find_if(
        moduleDefinition->classes.begin(),
        moduleDefinition->classes.end(),
        [&](const ClassDefinition &candidate) {
          return candidate.name == actualClass;
        });
    if (definition == moduleDefinition->classes.end() || definition->baseClassName == "SharedObject" || definition->baseClassName == "SharedRef") {
      break;
    }
    auto separator = definition->baseClassName.find('.');
    if (separator == std::string::npos) {
      actualClass = definition->baseClassName;
    } else {
      actualModule = definition->baseClassName.substr(0, separator);
      actualClass = definition->baseClassName.substr(separator + 1);
    }
  }
  throw CodedError(
      "ERR_SHARED_OBJECT_TYPE",
      "SharedObject " + std::to_string(objectId) + " is not an instance of '" + moduleName + "." + className + "'.");
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
  std::shared_ptr<NativeSharedObject> released;
  {
    std::scoped_lock lock(mutex_);
    auto native = nativeSharedObjects_.find(objectId);
    if (native == nativeSharedObjects_.end() || !releasingSharedObjectIds_.insert(objectId).second) {
      return;
    }
    released = native->second;
  }

  std::exception_ptr releaseError;
  try {
    released->sharedObjectWillRelease();
  } catch (...) {
    releaseError = std::current_exception();
  }

  {
    std::scoped_lock lock(mutex_);
    sharedObjects_.erase(objectId);
    auto native = nativeSharedObjects_.find(objectId);
    if (native != nativeSharedObjects_.end() && native->second == released) {
      nativeSharedObjectIds_.erase(released.get());
      nativeSharedObjects_.erase(native);
    }
    nativeSharedObjectClasses_.erase(objectId);
    sharedObjectObservationCounts_.erase(objectId);
    releasingSharedObjectIds_.erase(objectId);
  }

  released->unbindFromRuntime();
  try {
    released->sharedObjectDidRelease();
  } catch (...) {
    if (!releaseError) {
      releaseError = std::current_exception();
    }
  }
  if (releaseError) {
    std::rethrow_exception(releaseError);
  }
}

void RuntimeContext::scheduleSharedObjectRelease(long objectId) noexcept {
  if (!isAlive()) {
    return;
  }
  if (isRuntimeThread()) {
    try {
      releaseSharedObject(objectId);
    } catch (...) {
    }
    return;
  }
  if (!jsInvoker_) {
    return;
  }
  jsInvoker_->invokeAsync(
      [weakContext = weak_from_this(), objectId](jsi::Runtime &) {
        auto context = weakContext.lock();
        if (!context || !context->isAlive()) {
          return;
        }
        try {
          context->releaseSharedObject(objectId);
        } catch (...) {
        }
      });
}

jsi::Value RuntimeContext::getSharedObject(long objectId) {
  assertRuntimeThread();
  std::shared_ptr<jsi::WeakObject> weakObject;
  {
    std::scoped_lock lock(mutex_);
    auto iterator = sharedObjects_.find(objectId);
    if (iterator == sharedObjects_.end()) {
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

size_t RuntimeContext::beginObservingSharedObject(long objectId) {
  std::scoped_lock lock(mutex_);
  if (!nativeSharedObjects_.contains(objectId)) {
    return 0;
  }
  return ++sharedObjectObservationCounts_[objectId];
}

size_t RuntimeContext::endObservingSharedObject(long objectId) {
  std::scoped_lock lock(mutex_);
  auto iterator = sharedObjectObservationCounts_.find(objectId);
  if (iterator == sharedObjectObservationCounts_.end() || iterator->second == 0) {
    return 0;
  }
  const auto count = --iterator->second;
  if (count == 0) {
    sharedObjectObservationCounts_.erase(iterator);
  }
  return count;
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

void RuntimeContext::replaceNativeClassesForModule(
    const std::string &moduleName,
    const std::vector<std::pair<std::type_index, std::string>> &classes) {
  std::scoped_lock lock(mutex_);
  auto replacement = nativeClasses_;
  for (auto iterator = replacement.begin();
       iterator != replacement.end();) {
    if (iterator->second.first == moduleName) {
      iterator = replacement.erase(iterator);
    } else {
      ++iterator;
    }
  }
  for (const auto &[nativeType, className] : classes) {
    if (nativeType == std::type_index(typeid(void))) {
      throw CodedError(
          "ERR_INVALID_DEFINITION",
          "Native Expo class '" + moduleName + "." + className + "' has no C++ runtime type.");
    }
    auto value = std::make_pair(moduleName, className);
    auto [iterator, inserted] = replacement.emplace(nativeType, value);
    if (!inserted && iterator->second != value) {
      throw CodedError(
          "ERR_DUPLICATE_CLASS_TYPE",
          "One C++ native type cannot back two unrelated Expo classes.");
    }
  }
  nativeClasses_.swap(replacement);
}

std::pair<std::string, std::string> RuntimeContext::nativeClass(
    std::type_index nativeType) const {
  std::scoped_lock lock(mutex_);
  auto iterator = nativeClasses_.find(nativeType);
  if (iterator == nativeClasses_.end()) {
    throw CodedError(
        "ERR_CLASS_NOT_FOUND",
        "No Expo class is registered for the returned C++ native type.");
  }
  return iterator->second;
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
  while (true) {
    long objectId = 0;
    {
      std::scoped_lock lock(mutex_);
      if (nativeSharedObjects_.empty()) {
        break;
      }
      objectId = nativeSharedObjects_.begin()->first;
    }
    try {
      releaseSharedObject(objectId);
    } catch (...) {
    }
  }
  {
    std::scoped_lock lock(mutex_);
    sharedObjects_.clear();
    nativeSharedObjects_.clear();
    nativeSharedObjectIds_.clear();
    nativeSharedObjectClasses_.clear();
    releasingSharedObjectIds_.clear();
    sharedObjectObservationCounts_.clear();
    modules_.clear();
    classes_.clear();
    nativeClasses_.clear();
    viewProps_.clear();
  }
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

}  // namespace expo::harmony
