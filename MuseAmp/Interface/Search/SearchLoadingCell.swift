import SnapKit
import UIKit

@MainActor
class SearchLoadingCell: TableBaseCell {
    class var reuseID: String {
        String(describing: self)
    }

    private let spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.hidesWhenStopped = true
        return spinner
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        isUserInteractionEnabled = false
        contentView.addSubview(spinner)
        spinner.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.equalToSuperview().offset(32)
            make.bottom.equalToSuperview().inset(32)
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
