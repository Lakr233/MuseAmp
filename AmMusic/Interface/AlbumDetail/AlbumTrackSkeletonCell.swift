import SnapKit
import UIKit

final class AlbumTrackSkeletonCell: TableBaseCell {
    static let reuseID = "AlbumTrackSkeletonCell"

    private let numberBar = ShineBarView()
    private let titleBar = ShineBarView()
    private let durationBar = ShineBarView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        contentView.addSubview(numberBar)
        contentView.addSubview(titleBar)
        contentView.addSubview(durationBar)

        numberBar.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(20)
            make.height.equalTo(12)
        }

        durationBar.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(52)
            make.centerY.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(12)
        }

        titleBar.snp.makeConstraints { make in
            make.leading.equalTo(numberBar.snp.trailing).offset(16)
            make.trailing.lessThanOrEqualTo(durationBar.snp.leading).offset(-16)
            make.centerY.equalToSuperview()
            make.width.equalTo(contentView.snp.width).multipliedBy(0.45)
            make.height.equalTo(14)
            make.top.bottom.equalToSuperview().inset(16)
        }

        accessoryType = .none
    }
}
