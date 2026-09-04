package expo.modules.showcase

import expo.modules.kotlin.AppContext
import expo.modules.kotlin.sharedobjects.SharedObject
import expo.modules.kotlin.sharedobjects.SharedRef

class ShowcaseSharedCounter(appContext: AppContext, @Volatile var value: Double) : SharedObject(appContext) {
  @Synchronized fun increment(delta: Double): Double {
    value += delta
    return value
  }
}

class ShowcaseTextRef(appContext: AppContext, value: String) : SharedRef<String>(value, appContext) {
  override val nativeRefType = "expo-module-showcase.text"
}
