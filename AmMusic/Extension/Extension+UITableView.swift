import UIKit

extension UITableView {
    func sizeHeaderToFit(widthConstraint: inout NSLayoutConstraint?, lastWidth: inout CGFloat) {
        guard let header = tableHeaderView else { return }
        let width = bounds.width
        guard width > 0, width != lastWidth else { return }
        lastWidth = width
        sizeAuxiliaryView(header, to: width, widthConstraint: &widthConstraint)
        tableHeaderView = header
    }

    func sizeFooterToFit(widthConstraint: inout NSLayoutConstraint?) {
        guard let footer = tableFooterView else { return }
        let width = bounds.width
        guard width > 0 else { return }

        if footer.isHidden {
            footer.frame = CGRect(x: 0, y: 0, width: width, height: .leastNonzeroMagnitude)
            tableFooterView = footer
            return
        }

        sizeAuxiliaryView(footer, to: width, widthConstraint: &widthConstraint)
        tableFooterView = footer
    }

    private func sizeAuxiliaryView(
        _ view: UIView,
        to width: CGFloat,
        widthConstraint: inout NSLayoutConstraint?
    ) {
        view.translatesAutoresizingMaskIntoConstraints = false
        widthConstraint?.isActive = false
        let constraint = view.widthAnchor.constraint(equalToConstant: width)
        constraint.isActive = true
        widthConstraint = constraint
        view.frame = CGRect(x: 0, y: 0, width: width, height: max(view.frame.height, 1))
        let height = view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
    }
}
