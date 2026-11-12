/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

package expo.modules.showcase

import expo.modules.kotlin.AppContext
import expo.modules.kotlin.sharedobjects.SharedObject
import expo.modules.kotlin.sharedobjects.SharedRef

class ShowcaseSharedCounter(appContext: AppContext, initialValue: Double) : SharedObject(appContext) {
  @get:Synchronized
  @set:Synchronized
  var value = initialValue

  @Synchronized fun increment(delta: Double): Double {
    value += delta
    return value
  }
}

class ShowcaseTextRef(appContext: AppContext, value: String) : SharedRef<String>(value, appContext) {
  override val nativeRefType = "expo-module-showcase.text"
}
