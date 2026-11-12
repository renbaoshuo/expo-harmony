/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

#include <RNOH/PackageProvider.h>

#include <memory>
#include <vector>

#include "RNOHPackagesFactory.h"
#include "rnoh_codegen/generated/RNOHGeneratedPackage.h"

std::vector<std::shared_ptr<rnoh::Package>> rnoh::PackageProvider::getPackages(rnoh::Package::Context context) {
  auto packages = createRNOHPackages(context);
  packages.push_back(std::make_shared<rnoh::RNOHGeneratedPackage>(context));
  return packages;
}
