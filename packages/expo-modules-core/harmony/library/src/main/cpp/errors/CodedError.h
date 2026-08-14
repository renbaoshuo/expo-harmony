#pragma once

#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

#include <jsi/jsi.h>

namespace expo::harmony {

struct ExceptionOrigin final {
  std::string moduleName;
  std::string functionName;
};

class CodedError final : public std::runtime_error {
public:
  CodedError(std::string code, std::string message)
      : std::runtime_error(std::move(message)), code_(std::move(code)) {}

  CodedError(
      std::string code,
      std::string message,
      ExceptionOrigin origin,
      std::shared_ptr<const CodedError> cause = nullptr,
      std::vector<std::string> nativeStack = {})
      : std::runtime_error(std::move(message)),
        code_(std::move(code)),
        origin_(std::move(origin)),
        cause_(std::move(cause)),
        nativeStack_(std::move(nativeStack)) {}

  const std::string &code() const noexcept {
    return code_;
  }

  const std::optional<ExceptionOrigin> &origin() const noexcept {
    return origin_;
  }

  const std::shared_ptr<const CodedError> &cause() const noexcept {
    return cause_;
  }

  const std::vector<std::string> &nativeStack() const noexcept {
    return nativeStack_;
  }

  CodedError withOrigin(ExceptionOrigin origin, std::string nativeFrame = {}) const;
  CodedError wrapping(
      std::string code,
      std::string message,
      ExceptionOrigin origin = {}) const;

private:
  std::string code_;
  std::optional<ExceptionOrigin> origin_;
  std::shared_ptr<const CodedError> cause_;
  std::vector<std::string> nativeStack_;
};

facebook::jsi::JSError makeJSError(
    facebook::jsi::Runtime &runtime,
    const CodedError &error);

facebook::jsi::JSError makeJSError(
    facebook::jsi::Runtime &runtime,
    const std::string &code,
    const std::string &message);

}  // namespace expo::harmony
