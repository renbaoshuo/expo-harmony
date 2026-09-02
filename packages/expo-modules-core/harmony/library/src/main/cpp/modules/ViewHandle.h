#pragma once

#include <cstdint>
#include <string>
#include <utility>
#include <vector>

namespace expo::harmony {

class Invocation;

/** Core-internal mounted-view route passed to the generic ArkTS adapter. */
class ViewHandle final {
public:
  ViewHandle(int64_t tag, std::string componentName, int64_t propsRevision)
      : tag_(tag),
        componentName_(std::move(componentName)),
        propsRevision_(propsRevision) {}

  int64_t tag() const noexcept {
    return tag_;
  }

  const std::string &componentName() const noexcept {
    return componentName_;
  }

  int64_t propsRevision() const noexcept {
    return propsRevision_;
  }

private:
  int64_t tag_;
  std::string componentName_;
  int64_t propsRevision_;
};

ViewHandle requireViewHandle(
    Invocation &invocation,
    const std::vector<std::string> &componentNames);

}  // namespace expo::harmony
