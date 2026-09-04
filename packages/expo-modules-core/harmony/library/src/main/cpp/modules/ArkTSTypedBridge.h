#pragma once

#include <cstddef>
#include <memory>
#include <string>

#include <jsi/jsi.h>

#include <RNOH/ArkTSTurboModule.h>

namespace expo::harmony {

class RuntimeContext;

// JS-thread-only transaction. ArkTS accesses native snapshots; commit runs only
// after the caller has decoded and validated the logical result.
class SynchronousBinaryWriteBack final {
public:
  explicit SynchronousBinaryWriteBack(facebook::jsi::Runtime &runtime);
  ~SynchronousBinaryWriteBack();
  void add(const facebook::jsi::Value &argument);
  void commit(const RuntimeContext &context);

private:
  friend class ArkTSTypedBridge;
  class Impl;
  std::unique_ptr<Impl> impl_;
};

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
      size_t argumentCount,
      SynchronousBinaryWriteBack *writeBack = nullptr);
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
