import ConfigurableKit
import UIKit

final class ConfigurableInfoView: ConfigurableView {
    var valueLabel: EasyHitButton {
        contentView as! EasyHitButton
    }

    override init() {
        super.init()
        valueLabel.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.titleLabel?.numberOfLines = 1
        valueLabel.titleLabel?.lineBreakMode = .byTruncatingMiddle
        valueLabel.contentHorizontalAlignment = .right
    }

    func configure(value: String) {
        let attrString = NSAttributedString(string: value, attributes: [
            .foregroundColor: UIColor.tintColor,
            .font: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            ),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        valueLabel.setAttributedTitle(attrString, for: .normal)
    }

    override class func createContentView() -> UIView {
        EasyHitButton()
    }

    func use(menu: @escaping () -> [UIMenuElement]) {
        valueLabel.showsMenuAsPrimaryAction = true
        valueLabel.menu = .init(children: [
            UIDeferredMenuElement.uncached { completion in
                completion(menu())
            },
        ])
    }
}
