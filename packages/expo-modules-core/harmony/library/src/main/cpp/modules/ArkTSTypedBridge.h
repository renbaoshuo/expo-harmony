#pragma once

#include <cstddef>
#include <memory>
#include <string>

#include <jsi/jsi.h>

#include <RNOH/ArkTSTurboModule.h>

namespace expo::harmony {

// Private JSI <-> NAPI transport for values outside folly::dynamic.
class ArkTSTypedBridge final {
public:
  explicit ArkTSTypedBridge(const rnoh::ArkTSTurboModule::Context &context);
  ~ArkTSTypedBridge() noexcept;

  ArkTSTypedBridge(const ArkTSTypedBridge &) = delete;
  ArkTSTypedBridge &operator=(const ArkTSTypedBridge &) = delete;

  facebook::jsi::Value call(
      facebook::jsi::Runtime &runtime,
      const std::string &methodName,
      const facebook::jsi::Value *arguments,
      size_t argumentCount);
  facebook::jsi::Value callAsync(
      facebook::jsi::Runtime &runtime,
      const std::string &methodName,
      const facebook::jsi::Value *arguments,
      size_t argumentCount);

private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace expo::harmony
