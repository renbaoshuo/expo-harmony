#pragma once

#include "api/ModuleDefinition.h"

namespace expo::harmony {

class ExpoModule {
public:
  virtual ~ExpoModule() = default;
  virtual ModuleDefinition definition() = 0;
};

}  // namespace expo::harmony
