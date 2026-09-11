#include <RNOH/PackageProvider.h>

#include <package/ExpoModulesCorePackage.h>

namespace rnoh {
using ExpoModulesCorePackage = expo::harmony::ExpoModulesCorePackage;
}

#include <memory>
#include <vector>

#include "RNOHPackagesFactory.h"
#include "rnoh_codegen/generated/RNOHGeneratedPackage.h"

std::vector<std::shared_ptr<rnoh::Package>> rnoh::PackageProvider::getPackages(rnoh::Package::Context context) {
  auto packages = createRNOHPackages(context);
  packages.push_back(std::make_shared<rnoh::RNOHGeneratedPackage>(context));
  return packages;
}
