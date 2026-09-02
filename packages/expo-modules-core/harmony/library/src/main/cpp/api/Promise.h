#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include <jsi/jsi.h>

#include "api/internal/PromiseSettlementState.h"
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
  /** Resolves only when this caller wins the one-shot settlement race. */
  bool tryResolve(ValueFactory valueFactory);
  void resolveUndefined();
  void reject(std::string code, std::string message);
  void reject(
      std::string code,
      std::string message,
      std::shared_ptr<const CodedError> cause);
  void reject(CodedError error);
  std::shared_ptr<const CancellationToken> cancellationToken() const noexcept;
  bool isSettled() const noexcept;
  /** Keeps native invocation leases alive through settlement or invalidation. */
  void retainUntilSettled(std::shared_ptr<void> resource);

private:
  friend class RuntimeContext;
  using SettlementBody = std::function<void(
      facebook::jsi::Runtime &,
      facebook::jsi::Function &resolve,
      facebook::jsi::Function &reject)>;
  Promise(
      std::shared_ptr<RuntimeContext> context,
      facebook::jsi::Function resolve,
      facebook::jsi::Function reject);
  bool settle(SettlementBody body);
  void requestCancellation() noexcept;
  void cancelAndReject() noexcept;
  void invalidate() noexcept;
  std::vector<std::shared_ptr<void>> takeRetainedResources() noexcept;
  void releaseRetainedResources() noexcept;

  std::weak_ptr<RuntimeContext> context_;
  std::unique_ptr<facebook::jsi::Function> resolve_;
  std::unique_ptr<facebook::jsi::Function> reject_;
  std::shared_ptr<CancellationToken> cancellationToken_;
  PromiseSettlementState settlementState_;
  std::mutex retainedResourcesMutex_;
  std::vector<std::shared_ptr<void>> retainedResources_;
};

}  // namespace expo::harmony
