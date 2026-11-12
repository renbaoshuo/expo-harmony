/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#ifdef __cplusplus

#include <functional>
#include <list>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>
#include <jsi/jsi.h>

#include "JSI/CodedError.h"

namespace jsi = facebook::jsi;

namespace expo::EventEmitter {

using ListenerDrainCallback = std::function<void(const std::string &eventName)>;

class Listeners {
private:
  friend class NativeState;
  friend void addListener(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const jsi::Function &listener);
  friend void removeListener(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const jsi::Function &listener);
  friend void removeAllListeners(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName);
  friend void emitEvent(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const jsi::Value *args, size_t count);
  friend size_t getListenerCount(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName);
  friend std::optional<expo::common::CodedError> drainListeners(
      jsi::Runtime &runtime,
      const jsi::Object &emitter,
      const ListenerDrainCallback &callback) noexcept;

  using ListenersList = std::list<jsi::Value>;
  using ListenersMap = std::unordered_map<std::string, ListenersList>;

  ListenersMap listenersMap;

  void add(jsi::Runtime &runtime, const std::string& eventName, const jsi::Function &listener) noexcept;
  void remove(jsi::Runtime &runtime, const std::string& eventName, const jsi::Function &listener) noexcept;
  void removeAll(const std::string& eventName) noexcept;
  void clear() noexcept;

  /** Detaches all listeners before cleanup hooks are invoked. */
  ListenersMap takeAll() noexcept;

  size_t listenersCount(const std::string& eventName) noexcept;
  void call(jsi::Runtime &runtime, const std::string& eventName, const jsi::Object &thisObject, const jsi::Value *args, size_t count) noexcept;
};

class JSI_EXPORT NativeState : public jsi::NativeState {
public:
  using Shared = std::shared_ptr<NativeState>;

  NativeState();
  ~NativeState() override;

  Listeners listeners;

  /**
   Gets event emitter's native state from the given object.
   If `createIfMissing` is set to `true`, the state will be automatically created.
   */
  static Shared get(jsi::Runtime &runtime, const jsi::Object &object, bool createIfMissing = false);

  /** Prevents re-entrant cleanup hooks from attaching orphan listeners. */
  void closeListenerAdmission() noexcept;
  bool beginDrainingListeners() noexcept;
  bool acceptsListeners() const noexcept;

private:
  bool acceptsListeners_{true};
  bool listenersDrained_{false};
};

/** Closes addListener admission without detaching live listener state. */
void closeListenerAdmission(
    jsi::Runtime &runtime,
    const jsi::Object &emitter) noexcept;

/** Does nothing if the object is not an EventEmitter. */
void emitEvent(jsi::Runtime &runtime, const jsi::Object &emitter, const std::string &eventName, const std::vector<jsi::Value> &arguments);

/**
 Drains every active event before invoking its native and JavaScript stop hooks.
 Listener state is detached first, all hooks are attempted, and the first error
 is returned to the owner so release can finish before reporting it.
 */
std::optional<expo::common::CodedError> drainListeners(
    jsi::Runtime &runtime,
    const jsi::Object &emitter,
    const ListenerDrainCallback &callback) noexcept;

jsi::Function getClass(jsi::Runtime &runtime);
void installClass(jsi::Runtime &runtime);

} // namespace expo::EventEmitter

#endif // __cplusplus
