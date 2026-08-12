#include "api/View.h"

#include "errors/CodedError.h"
#include "runtime/Protocol.h"
#include "runtime/RuntimeContext.h"

#include <cmath>

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

std::shared_ptr<RuntimeContext> requireContext(
    const std::weak_ptr<RuntimeContext>& weakContext) {
  auto context = weakContext.lock();
  if (!context || !context->isAlive()) {
    throw CodedError(
        "ERR_RUNTIME_DESTROYED",
        "Cannot access an Expo view after its runtime was destroyed.");
  }
  return context;
}

} // namespace

void ViewHandle::dispatchCommand(
    std::string commandName,
    folly::dynamic arguments) const {
  if (!arguments.isArray()) {
    throw CodedError(
        "ERR_INVALID_VIEW_COMMAND",
        "Expo view command arguments must be an array.");
  }
  requireContext(context_)->postPlatformMessage(
      protocol::kViewCommand,
      folly::dynamic::object("tag", tag_)("componentName", componentName_)(
          "commandName", std::move(commandName))(
          "arguments", std::move(arguments)));
}

void ViewHandle::emitEvent(
    std::string eventName,
    folly::dynamic payload) const {
  requireContext(context_)->postPlatformMessage(
      protocol::kViewEventEmit,
      folly::dynamic::object("tag", tag_)("componentName", componentName_)(
          "eventName", std::move(eventName))("payload", std::move(payload)));
}

ViewHandle requireViewHandle(
    Invocation& invocation,
    const std::string& componentName) {
  auto& runtime = invocation.runtime();
  const auto& thisValue = invocation.thisValue();
  if (!thisValue.isObject()) {
    throw CodedError(
        "ERR_VIEW_NOT_FOUND",
        invocation.path() + " must be called with an Expo view ref as this.");
  }
  auto object = thisValue.getObject(runtime);
  auto nativeTag = object.getProperty(runtime, "nativeTag");
  if (!nativeTag.isNumber() || !std::isfinite(nativeTag.getNumber()) ||
      std::trunc(nativeTag.getNumber()) != nativeTag.getNumber()) {
    throw CodedError(
        "ERR_VIEW_NOT_FOUND",
        invocation.path() + " cannot resolve the mounted Expo view tag.");
  }
  return ViewHandle(
      invocation.sharedContext(),
      static_cast<int64_t>(nativeTag.getNumber()),
      componentName);
}

} // namespace expo::harmony
