/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#pragma once

#include <memory>
#include <unordered_map>

namespace expo::harmony {

// Protected by RuntimeContext's mutex. A collected wrapper can be replaced
// before its queued finalizer executes, so objectId alone is not sufficient.
class SharedObjectWrapperState final {
public:
  struct Identity final {};
  using Token = std::shared_ptr<const Identity>;

  Token replace(long objectId) {
    auto token = std::make_shared<const Identity>();
    wrappers_[objectId] = token;
    return token;
  }

  bool isCurrent(long objectId, const Token &token) const {
    const auto found = wrappers_.find(objectId);
    return found != wrappers_.end() && found->second == token;
  }

  void erase(long objectId) { wrappers_.erase(objectId); }
  void clear() { wrappers_.clear(); }

private:
  std::unordered_map<long, Token> wrappers_;
};

}  // namespace expo::harmony
