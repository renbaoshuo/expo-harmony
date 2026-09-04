import ExpoModulesCore
import UIKit

public final class ExpoModuleShowcaseModule: Module {
  private var counts = ["created": 0, "foregrounded": 0, "backgrounded": 0, "startObserving": 0, "stopObserving": 0]
  private let lock = NSLock()
  private var sequence = 0
  private var page: ShowcasePage?

  public func definition() -> ModuleDefinition {
    Name("ExpoModuleShowcase")
    Constants(["platform": "ios", "nativeLanguage": "Swift"])
    Events("onShowcaseEvent")
    Function("echo") { (value: String) in value }
    AsyncFunction("echoAsync") { (value: String) in value }
    AsyncFunction("failAsync") { () throws -> Void in
      throw Exception(name: "ShowcaseException", description: "这是用于测试的原生错误。", code: "ERR_SHOWCASE")
    }
    Function("emitEvent") { (value: String) in
      self.sequence += 1
      self.sendEvent("onShowcaseEvent", ["value": value, "sequence": self.sequence, "platform": "ios"])
    }
    Class(ShowcaseSharedCounter.self) {
      Constructor { (value: Double) in ShowcaseSharedCounter(value) }
      Property("value") { (counter: ShowcaseSharedCounter) in counter.value }
        .set { (counter: ShowcaseSharedCounter, value: Double) in counter.value = value }
      Function("increment") { (counter: ShowcaseSharedCounter, delta: Double) in counter.increment(delta) }
      AsyncFunction("incrementAsync") { (counter: ShowcaseSharedCounter, delta: Double) in counter.increment(delta) }
      Function("emitValueChanged") { (counter: ShowcaseSharedCounter) in
        counter.emit(event: "onValueChanged", arguments: ["value": counter.value])
      }
    }
    Class(ShowcaseTextRef.self) {
      Property("value") { (ref: ShowcaseTextRef) in ref.ref }
    }
    Function("returnSameSharedCounter") { (counter: ShowcaseSharedCounter) in counter }
    Function("createSharedTextRef") { (value: String) in ShowcaseTextRef(value) }
    View(ShowcaseView.self) {
      Events("onValueChanged")
      Prop("label") { (view: ShowcaseView, label: String) in view.label = label }
      Prop("value") { (view: ShowcaseView, value: Double) in view.value = value }
      AsyncFunction("increment") { (view: ShowcaseView, delta: Double) in view.increment(delta, source: "command") }
    }
    AsyncFunction("openNativePage") { (initialValue: Double, promise: Promise) in
      guard self.page == nil, let presenter = self.appContext?.utilities?.currentViewController(),
        presenter.viewIfLoaded?.window != nil, !presenter.isBeingDismissed else {
        throw Exception(name: "ShowcasePageException", description: "没有可用的页面容器，或原生页面已经打开。", code: "ERR_SHOWCASE_PAGE")
      }
      let page = ShowcasePage(initialValue: initialValue) { [weak self] action, value in
        self?.page = nil
        promise.resolve(["action": action, "value": value])
      }
      self.page = page
      let navigation = UINavigationController(rootViewController: page)
      navigation.modalPresentationStyle = .fullScreen
      navigation.overrideUserInterfaceStyle = .light
      navigation.navigationBar.tintColor = ShowcaseStyles.blue
      let appearance = UINavigationBarAppearance()
      appearance.configureWithOpaqueBackground()
      appearance.backgroundColor = ShowcaseStyles.canvas
      navigation.navigationBar.standardAppearance = appearance
      navigation.navigationBar.scrollEdgeAppearance = appearance
      presenter.present(navigation, animated: true)
    }.runOnQueue(.main)
    Function("getLifecycleSnapshot") { () -> [String: Int] in
      self.lock.lock()
      defer { self.lock.unlock() }
      return self.counts
    }
    OnCreate { self.record("created") }
    OnAppEntersForeground { self.record("foregrounded") }
    OnAppEntersBackground { self.record("backgrounded") }
    OnStartObserving { self.record("startObserving") }
    OnStopObserving { self.record("stopObserving") }
    OnDestroy {
      DispatchQueue.main.async { self.page?.finish(action: "cancel"); self.page = nil }
    }
  }

  private func record(_ name: String) {
    lock.lock()
    defer { lock.unlock() }
    counts[name, default: 0] += 1
  }
}
