#pragma once

#include <cstddef>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace expo::harmony {

/** Runtime-owned event observation state for SharedObjects. */
class SharedObjectObservationState final {
public:
  using StopHook =
      std::function<void(const std::string &eventName, size_t remainingEventCount)>;

  struct PendingStop final {
    std::string eventName;
    size_t remainingEventCount{0};
    StopHook hook;
  };

  /** Returns the object's observed-event count, or zero for a duplicate/invalid transition. */
  size_t begin(long objectId, std::string eventName, StopHook hook);

  /** Detaches one event before returning its stop transition. */
  std::optional<PendingStop> take(long objectId, const std::string &eventName);

  /** Detaches every event for an object before returning their stop transitions. */
  std::vector<PendingStop> drain(long objectId);

  size_t count(long objectId) const noexcept;
  bool contains(long objectId, const std::string &eventName) const noexcept;
  bool empty() const noexcept;
  void clear() noexcept;

private:
  using ObjectObservations = std::unordered_map<std::string, StopHook>;
  std::unordered_map<long, ObjectObservations> observations_;
};

}  // namespace expo::harmony
