#pragma once

#include <cstddef>
#include <unordered_map>
#include <unordered_set>

namespace expo::harmony {

enum class SharedObjectReleaseReadiness {
  AlreadyRequested,
  Ready,
  Deferred,
};

/** Tracks in-flight native bodies separately from JavaScript owners. */
class SharedObjectInvocationState final {
public:
  bool acquire(long objectId);

  /** Returns true when this was the final active lease of a requested release. */
  bool release(long objectId) noexcept;

  SharedObjectReleaseReadiness requestRelease(long objectId);
  bool isReleaseRequested(long objectId) const noexcept;
  bool isReadyToFinalize(long objectId) const noexcept;
  /** Claims the ready finalization transition; re-entrant claims are no-ops. */
  bool beginFinalization(long objectId) noexcept;
  bool isFinalizing(long objectId) const noexcept;
  bool hasFinalizing() const noexcept;
  size_t activeCount(long objectId) const noexcept;
  void completeRelease(long objectId) noexcept;
  void clear() noexcept;

private:
  std::unordered_map<long, size_t> activeCounts_;
  std::unordered_set<long> releaseRequested_;
  std::unordered_set<long> finalizing_;
};

}  // namespace expo::harmony
