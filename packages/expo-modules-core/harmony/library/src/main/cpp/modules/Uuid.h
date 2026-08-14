#pragma once

#include <string>

namespace expo::harmony {

std::string uuidV4();
std::string uuidV5(const std::string &name, const std::string &nameSpace);

}  // namespace expo::harmony
