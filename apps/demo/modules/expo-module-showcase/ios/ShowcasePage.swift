/*!
 * @expo-harmony-copyright
 *
 * Copyright 2026-present, Baoshuo <i@baoshuo.ren> ( https://baoshuo.ren ).
 * Released under MIT license. https://github.com/renbaoshuo/expo-harmony
 */

import UIKit

/// A UIKit page presented by the native module, with its result delivered on dismissal.
final class ShowcasePage: UIViewController {
  private var value: Double
  private var completion: ((String, Double) -> Void)?
  private let count = ShowcaseStyles.label("", size: 36, color: ShowcaseStyles.blue, weight: .bold)
  private var finishing = false

  init(initialValue: Double, completion: @escaping (String, Double) -> Void) {
    value = initialValue
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("Use init(initialValue:completion:)") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "原生页面"
    view.backgroundColor = ShowcaseStyles.canvas
    navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", primaryAction: UIAction { [weak self] _ in
      self?.finish(action: "cancel")
    })
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", primaryAction: UIAction { [weak self] _ in
      self?.finish(action: "done")
    })
    let scroll = UIScrollView()
    let content = UIStackView()
    content.axis = .vertical
    content.spacing = 18
    let card = UIStackView()
    card.axis = .vertical
    card.spacing = 16
    card.backgroundColor = .white
    card.layer.cornerRadius = 16
    card.isLayoutMarginsRelativeArrangement = true
    card.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    card.addArrangedSubview(ShowcaseStyles.label("计数", size: 18, weight: .bold))
    count.text = ShowcaseStyles.format(value)
    card.addArrangedSubview(count)
    card.addArrangedSubview(ShowcaseStyles.button("增加 1") { [weak self] in
      guard let self else { return }
      self.value += 1
      self.count.text = ShowcaseStyles.format(self.value)
    })
    content.addArrangedSubview(card)
    view.addSubview(scroll)
    scroll.addSubview(content)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
      content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
      content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
      content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
      content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
    ])
  }

  func finish(action: String) {
    guard !finishing else { return }
    finishing = true
    let completion = self.completion
    self.completion = nil
    let value = self.value
    dismiss(animated: true) { completion?(action, value) }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if !finishing && (isBeingDismissed || navigationController?.isBeingDismissed == true) {
      completion?("cancel", value)
      completion = nil
    }
  }
}
