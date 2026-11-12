/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <atomic>
#include <functional>

namespace expo::SharedObject {

/** One-shot release token shared by explicit release and the JSI finalizer. */
class SharedObjectReleaseState final {
public:
  using Releaser = std::function<void(long)>;

  SharedObjectReleaseState(long objectId, Releaser releaser);
  ~SharedObjectReleaseState() noexcept;

  SharedObjectReleaseState(const SharedObjectReleaseState &) = delete;
  SharedObjectReleaseState &operator=(const SharedObjectReleaseState &) = delete;

  bool release() noexcept;
  bool isReleased() const noexcept;

private:
  long objectId_;
  Releaser releaser_;
  std::atomic_bool released_{false};
};

}  // namespace expo::SharedObject
