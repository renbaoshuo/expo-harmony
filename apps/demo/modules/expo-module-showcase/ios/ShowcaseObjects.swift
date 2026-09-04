import ExpoModulesCore
import Foundation

final class ShowcaseSharedCounter: SharedObject {
  private let lock = NSLock()
  private var storedValue: Double
  var value: Double {
    get { lock.lock(); defer { lock.unlock() }; return storedValue }
    set { lock.lock(); defer { lock.unlock() }; storedValue = newValue }
  }

  init(_ value: Double) {
    storedValue = value
    super.init()
  }

  func increment(_ delta: Double) -> Double {
    lock.lock()
    defer { lock.unlock() }
    storedValue += delta
    return storedValue
  }
}

final class ShowcaseTextRef: SharedRef<String> {
  override var nativeRefType: String { "expo-module-showcase.text" }
}
