/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#ifdef __APPLE__
#include <ExpoModulesJSI/JSIUtils.h>
#else
#include "JSIUtils.h"
#endif

#include "EventEmitter.h"
#include "EventEmitterArgumentValidator.h"
#include "LazyObject.h"
#include "JSI/CodedError.h"

#include <cxxreact/ErrorUtils.h>

#include <optional>

namespace expo::EventEmitter {

namespace {

void validateHostArguments(
    jsi::Runtime &runtime,
    HostFunction function,
    size_t count,
    ArgumentShape shape) {
  const auto *expectation = validateArguments(function, count, shape);
  if (!expectation) {
    return;
  }

  throw expo::common::CodedJSError(
      runtime,
      "ERR_INVALID_ARGUMENT",
      std::string("EventEmitter.") + hostFunctionName(function) + " " + expectation + ".");
}

jsi::Object requireEmitterObject(
    jsi::Runtime &runtime,
    const jsi::Value &thisValue,
    const char *functionName) {
  if (!thisValue.isObject()) {
    throw expo::common::CodedJSError(
        runtime,
        "ERR_INVALID_ARGUMENT",
        std::string("EventEmitter.") + functionName + " must be called on an object.");
  }

  return thisValue.getObject(runtime);
}

}  // namespace

#pragma mark - Listeners

void Listeners::add(jsi::Runtime &runtime, const std::string& eventName, const jsi::Function &listener) noexcept {
  listenersMap[eventName].emplace_back(runtime, listener);
}

void Listeners::remove(jsi::Runtime &runtime, const std::string& eventName, const jsi::Function &listener) noexcept {
  auto event = listenersMap.find(eventName);
  if (event == listenersMap.end()) {
    return;
  }

  jsi::Value listenerValue(runtime, listener);

  event->second.remove_if([&](const jsi::Value &item) {
    return jsi::Value::strictEquals(runtime, listenerValue, item);
  });
  if (event->second.empty()) {
    listenersMap.erase(event);
  }
}

void Listeners::removeAll(const std::string& eventName) noexcept {
  listenersMap.erase(eventName);
}

void Listeners::clear() noexcept {
  listenersMap.clear();
}

Listeners::ListenersMap Listeners::takeAll() noexcept {
  ListenersMap listeners;
  listeners.swap(listenersMap);
  return listeners;
}

size_t Listeners::listenersCount(const std::string& eventName) noexcept {
  if (!listenersMap.contains(eventName)) {
    return 0;
  }
  return listenersMap[eventName].size();
}

void Listeners::call(jsi::Runtime &runtime, const std::string& eventName, const jsi::Object &thisObject, const jsi::Value *args, size_t count) noexcept {
  if (!listenersMap.contains(eventName)) {
    return;
  }

  ListenersList &listeners = listenersMap[eventName];
  const auto size = listeners.size();

  if (size == 0) {
    return;
  }
  if (size == 1) {
    try {
      listeners
        .front()
        .asObject(runtime)
        .asFunction(runtime)
        .callWithThis(runtime, thisObject, args, count);
    } catch (jsi::JSError& error) {
      facebook::react::handleJSError(runtime, error, false);
    }
    return;
  }

  // Snapshot the listeners because callbacks can mutate the original list.
  std::vector<jsi::Function> snapshot;
  snapshot.reserve(size);
  for (const jsi::Value &listener : listeners) {
    snapshot.push_back(listener.asObject(runtime).asFunction(runtime));
  }

  for (const jsi::Function &listener : snapshot) {
    try {
      listener.callWithThis(runtime, thisObject, args, count);
    } catch (jsi::JSError& error) {
      facebook::react::handleJSError(runtime, error, false);
    }
  }
}

#pragma mark - NativeState

NativeState::NativeState() : jsi::NativeState() {}

NativeState::~NativeState() {
  listeners.clear();
}

NativeState::Shared NativeState::get(jsi::Runtime &runtime, const jsi::Object &object, bool createIfMissing) {
  if (object.hasNativeState<NativeState>(runtime)) {
    return object.getNativeState<NativeState>(runtime);
  }
  if (createIfMissing) {
    NativeState::Shared state = std::make_shared<NativeState>();
    object.setNativeState(runtime, state);
    return state;
  }

  return nullptr;
}

void NativeState::closeListenerAdmission() noexcept {
  acceptsListeners_ = false;
}

bool NativeState::beginDrainingListeners() noexcept {
  closeListenerAdmission();
  if (listenersDrained_) {
    return false;
  }
  listenersDrained_ = true;
  return true;
}

bool NativeState::acceptsListeners() const noexcept {
  return acceptsListeners_;
}

void closeListenerAdmission(
    jsi::Runtime &runtime,
    const jsi::Object &emitter) noexcept {
  try {
    if (auto state = NativeState::get(runtime, emitter, false)) {
      state->closeListenerAdmission();
    }
  } catch (...) {
  }
}

#pragma mark - Utils

void callObservingFunction(jsi::Runtime &runtime, const jsi::Object &object, const char* functionName, const std::string& eventName) {
  jsi::Value fnValue = object.getProperty(runtime, functionName);

  if (!fnValue.isObject()) {
    return;
  }

  fnValue
    .getObject(runtime)
    .asFunction(runtime)
    .callWithThis(runtime, object, {
      jsi::Value(runtime, jsi::String::createFromUtf8(runtime, eventName))
    });
}

namespace {

void callStopObservingFunctions(
    jsi::Runtime &runtime,
    const jsi::Object &emitter,
    const std::string &eventName,
    bool callNative,
    bool callJavaScript) {
  if (!callNative) {
    if (callJavaScript) {
      callObservingFunction(runtime, emitter, "stopObserving", eventName);
    }
    return;
  }

  const auto finishJavaScript = [&]() noexcept {
    if (!callJavaScript) {
      return;
    }
    try {
      callObservingFunction(runtime, emitter, "stopObserving", eventName);
    } catch (...) {
    }
  };

  try {
    callObservingFunction(
        runtime, emitter, "__expo_onStopListeningToEvent", eventName);
  } catch (const expo::common::CodedError &error) {
    finishJavaScript();
    throw expo::common::CodedJSError(runtime, error);
  } catch (const jsi::JSError &error) {
    finishJavaScript();
    throw jsi::JSError(error);
  } catch (const std::exception &error) {
    finishJavaScript();
    throw std::runtime_error(error.what());
  } catch (...) {
    finishJavaScript();
    throw std::runtime_error(
        "EventEmitter failed to stop observing '" + eventName + "'.");
  }

  if (callJavaScript) {
    callObservingFunction(runtime, emitter, "stopObserving", eventName);
  }
}

}  // namespace

void addListener(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const jsi::Function &listener) {
  if (NativeState::Shared state = NativeState::get(runtime, emitter, true)) {
    if (!state->acceptsListeners()) {
      throw expo::common::CodedJSError(
          runtime,
          "ERR_EVENT_EMITTER_RELEASED",
          "Cannot add a listener while its EventEmitter is being released.");
    }

    state->listeners.add(runtime, eventName, listener);

    if (state->listeners.listenersCount(eventName) == 1) {
      try {
        callObservingFunction(
            runtime, emitter, "__expo_onStartListeningToEvent", eventName);
        // A native start hook may synchronously remove or release the emitter.
        if (state->acceptsListeners() &&
            state->listeners.listenersCount(eventName) > 0) {
          callObservingFunction(runtime, emitter, "startObserving", eventName);
        }
      } catch (const expo::common::CodedError &error) {
        throw expo::common::CodedJSError(runtime, error);
      }
    }
  }
}

void removeListener(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const jsi::Function &listener) {
  if (NativeState::Shared state = NativeState::get(runtime, emitter, false)) {
    size_t listenersCountBefore = state->listeners.listenersCount(eventName);

    state->listeners.remove(runtime, eventName, listener);

    if (listenersCountBefore >= 1 && state->listeners.listenersCount(eventName) == 0) {
      callStopObservingFunctions(runtime, emitter, eventName, true, true);
    }
  }
}

void removeAllListeners(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName) {
  if (NativeState::Shared state = NativeState::get(runtime, emitter, false)) {
    size_t listenersCountBefore = state->listeners.listenersCount(eventName);

    state->listeners.removeAll(eventName);

    if (listenersCountBefore >= 1) {
      callStopObservingFunctions(runtime, emitter, eventName, true, true);
    }
  }
}

std::optional<expo::common::CodedError> drainListeners(
    jsi::Runtime &runtime,
    const jsi::Object &emitter,
    const ListenerDrainCallback &callback) noexcept {
  std::optional<expo::common::CodedError> firstError;

  const auto attempt = [&]<typename Operation>(Operation &&operation) noexcept {
    try {
      operation();
    } catch (...) {
      if (firstError) {
        return;
      }
      try {
        try {
          throw;
        } catch (const expo::common::CodedError &error) {
          firstError.emplace(error);
        } catch (const jsi::JSError &error) {
          firstError.emplace(
              "ERR_EVENT_EMITTER",
              error.getMessage().empty() ? error.what() : error.getMessage());
        } catch (const std::exception &error) {
          firstError.emplace("ERR_EVENT_EMITTER", error.what());
        } catch (...) {
          firstError.emplace("ERR_EVENT_EMITTER", "EventEmitter listener cleanup failed.");
        }
      } catch (...) {
        // Recording a diagnostic must not prevent further cleanup.
      }
    }
  };

  attempt([&] {
    auto state = NativeState::get(runtime, emitter, false);
    if (!state || !state->beginDrainingListeners()) {
      return;
    }

    auto listeners = state->listeners.takeAll();
    for (const auto &entry : listeners) {
      if (entry.second.empty()) {
        continue;
      }
      const auto &eventName = entry.first;

      attempt([&] {
        if (callback) {
          callback(eventName);
        } else {
          callObservingFunction(runtime, emitter, "__expo_onStopListeningToEvent", eventName);
        }
      });
      attempt([&] {
        callObservingFunction(runtime, emitter, "stopObserving", eventName);
      });
    }
  });
  return firstError;
}

void emitEvent(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const jsi::Value *args, size_t count) {
  if (NativeState::Shared state = NativeState::get(runtime, emitter, false)) {
    state->listeners.call(runtime, eventName, emitter, args, count);
  }
}

size_t getListenerCount(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName) {
  if (NativeState::Shared state = NativeState::get(runtime, emitter, false)) {
    return state->listeners.listenersCount(eventName);
  }
  return 0;
}

jsi::Value createEventSubscription(jsi::Runtime &runtime, const std::string &eventName, const jsi::Object &emitter, const jsi::Function &listener) {
  jsi::Object subscription(runtime);
  auto removeName = jsi::PropNameID::forAscii(runtime, "remove", 6);
  auto emitterHandle = std::make_shared<jsi::Value>(runtime, emitter);
  auto listenerHandle = std::make_shared<jsi::Value>(runtime, listener);

  jsi::HostFunctionType remove = [eventName, emitterHandle, listenerHandle](jsi::Runtime &runtime, const jsi::Value &, const jsi::Value *, size_t) -> jsi::Value {
    if (emitterHandle->isUndefined()) {
      return jsi::Value::undefined();
    }

    auto emitter = emitterHandle->getObject(runtime);
    auto listener = listenerHandle->getObject(runtime).getFunction(runtime);

    // Detach the subscription before hooks can throw or re-enter remove().
    *emitterHandle = jsi::Value::undefined();
    *listenerHandle = jsi::Value::undefined();
    removeListener(runtime, emitter, eventName, listener);

    return jsi::Value::undefined();
  };

  subscription.setProperty(
      runtime,
      removeName,
      jsi::Function::createFromHostFunction(runtime, removeName, 0, remove));

  return jsi::Value(runtime, subscription);
}

#pragma mark - Public API

void emitEvent(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const std::vector<jsi::Value> &arguments) {
  emitEvent(runtime, emitter, eventName, arguments.data(), arguments.size());
}

jsi::Function getClass(jsi::Runtime &runtime) {
  return common::getCoreObject(runtime)
    .getPropertyAsFunction(runtime, "EventEmitter");
}

void installClass(jsi::Runtime &runtime) {
  jsi::Function eventEmitterClass = common::createClass(runtime, "EventEmitter", [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    // Preserve compatibility with the legacy emitter shape.
    if (count > 0) {
      if (!args[0].isObject()) {
        throw expo::common::CodedJSError(
            runtime,
            "ERR_INVALID_ARGUMENT",
            "EventEmitter constructor expected its optional argument to be an object.");
      }

      // Keep a temporary object so LazyObject unwrapping works reliably.
      const jsi::Object &tmp = args[0].asObject(runtime);
      const jsi::Object &firstArg = LazyObject::unwrapObjectIfNecessary(runtime, tmp);

      jsi::Function constructor = thisValue.getObject(runtime).getPropertyAsFunction(runtime, "constructor");

      if (firstArg.instanceOf(runtime, constructor)) {
        return jsi::Value(runtime, args[0]);
      }
    }

    return jsi::Value(runtime, thisValue);
  });
  jsi::Object prototype = eventEmitterClass.getPropertyAsObject(runtime, "prototype");

  jsi::HostFunctionType addListenerHost = [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    const bool secondIsFunction =
        count > 1 && args[1].isObject() && args[1].getObject(runtime).isFunction(runtime);
    validateHostArguments(
        runtime,
        HostFunction::AddListener,
        count,
        ArgumentShape{
            .firstIsString = count > 0 && args[0].isString(),
            .secondIsFunction = secondIsFunction,
        });

    auto eventName = args[0].asString(runtime).utf8(runtime);
    auto listener = args[1].asObject(runtime).asFunction(runtime);
    auto thisObject = requireEmitterObject(
        runtime, thisValue, "addListener");

    const jsi::Object &emitter = LazyObject::unwrapObjectIfNecessary(runtime, thisObject);

    addListener(runtime, emitter, eventName, listener);
    return createEventSubscription(runtime, eventName, emitter, listener);
  };

  jsi::HostFunctionType removeListenerHost = [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    const bool secondIsFunction =
        count > 1 && args[1].isObject() && args[1].getObject(runtime).isFunction(runtime);
    validateHostArguments(
        runtime,
        HostFunction::RemoveListener,
        count,
        ArgumentShape{
            .firstIsString = count > 0 && args[0].isString(),
            .secondIsFunction = secondIsFunction,
        });

    auto eventName = args[0].asString(runtime).utf8(runtime);
    auto listener = args[1].asObject(runtime).asFunction(runtime);
    auto thisObject = requireEmitterObject(
        runtime, thisValue, "removeListener");

    const jsi::Object &emitter = LazyObject::unwrapObjectIfNecessary(runtime, thisObject);

    removeListener(runtime, emitter, eventName, listener);
    return jsi::Value::undefined();
  };

  jsi::HostFunctionType removeAllListenersHost = [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    validateHostArguments(
        runtime,
        HostFunction::RemoveAllListeners,
        count,
        ArgumentShape{
            .firstIsString = count > 0 && args[0].isString(),
        });

    auto eventName = args[0].asString(runtime).utf8(runtime);
    auto thisObject = requireEmitterObject(
        runtime, thisValue, "removeAllListeners");

    const jsi::Object &emitter = LazyObject::unwrapObjectIfNecessary(runtime, thisObject);

    removeAllListeners(runtime, emitter, eventName);
    return jsi::Value::undefined();
  };

  jsi::HostFunctionType emit = [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    validateHostArguments(
        runtime,
        HostFunction::Emit,
        count,
        ArgumentShape{
            .firstIsString = count > 0 && args[0].isString(),
        });

    auto eventName = args[0].asString(runtime).utf8(runtime);
    auto thisObject = requireEmitterObject(runtime, thisValue, "emit");

    const jsi::Object &emitter = LazyObject::unwrapObjectIfNecessary(runtime, thisObject);
    const jsi::Value *eventArgs = count > 1 ? &args[1] : nullptr;

    emitEvent(runtime, emitter, eventName, eventArgs, count - 1);
    return jsi::Value::undefined();
  };

  jsi::HostFunctionType listenerCountHost = [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    validateHostArguments(
        runtime,
        HostFunction::ListenerCount,
        count,
        ArgumentShape{
            .firstIsString = count > 0 && args[0].isString(),
        });

    auto eventName = args[0].asString(runtime).utf8(runtime);
    auto thisObject = requireEmitterObject(
        runtime, thisValue, "listenerCount");

    const jsi::Object &emitter = LazyObject::unwrapObjectIfNecessary(runtime, thisObject);

    return jsi::Value((int)getListenerCount(runtime, emitter, eventName));
  };

  // Added for compatibility with the old EventEmitter API.
  jsi::HostFunctionType removeSubscriptionHost = [](jsi::Runtime &runtime, const jsi::Value &thisValue, const jsi::Value *args, size_t count) -> jsi::Value {
    validateHostArguments(
        runtime,
        HostFunction::RemoveSubscription,
        count,
        ArgumentShape{
            .firstIsObject = count > 0 && args[0].isObject(),
        });

    auto subscription = args[0].asObject(runtime);
    auto removeValue = subscription.getProperty(runtime, "remove");
    if (!removeValue.isObject() ||
        !removeValue.getObject(runtime).isFunction(runtime)) {
      throw expo::common::CodedJSError(
          runtime,
          "ERR_INVALID_ARGUMENT",
          "EventEmitter.removeSubscription expected an object with a remove function.");
    }

    removeValue
        .getObject(runtime)
        .asFunction(runtime)
        .callWithThis(runtime, subscription, {});

    return jsi::Value::undefined();
  };

  jsi::PropNameID addListenerProp = jsi::PropNameID::forAscii(runtime, "addListener", 11);
  jsi::PropNameID removeListenerProp = jsi::PropNameID::forAscii(runtime, "removeListener", 14);
  jsi::PropNameID removeAllListenersProp = jsi::PropNameID::forAscii(runtime, "removeAllListeners", 18);
  jsi::PropNameID emitProp = jsi::PropNameID::forAscii(runtime, "emit", 4);
  jsi::PropNameID listenerCountProp = jsi::PropNameID::forAscii(runtime, "listenerCount", 13);
  jsi::PropNameID removeSubscriptionProp = jsi::PropNameID::forAscii(runtime, "removeSubscription", 18);

  prototype.setProperty(runtime, addListenerProp, jsi::Function::createFromHostFunction(runtime, addListenerProp, 2, addListenerHost));
  prototype.setProperty(runtime, removeListenerProp, jsi::Function::createFromHostFunction(runtime, removeListenerProp, 2, removeListenerHost));
  prototype.setProperty(runtime, removeAllListenersProp, jsi::Function::createFromHostFunction(runtime, removeAllListenersProp, 1, removeAllListenersHost));
  prototype.setProperty(runtime, emitProp, jsi::Function::createFromHostFunction(runtime, emitProp, 2, emit));
  prototype.setProperty(runtime, listenerCountProp, jsi::Function::createFromHostFunction(runtime, listenerCountProp, 1, listenerCountHost));
  prototype.setProperty(runtime, removeSubscriptionProp, jsi::Function::createFromHostFunction(runtime, removeSubscriptionProp, 1, removeSubscriptionHost));

  common::getCoreObject(runtime)
    .setProperty(runtime, "EventEmitter", eventEmitterClass);
}

} // namespace expo::EventEmitter
