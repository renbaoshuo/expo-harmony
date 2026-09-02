#pragma once

#include <cstddef>

namespace expo::EventEmitter {

enum class HostFunction {
  AddListener,
  RemoveListener,
  RemoveAllListeners,
  Emit,
  ListenerCount,
  RemoveSubscription,
};

struct ArgumentShape final {
  bool firstIsString{false};
  bool firstIsObject{false};
  bool secondIsFunction{false};
};

const char *hostFunctionName(HostFunction function) noexcept;

/** Returns null for a valid shape and a stable expectation string otherwise. */
const char *validateArguments(
    HostFunction function,
    size_t count,
    ArgumentShape shape) noexcept;

}  // namespace expo::EventEmitter
