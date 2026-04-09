import SnapKit
import Then
import UIKit

@MainActor
class MediaDetailViewController: UIViewController {
    let tableView: UITableView
    let headerContainer = UIView()
    let artworkImageView = AmImageView()
    let shadowContainer = UIView().then {
        $0.layer.shadowColor = UIColor.black.cgColor
        $0.layer.shadowOpacity = 0.25
        $0.layer.shadowRadius = 20
        $0.layer.shadowOffset = CGSize(width: 0, height: 10)
    }

    let footerView = DetailFooterView()

    private var headerWidthConstraint: NSLayoutConstraint?
    private var footerWidthConstraint: NSLayoutConstraint?
    private var lastHeaderWidth: CGFloat = 0

    init(tableStyle: UITableView.Style) {
        tableView = UITableView(frame: .zero, style: tableStyle)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.window != nil else {
            return
        }
        tableView.sizeHeaderToFit(widthConstraint: &headerWidthConstraint, lastWidth: &lastHeaderWidth)
        tableView.sizeFooterToFit(widthConstraint: &footerWidthConstraint)
    }

    func configureDetailArtwork(
        placeholder: String,
        cornerRadius: CGFloat = 12,
        allowsPreviewOnTap: Bool = false
    ) {
        artworkImageView.configure(placeholder: placeholder, cornerRadius: cornerRadius)
        artworkImageView.allowsPreviewOnTap = allowsPreviewOnTap
    }

    func configureDetailHeader(
        arrangedSubviews: [UIView],
        artworkSize: CGFloat,
        customSpacings: [(UIView, CGFloat)] = []
    ) {
        if artworkImageView.superview == nil {
            shadowContainer.addSubview(artworkImageView)
            artworkImageView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }

        let stack = UIStackView(arrangedSubviews: [shadowContainer] + arrangedSubviews).then {
            $0.axis = .vertical
            $0.spacing = InterfaceStyle.Spacing.xSmall
            $0.alignment = .center
            $0.setCustomSpacing(InterfaceStyle.Spacing.medium, after: shadowContainer)
        }
        for (view, spacing) in customSpacings {
            stack.setCustomSpacing(spacing, after: view)
        }

        headerContainer.subviews.forEach { $0.removeFromSuperview() }
        headerContainer.addSubview(stack)

        shadowContainer.snp.remakeConstraints { make in
            make.size.equalTo(artworkSize).priority(.high)
        }

        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.medium).priority(.high)
            make.leading.trailing.equalToSuperview().inset(InterfaceStyle.Spacing.medium).priority(.high)
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.small).priority(.high)
        }

        if headerContainer.frame.width <= 0 || headerContainer.frame.height <= 0 {
            headerContainer.frame = CGRect(x: 0, y: 0, width: max(tableView.bounds.width, 1), height: 1)
        }
        tableView.tableHeaderView = headerContainer
        invalidateHeaderLayout()
    }

    func configureDetailTableView(backgroundColor: UIColor = .systemBackground) {
        tableView.separatorStyle = .none
        tableView.backgroundColor = backgroundColor
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    func configureDetailFooter(hidden: Bool = true) {
        footerView.isHidden = hidden
        if footerView.frame.width <= 0 || footerView.frame.height <= 0 {
            footerView.frame = CGRect(x: 0, y: 0, width: max(tableView.bounds.width, 1), height: 1)
        }
        tableView.tableFooterView = footerView
    }

    func updateFooterText(_ text: String?) {
        footerView.infoText = text
        footerView.isHidden = text?.isEmpty != false
        guard view.window != nil else {
            return
        }
        tableView.sizeFooterToFit(widthConstraint: &footerWidthConstraint)
    }

    func invalidateHeaderLayout(animated: Bool = false) {
        lastHeaderWidth = 0
        guard view.window != nil else {
            return
        }
        tableView.sizeHeaderToFit(widthConstraint: &headerWidthConstraint, lastWidth: &lastHeaderWidth)
        if animated {
            let targetView = parent?.view ?? view
            InterfaceAnimation.smoothSpringAnimate {
                targetView?.layoutIfNeeded()
            }
        }
    }
}
