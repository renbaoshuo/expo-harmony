package expo.modules.showcase

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ExpoModuleShowcaseConsumerModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoModuleShowcaseConsumer")
    Function("readSharedCounter") { counter: ShowcaseSharedCounter -> counter.value }
    Function("forwardSharedCounter") { counter: ShowcaseSharedCounter -> counter }
    Function("readSharedTextRef") { ref: ShowcaseTextRef -> ref.ref }
    Function("forwardSharedTextRef") { ref: ShowcaseTextRef -> ref }
  }
}
