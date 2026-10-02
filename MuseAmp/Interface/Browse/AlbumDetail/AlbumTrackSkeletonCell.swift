import SnapKit
import UIKit

@MainActor
class AlbumTrackSkeletonCell: TableBaseCell {
    class var reuseID: String {
        String(describing: self)
    }

    private let numberBar = SkeletonShineBarView()
    private let titleBar = SkeletonShineBarView()
    private let durationBar = SkeletonShineBarView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        contentView.addSubview(numberBar)
        contentView.addSubview(titleBar)
        contentView.addSubview(durationBar)

        numberBar.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 20, height: 12))
        }
        durationBar.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(52)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 36, height: 12))
        }
        titleBar.snp.makeConstraints { make in
            make.leading.equalTo(numberBar.snp.trailing).offset(16)
            make.trailing.lessThanOrEqualTo(durationBar.snp.leading).offset(-16)
            make.centerY.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0.45)
            make.height.equalTo(14)
            make.top.bottom.equalToSuperview().inset(16)
        }

        accessoryType = .none
    }
}
