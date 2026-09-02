#include "EventEmitterArgumentValidator.h"

namespace expo::EventEmitter {

const char *hostFunctionName(HostFunction function) noexcept {
  switch (function) {
    case HostFunction::AddListener:
      return "addListener";
    case HostFunction::RemoveListener:
      return "removeListener";
    case HostFunction::RemoveAllListeners:
      return "removeAllListeners";
    case HostFunction::Emit:
      return "emit";
    case HostFunction::ListenerCount:
      return "listenerCount";
    case HostFunction::RemoveSubscription:
      return "removeSubscription";
  }
  return "unknown";
}

const char *validateArguments(
    HostFunction function,
    size_t count,
    ArgumentShape shape) noexcept {
  switch (function) {
    case HostFunction::AddListener:
    case HostFunction::RemoveListener:
      if (count < 2) {
        return "expected an event name and listener";
      }
      if (!shape.firstIsString) {
        return "expected the event name to be a string";
      }
      if (!shape.secondIsFunction) {
        return "expected the listener to be a function";
      }
      return nullptr;
    case HostFunction::RemoveAllListeners:
    case HostFunction::Emit:
    case HostFunction::ListenerCount:
      if (count < 1) {
        return "expected an event name";
      }
      return shape.firstIsString
          ? nullptr
          : "expected the event name to be a string";
    case HostFunction::RemoveSubscription:
      if (count < 1) {
        return "expected a subscription";
      }
      return shape.firstIsObject
          ? nullptr
          : "expected the subscription to be an object";
  }
  return "received invalid arguments";
}

}  // namespace expo::EventEmitter
