#include "modules/ViewHandle.h"

#include <algorithm>
#include <cmath>

#include "errors/CodedError.h"
#include "modules/internal/ModuleDefinition.h"
#include "runtime/RuntimeContext.h"

namespace expo::harmony {

namespace {

int64_t requireViewTag(Invocation &invocation) {
  constexpr auto kMaxSafeInteger = 9007199254740991.0;
  auto &runtime = invocation.runtime();
  const auto &thisValue = invocation.thisValue();
  if (!thisValue.isObject()) {
    throw CodedError(
        "ERR_VIEW_NOT_FOUND",
        invocation.path() + " must be called with an Expo view ref as this.");
  }
  auto object = thisValue.getObject(runtime);
  auto nativeTag = object.getProperty(runtime, "nativeTag");
  if (!nativeTag.isNumber() || !std::isfinite(nativeTag.getNumber()) || std::trunc(nativeTag.getNumber()) != nativeTag.getNumber() || nativeTag.getNumber() <= 0 || nativeTag.getNumber() > kMaxSafeInteger) {
    throw CodedError(
        "ERR_VIEW_NOT_FOUND",
        invocation.path() + " cannot resolve the mounted Expo view tag.");
  }
  return static_cast<int64_t>(nativeTag.getNumber());
}

std::string requireViewComponentName(Invocation &invocation) {
  auto &runtime = invocation.runtime();
  const auto object = invocation.thisValue().getObject(runtime);
  const auto componentName = object.getProperty(runtime, "nativeComponentName");
  if (!componentName.isString()) {
    throw CodedError(
        "ERR_VIEW_NOT_FOUND",
        invocation.path() + " cannot resolve the Expo view component route.");
  }
  return componentName.getString(runtime).utf8(runtime);
}

int64_t requireViewPropsRevision(Invocation &invocation) {
  auto &runtime = invocation.runtime();
  const auto object = invocation.thisValue().getObject(runtime);
  const auto revision = object.getProperty(runtime, "nativePropsRevision");
  constexpr auto kMaxSafeInteger = 9007199254740991.0;
  if (!revision.isNumber() || !std::isfinite(revision.getNumber()) || std::trunc(revision.getNumber()) != revision.getNumber() || revision.getNumber() <= 0 || revision.getNumber() > kMaxSafeInteger) {
    throw CodedError(
        "ERR_VIEW_NOT_FOUND",
        invocation.path() + " cannot resolve the committed Expo view props revision.");
  }
  return static_cast<int64_t>(revision.getNumber());
}

}  // namespace

ViewHandle requireViewHandle(
    Invocation &invocation,
    const std::vector<std::string> &componentNames) {
  const auto tag = requireViewTag(invocation);
  auto componentName = requireViewComponentName(invocation);
  const auto propsRevision = requireViewPropsRevision(invocation);
  if (std::find(
          componentNames.begin(),
          componentNames.end(),
          componentName)
      == componentNames.end()) {
    throw CodedError(
        "ERR_VIEW_COMPONENT_MISMATCH",
        "Expo view tag " + std::to_string(tag) + " uses route '" + componentName + "', which is not a route for " + invocation.path() + ".");
  }

  auto context = invocation.sharedContext();
  const auto mountedComponentName = context->mountedViewComponentNameIfPresent(tag);
  if (mountedComponentName && *mountedComponentName != componentName) {
    throw CodedError(
        "ERR_VIEW_COMPONENT_MISMATCH",
        "Expo view tag " + std::to_string(tag) + " belongs to '" + *mountedComponentName + "', not '" + componentName + "'.");
  }

  // The ArkTS adapter registry is authoritative before native mount state arrives.
  return ViewHandle(tag, std::move(componentName), propsRevision);
}

}  // namespace expo::harmony
