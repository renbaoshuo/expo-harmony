import UIKit

// Match apps/demo/src/theme.ts and its shared card/button components.
enum ShowcaseStyles {
  static let canvas = UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1)
  static let raised = UIColor(red: 247/255, green: 248/255, blue: 250/255, alpha: 1)
  static let text = UIColor(red: 17/255, green: 24/255, blue: 39/255, alpha: 1)
  static let muted = UIColor(red: 102/255, green: 112/255, blue: 133/255, alpha: 1)
  static let blue = UIColor(red: 0, green: 122/255, blue: 1, alpha: 1)

  static func label(_ text: String, size: CGFloat, color: UIColor = text, weight: UIFont.Weight = .regular) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = color
    label.numberOfLines = 0
    return label
  }

  static func button(_ title: String, action: @escaping () -> Void) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
    button.backgroundColor = blue
    button.layer.cornerRadius = 10
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
  }

  static func format(_ value: Double) -> String {
    String(format: "%g", value)
  }
}
