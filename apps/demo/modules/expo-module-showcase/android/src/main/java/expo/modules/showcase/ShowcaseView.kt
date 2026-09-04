package expo.modules.showcase

import android.content.Context
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView

class ShowcaseView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
  override val shouldUseAndroidLayout = true
  private val onValueChanged by EventDispatcher<Map<String, Any>>()
  private val title = ShowcaseStyles.text(context, "原生计数器", 17f, bold = true)
  private val count = ShowcaseStyles.text(context, "1", 28f, ShowcaseStyles.blue, true)
  var label = "原生计数器"
    set(value) { field = value; title.text = value }
  var value = 1.0
    set(value) { field = value; count.text = formatValue(value) }

  init {
    orientation = VERTICAL
    gravity = Gravity.CENTER_VERTICAL
    val inset = ShowcaseStyles.dp(context, 16)
    setPadding(inset, inset, inset, inset)
    background = ShowcaseStyles.background(context, ShowcaseStyles.raised, 12)
    addView(title, LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    addView(count, LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = ShowcaseStyles.dp(context, 10) })
    addView(ShowcaseStyles.button(context, "原生按钮 +1") { increment(1.0, "touch") },
      LayoutParams(MATCH_PARENT, ShowcaseStyles.dp(context, 44)))
  }

  fun increment(delta: Double, source: String): Double {
    value += delta
    onValueChanged(mapOf("label" to label, "value" to value, "source" to source))
    return value
  }
}

internal fun formatValue(value: Double) = if (value == value.toLong().toDouble()) value.toLong().toString() else value.toString()
