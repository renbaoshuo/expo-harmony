import ExpoModulesCore
import UIKit

final class ShowcaseView: ExpoView {
  let onValueChanged = EventDispatcher()
  private let title = ShowcaseStyles.label("原生计数器", size: 17, weight: .bold)
  private let count = ShowcaseStyles.label("1", size: 28, color: ShowcaseStyles.blue, weight: .bold)
  private let stack = UIStackView()
  var label = "原生计数器" { didSet { title.text = label } }
  var value = 1.0 { didSet { count.text = ShowcaseStyles.format(value) } }

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = ShowcaseStyles.raised
    layer.cornerRadius = 12
    stack.axis = .vertical
    stack.spacing = 10
    stack.addArrangedSubview(title)
    stack.addArrangedSubview(count)
    stack.addArrangedSubview(ShowcaseStyles.button("原生按钮 +1") { [weak self] in
      _ = self?.increment(1, source: "touch")
    })
    addSubview(stack)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    stack.frame = bounds.insetBy(dx: 16, dy: 16)
  }

  func increment(_ delta: Double, source: String) -> Double {
    value += delta
    onValueChanged(["label": label, "value": value, "source": source])
    return value
  }
}
