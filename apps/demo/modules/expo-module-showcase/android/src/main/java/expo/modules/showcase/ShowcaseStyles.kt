package expo.modules.showcase

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.widget.Button
import android.widget.TextView

internal object ShowcaseStyles {
  val canvas = Color.rgb(242, 242, 247)
  val surface = Color.WHITE
  val raised = Color.rgb(247, 248, 250)
  val text = Color.rgb(17, 24, 39)
  val muted = Color.rgb(102, 112, 133)
  val blue = Color.rgb(0, 122, 255)
  val softBlue = Color.rgb(234, 243, 255)

  fun dp(context: Context, value: Int) = (value * context.resources.displayMetrics.density).toInt()
  fun background(context: Context, color: Int, radius: Int) = GradientDrawable().apply {
    setColor(color)
    cornerRadius = dp(context, radius).toFloat()
  }
  fun text(context: Context, label: String, size: Float, color: Int = text, bold: Boolean = false) = TextView(context).apply {
    text = label
    textSize = size
    setTextColor(color)
    if (bold) setTypeface(typeface, Typeface.BOLD)
  }
  fun button(context: Context, label: String, secondary: Boolean = false, onClick: () -> Unit) = Button(context).apply {
    text = label
    textSize = 14f
    isAllCaps = false
    setTextColor(if (secondary) blue else Color.WHITE)
    background = background(context, if (secondary) softBlue else blue, 10)
    minHeight = dp(context, 44)
    minimumHeight = dp(context, 44)
    setOnClickListener { onClick() }
  }
}
