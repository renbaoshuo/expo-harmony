#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <string>

#include <jsi/jsi.h>

#include "errors/CodedError.h"

namespace expo::harmony {

class RuntimeContext;

class CancellationToken final {
public:
  bool isCancellationRequested() const noexcept {
    return cancelled_.load(std::memory_order_acquire);
  }

  void throwIfCancellationRequested() const;

private:
  friend class Promise;

  void cancel() noexcept {
    cancelled_.store(true, std::memory_order_release);
  }

  std::atomic_bool cancelled_{false};
};

class Promise final : public std::enable_shared_from_this<Promise> {
public:
  using Setup = std::function<void(const std::shared_ptr<Promise> &)>;
  using ValueFactory = std::function<facebook::jsi::Value(facebook::jsi::Runtime &)>;

  static facebook::jsi::Value create(
      facebook::jsi::Runtime &runtime,
      const std::shared_ptr<RuntimeContext> &context,
      Setup setup);
  static facebook::jsi::Value rejected(
      facebook::jsi::Runtime &runtime,
      const std::shared_ptr<RuntimeContext> &context,
      std::string code,
      std::string message);

  void resolve(ValueFactory valueFactory);
  void resolveUndefined();
  void reject(std::string code, std::string message);
  void reject(
      std::string code,
      std::string message,
      std::shared_ptr<const CodedError> cause);
  void reject(CodedError error);
  std::shared_ptr<const CancellationToken> cancellationToken() const noexcept;
  bool isSettled() const noexcept;

private:
  friend class RuntimeContext;
  Promise(
      std::shared_ptr<RuntimeContext> context,
      facebook::jsi::Function resolve,
      facebook::jsi::Function reject);
  void settle(std::function<void(facebook::jsi::Runtime &)> body);
  void invalidate() noexcept;

  std::weak_ptr<RuntimeContext> context_;
  std::unique_ptr<facebook::jsi::Function> resolve_;
  std::unique_ptr<facebook::jsi::Function> reject_;
  std::shared_ptr<CancellationToken> cancellationToken_;
  std::atomic_bool settled_{false};
};

}  // namespace expo::harmony
