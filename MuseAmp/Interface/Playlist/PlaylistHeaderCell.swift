import SnapKit
import UIKit

@MainActor
class PlaylistHeaderCell: TableBaseCell {
    class var reuseID: String {
        String(describing: self)
    }

    let artworkImageView = MuseAmpImageView()

    private let shadowContainer: UIView = {
        let view = UIView()
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.25
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 5)
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        artworkImageView.configure(placeholder: "music.note.list", cornerRadius: 12)

        shadowContainer.addSubview(artworkImageView)
        contentView.addSubview(shadowContainer)

        artworkImageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        shadowContainer.snp.makeConstraints { make in
            make.size.equalTo(200)
            make.top.equalToSuperview().offset(InterfaceStyle.Spacing.medium)
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().inset(InterfaceStyle.Spacing.medium)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkImageView.reset()
    }
}
