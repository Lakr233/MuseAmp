import SnapKit
import Then
import UIKit

class ShowMoreCell: TableBaseCell {
    static let reuseID = "ShowMoreCell"
    private let label = UILabel().then { $0.font = .systemFont(ofSize: 15, weight: .medium); $0.textColor = .tintColor; $0.textAlignment = .center; $0.text = String(localized: "Show More") }
    private let spinner = UIActivityIndicatorView(style: .medium).then { $0.hidesWhenStopped = true }
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.addSubview(label)
        contentView.addSubview(spinner)
        label.snp.makeConstraints { $0.center.equalToSuperview(); $0.top.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.small) }
        spinner.snp.makeConstraints { $0.center.equalToSuperview() }
    }

    func configure(isLoading: Bool) {
        label.isHidden = isLoading
        if isLoading { spinner.startAnimating() } else { spinner.stopAnimating() }
    }

    override func prepareForReuse() {
        super.prepareForReuse(); spinner.stopAnimating(); label.isHidden = false
    }
}

class SearchLoadingCell: TableBaseCell {
    static let reuseID = "SearchLoadingCell"

    private let spinner = UIActivityIndicatorView(style: .large).then {
        $0.hidesWhenStopped = true
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isUserInteractionEnabled = false
        contentView.addSubview(spinner)
        spinner.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.bottom.equalToSuperview().inset(32)
        }
    }

    func startAnimating() {
        spinner.startAnimating()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        spinner.stopAnimating()
    }
}
