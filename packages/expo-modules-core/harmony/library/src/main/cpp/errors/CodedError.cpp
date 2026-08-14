#include "CodedError.h"

namespace jsi = facebook::jsi;

namespace expo::harmony {

CodedError CodedError::withOrigin(
    ExceptionOrigin origin,
    std::string nativeFrame) const {
  auto stack = nativeStack_;
  if (!nativeFrame.empty()) {
    stack.insert(stack.begin(), std::move(nativeFrame));
  }
  return CodedError(code_, what(), std::move(origin), cause_, std::move(stack));
}

CodedError CodedError::wrapping(
    std::string code,
    std::string message,
    ExceptionOrigin origin) const {
  std::vector<std::string> stack;
  if (!origin.functionName.empty()) {
    stack.push_back(origin.functionName);
  }
  message += "\n→ Caused by: ";
  message += what();
  return CodedError(
      std::move(code),
      std::move(message),
      std::move(origin),
      std::make_shared<CodedError>(*this),
      std::move(stack));
}

namespace {

jsi::Object makeErrorObject(jsi::Runtime &runtime, const CodedError &error) {
  jsi::Object result(runtime);
  auto codedError = runtime.global().getProperty(runtime, "ExpoModulesCore_CodedError");
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
                     runtime, jsi::String::createFromUtf8(runtime, error.what()))
                 .getObject(runtime);
    result.setProperty(
        runtime, "code", jsi::String::createFromUtf8(runtime, error.code()));
  }
  // ExpoModulesCore_CodedError's public JavaScript contract contains only
  // `code` and `message`. Keep origin, native stack and causes on the native
  // exception for diagnostics, but do not add Harmony-only JS properties.
  return result;
}

}  // namespace

jsi::JSError makeJSError(jsi::Runtime &runtime, const CodedError &error) {
  return jsi::JSError(runtime, makeErrorObject(runtime, error));
}

jsi::JSError makeJSError(
    jsi::Runtime &runtime,
    const std::string &code,
    const std::string &message) {
  return makeJSError(runtime, CodedError(std::move(code), std::move(message)));
}

}  // namespace expo::harmony
