#include "SharedObjectObservationState.h"

#include <algorithm>
#include <utility>

namespace expo::harmony {

size_t SharedObjectObservationState::begin(
    long objectId,
    std::string eventName,
    StopHook hook) {
  if (objectId <= 0 || !hook) {
    return 0;
  }
  auto &events = observations_[objectId];
  if (!events.emplace(std::move(eventName), std::move(hook)).second) {
    return 0;
  }
  return events.size();
}

std::optional<SharedObjectObservationState::PendingStop>
SharedObjectObservationState::take(
    long objectId,
    const std::string &eventName) {
  auto object = observations_.find(objectId);
  if (object == observations_.end()) {
    return std::nullopt;
  }
  auto event = object->second.find(eventName);
  if (event == object->second.end()) {
    return std::nullopt;
  }
  PendingStop pending{
      .eventName = event->first,
      .remainingEventCount = object->second.size() - 1,
      .hook = std::move(event->second),
  };
  object->second.erase(event);
  if (object->second.empty()) {
    observations_.erase(object);
  }
  return pending;
}

std::vector<SharedObjectObservationState::PendingStop>
SharedObjectObservationState::drain(long objectId) {
  auto object = observations_.find(objectId);
  if (object == observations_.end()) {
    return {};
  }

  // Detach first so release/stop hooks may safely re-enter observation APIs.
  ObjectObservations events;
  events.swap(object->second);
  observations_.erase(object);

  std::vector<PendingStop> pending;
  pending.reserve(events.size());
  for (auto &[eventName, hook] : events) {
    pending.push_back(PendingStop{
        .eventName = std::move(eventName),
        .hook = std::move(hook),
    });
  }
  std::sort(
      pending.begin(),
      pending.end(),
      [](const PendingStop &left, const PendingStop &right) {
        return left.eventName < right.eventName;
      });
  for (size_t index = 0; index < pending.size(); ++index) {
    pending[index].remainingEventCount = pending.size() - index - 1;
  }
  return pending;
}

size_t SharedObjectObservationState::count(long objectId) const noexcept {
  auto object = observations_.find(objectId);
  return object == observations_.end() ? 0 : object->second.size();
}

bool SharedObjectObservationState::contains(
    long objectId,
    const std::string &eventName) const noexcept {
  auto object = observations_.find(objectId);
  return object != observations_.end() && object->second.contains(eventName);
}

bool SharedObjectObservationState::empty() const noexcept {
  return observations_.empty();
}

void SharedObjectObservationState::clear() noexcept {
  observations_.clear();
}

}  // namespace expo::harmony
