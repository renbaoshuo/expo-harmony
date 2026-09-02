#include "CodedError.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

namespace {

constexpr size_t kMaximumErrorCauseDepth = 4;

jsi::Object makeCodedErrorObject(
    jsi::Runtime &runtime,
    const CodedError &error,
    size_t depth) {
  jsi::Object result(runtime);
  auto codedError = runtime.global().getProperty(
      runtime, "ExpoModulesCore_CodedError");
  if (codedError.isObject() && codedError.getObject(runtime).isFunction(runtime)) {
    result = codedError.getObject(runtime)
                 .getFunction(runtime)
                 .callAsConstructor(
                     runtime,
                     jsi::String::createFromUtf8(runtime, error.code()),
                     jsi::String::createFromUtf8(runtime, error.what()))
                 .getObject(runtime);
  } else {
    result = runtime.global()
                 .getPropertyAsFunction(runtime, "Error")
                 .callAsConstructor(
                     runtime,
                     jsi::String::createFromUtf8(runtime, error.what()))
                 .getObject(runtime);
    result.setProperty(
        runtime,
        "code",
        jsi::String::createFromUtf8(runtime, error.code()));
  }

  if (error.path()) {
    result.setProperty(
        runtime,
        "path",
        jsi::String::createFromUtf8(runtime, *error.path()));
  }
  if (error.origin()) {
    const auto &origin = *error.origin();
    jsi::Object originObject(runtime);
    originObject.setProperty(
        runtime,
        "moduleName",
        jsi::String::createFromUtf8(runtime, origin.moduleName));
    originObject.setProperty(
        runtime,
        "functionName",
        jsi::String::createFromUtf8(runtime, origin.functionName));
    if (!origin.className.empty()) {
      originObject.setProperty(
          runtime,
          "className",
          jsi::String::createFromUtf8(runtime, origin.className));
      result.setProperty(
          runtime,
          "className",
          jsi::String::createFromUtf8(runtime, origin.className));
    }
    result.setProperty(runtime, "origin", std::move(originObject));
    result.setProperty(
        runtime,
        "moduleName",
        jsi::String::createFromUtf8(runtime, origin.moduleName));
    result.setProperty(
        runtime,
        "functionName",
        jsi::String::createFromUtf8(runtime, origin.functionName));
  }
  if (!error.nativeStack().empty()) {
    jsi::Array nativeStack(runtime, error.nativeStack().size());
    for (size_t index = 0; index < error.nativeStack().size(); ++index) {
      nativeStack.setValueAtIndex(
          runtime,
          index,
          jsi::String::createFromUtf8(runtime, error.nativeStack()[index]));
    }
    result.setProperty(runtime, "nativeStack", std::move(nativeStack));
  }
  if (error.cause() && depth < kMaximumErrorCauseDepth) {
    result.setProperty(
        runtime,
        "cause",
        makeCodedErrorObject(runtime, *error.cause(), depth + 1));
  }
  return result;
}

}  // namespace

CodedJSError::CodedJSError(
    jsi::Runtime &runtime,
    const CodedError &error)
    : jsi::JSError(
          runtime,
          [&runtime, &error]() -> jsi::Value {
            return jsi::Value(makeCodedErrorObject(runtime, error, 0));
          }()) {}

CodedJSError::CodedJSError(
    jsi::Runtime &runtime,
    std::string code,
    std::string message)
    : CodedJSError(
          runtime,
          CodedError(std::move(code), std::move(message))) {}

}  // namespace expo::harmony
