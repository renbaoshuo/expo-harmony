package expo.modules.showcase

import android.os.Handler
import android.os.Looper
import expo.modules.kotlin.Promise
import expo.modules.kotlin.exception.CodedException
import expo.modules.kotlin.functions.Queues
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.util.concurrent.atomic.AtomicInteger

class ExpoModuleShowcaseModule : Module() {
  private val created = AtomicInteger()
  private val foregrounded = AtomicInteger()
  private val backgrounded = AtomicInteger()
  private val startObserving = AtomicInteger()
  private val stopObserving = AtomicInteger()
  private val sequence = AtomicInteger()
  private var page: ShowcasePage? = null

  override fun definition() = ModuleDefinition {
    Name("ExpoModuleShowcase")
    Constants("platform" to "android", "nativeLanguage" to "Kotlin")
    Events("onShowcaseEvent")
    Function("echo") { value: String -> value }
    AsyncFunction("echoAsync") { value: String -> value }
    AsyncFunction("failAsync") { promise: Promise ->
      promise.reject("ERR_SHOWCASE", "这是用于测试的原生错误。", null)
    }
    Function("emitEvent") { value: String ->
      sendEvent("onShowcaseEvent", mapOf("value" to value, "sequence" to sequence.incrementAndGet(), "platform" to "android"))
    }
    Class(ShowcaseSharedCounter::class) {
      Constructor { value: Double -> ShowcaseSharedCounter(appContext, value) }
      Property("value") { counter: ShowcaseSharedCounter -> counter.value }
        .set { counter: ShowcaseSharedCounter, value: Double -> counter.value = value }
      Function("increment") { counter: ShowcaseSharedCounter, delta: Double -> counter.increment(delta) }
      AsyncFunction("incrementAsync") { counter: ShowcaseSharedCounter, delta: Double -> counter.increment(delta) }
      Events("onValueChanged")
      Function("emitValueChanged") { counter: ShowcaseSharedCounter ->
        counter.emit("onValueChanged", mapOf("value" to counter.value))
      }
    }
    Class(ShowcaseTextRef::class) {
      Property("value") { ref: ShowcaseTextRef -> ref.ref }
    }
    Function("returnSameSharedCounter") { counter: ShowcaseSharedCounter -> counter }
    Function("createSharedTextRef") { value: String -> ShowcaseTextRef(appContext, value) }
    View(ShowcaseView::class) {
      Events("onValueChanged")
      Prop("label") { view: ShowcaseView, label: String -> view.label = label }
      Prop("value") { view: ShowcaseView, value: Double -> view.value = value }
      AsyncFunction("increment") { view: ShowcaseView, delta: Double -> view.increment(delta, "command") }
    }
    AsyncFunction("openNativePage") { initialValue: Double, promise: Promise ->
      if (page != null) throw CodedException("ERR_SHOWCASE_PAGE", "原生页面已经打开。", null)
      val activity = appContext.currentActivity
        ?: throw CodedException("ERR_SHOWCASE_PAGE", "没有可显示页面的 Activity。", null)
      if (activity.isFinishing || activity.isDestroyed) {
        throw CodedException("ERR_SHOWCASE_PAGE", "Activity 已销毁。", null)
      }
      val nativePage = ShowcasePage(activity, initialValue)
      page = nativePage
      nativePage.setOnDismissListener {
        if (page === nativePage) page = null
        promise.resolve(mapOf("action" to nativePage.action, "value" to nativePage.value))
      }
      try {
        nativePage.show()
      } catch (error: Exception) {
        page = null
        throw error
      }
    }.runOnQueue(Queues.MAIN)
    Function("getLifecycleSnapshot") {
      mapOf("created" to created.get(), "foregrounded" to foregrounded.get(), "backgrounded" to backgrounded.get(),
        "startObserving" to startObserving.get(), "stopObserving" to stopObserving.get())
    }
    OnCreate { created.incrementAndGet() }
    OnActivityEntersForeground { foregrounded.incrementAndGet() }
    OnActivityEntersBackground { backgrounded.incrementAndGet() }
    OnStartObserving { startObserving.incrementAndGet() }
    OnStopObserving { stopObserving.incrementAndGet() }
    OnActivityDestroys { closePage() }
    OnDestroy { closePage() }
  }

  private fun closePage() {
    Handler(Looper.getMainLooper()).post { page?.dismiss(); page = null }
  }
}
