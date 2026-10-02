import SnapKit
import UIKit

@MainActor
class ShowMoreCell: TableBaseCell {
    class var reuseID: String {
        String(describing: self)
    }

    private let label: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .tintColor
        label.textAlignment = .center
        label.text = String(localized: "Show More")
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.hidesWhenStopped = true
        return spinner
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(label)
        contentView.addSubview(spinner)

        label.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.small)
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.small)
        }

        spinner.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    func configure(isLoading: Bool) {
        label.isHidden = isLoading
        if isLoading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        spinner.stopAnimating()
        label.isHidden = false
    }
}
