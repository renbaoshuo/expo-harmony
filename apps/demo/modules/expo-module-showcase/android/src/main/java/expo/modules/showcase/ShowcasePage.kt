package expo.modules.showcase

import android.app.Activity
import android.app.Dialog
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.Window
import android.widget.LinearLayout
import android.widget.ScrollView

/** A native full-screen page; no React root or JavaScript-rendered content. */
class ShowcasePage(activity: Activity, initialValue: Double) : Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar) {
  var value = initialValue
    private set
  var action = "cancel"
    private set

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    requestWindowFeature(Window.FEATURE_NO_TITLE)
    val inset = ShowcaseStyles.dp(context, 16)
    val root = LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      setPadding(inset, inset, inset, inset)
      setBackgroundColor(ShowcaseStyles.canvas)
      fitsSystemWindows = true
    }
    val header = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
    header.addView(ShowcaseStyles.button(context, "取消", true) { dismiss() })
    header.addView(ShowcaseStyles.text(context, "原生页面", 18f, bold = true).apply { gravity = Gravity.CENTER },
      LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
    header.addView(ShowcaseStyles.button(context, "完成") { action = "done"; dismiss() })
    root.addView(header, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
    val content = LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      setPadding(0, inset, 0, inset)
    }
    fun addText(label: String, size: Float, color: Int, bold: Boolean = false) {
      content.addView(ShowcaseStyles.text(context, label, size, color, bold),
        LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = inset })
    }
    addText("Expo Modules", 12f, ShowcaseStyles.blue, true)
    addText("原生页面交互", 30f, ShowcaseStyles.text, true)
    addText("在原生页面中修改计数，完成后将结果带回测试页面。", 15f, ShowcaseStyles.muted)
    val card = LinearLayout(context).apply {
      orientation = LinearLayout.VERTICAL
      setPadding(inset, inset, inset, inset)
      background = ShowcaseStyles.background(context, ShowcaseStyles.surface, 16)
    }
    val count = ShowcaseStyles.text(context, formatValue(value), 36f, ShowcaseStyles.blue, true)
    card.addView(ShowcaseStyles.text(context, "页面计数器", 18f, bold = true))
    card.addView(count, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
      topMargin = inset; bottomMargin = inset
    })
    card.addView(ShowcaseStyles.button(context, "增加计数 +1") {
      value += 1
      count.text = formatValue(value)
    }, LinearLayout.LayoutParams(MATCH_PARENT, ShowcaseStyles.dp(context, 44)))
    content.addView(card, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = inset })
    addText("取消或系统返回将放弃本次修改。", 13f, ShowcaseStyles.muted)
    root.addView(ScrollView(context).apply { addView(content) }, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
    setContentView(root)
    setCanceledOnTouchOutside(false)
    window?.setLayout(MATCH_PARENT, MATCH_PARENT)
  }
}
