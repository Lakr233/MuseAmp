import AmMusicDatabaseKit
import SnapKit
import Then
import UIKit

final class AmSongCell: TableBaseCell {
    static let reuseID = "AmSongCell"

    enum AppearanceStyle {
        case standard
        case nowPlaying
    }

    private enum Layout {
        static let defaultRowInsets = InterfaceStyle.Insets.symmetric(
            vertical: 6,
            horizontal: InterfaceStyle.Spacing.small
        )
    }

    private let artworkView = AmImageView().then { $0.configure(placeholder: "music.note", cornerRadius: 6) }
    private let titleLabel = UILabel().then { $0.font = .systemFont(ofSize: 16); $0.textColor = .label }
    private let subtitleLabel = UILabel().then { $0.font = .systemFont(ofSize: 13); $0.textColor = .secondaryLabel }
    private let trailingLabel = UILabel().then {
        $0.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        $0.textColor = .tertiaryLabel
        $0.textAlignment = .right
        $0.setContentHuggingPriority(.required, for: .horizontal)
        $0.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private let downloadedIndicator = UIImageView(image: UIImage(systemName: "arrow.down.to.line.circle.fill")).then {
        $0.tintColor = .tintColor
        $0.contentMode = .scaleAspectFit
        $0.isHidden = true
    }

    private let textStack = UIStackView()
    private let row = UIStackView()

    private var rowInsets = Layout.defaultRowInsets
    private var appearanceStyle: AppearanceStyle = .standard
    private var rowTopConstraint: Constraint?
    private var rowLeftConstraint: Constraint?
    private var rowBottomConstraint: Constraint?
    private var rowRightConstraint: Constraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        clipsToBounds = true
        contentView.clipsToBounds = true

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.do {
            $0.axis = .vertical
            $0.spacing = InterfaceStyle.Spacing.xSmall
        }

        row.addArrangedSubview(artworkView)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(trailingLabel)
        row.addArrangedSubview(downloadedIndicator)
        row.do {
            $0.axis = .horizontal
            $0.spacing = InterfaceStyle.Spacing.small
            $0.alignment = .center
        }

        contentView.addSubview(row)

        artworkView.snp.makeConstraints { $0.size.equalTo(44) }
        downloadedIndicator.snp.makeConstraints { $0.size.equalTo(18) }
        row.snp.makeConstraints { make in
            rowTopConstraint = make.top.equalToSuperview().inset(rowInsets.top).constraint
            rowLeftConstraint = make.left.equalToSuperview().inset(rowInsets.left).constraint
            rowBottomConstraint = make.bottom.equalToSuperview().inset(rowInsets.bottom).constraint
            rowRightConstraint = make.right.equalToSuperview().inset(rowInsets.right).constraint
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkView.reset()
        titleLabel.text = nil
        subtitleLabel.text = nil
        trailingLabel.text = nil
        trailingLabel.isHidden = false
        downloadedIndicator.isHidden = true
        setRowInsets(Layout.defaultRowInsets)
        applyAppearanceStyle(.standard)
    }

    // MARK: - Configuration

    func configure(with song: CatalogSong, artworkURL: URL? = nil) {
        titleLabel.text = song.attributes.name
        subtitleLabel.text = song.attributes.artistName
        trailingLabel.text = song.attributes.durationInMillis.map { formattedDuration(millis: $0) }
        artworkView.loadImage(
            url: artworkURL
                ?? APIClient.resolveMediaURL(song.attributes.artwork?.url, width: 88, height: 88)
        )
    }

    func configure(with track: AudioTrackRecord) {
        titleLabel.text = track.title
        subtitleLabel.text = [track.artistName, track.albumTitle].filter { !$0.isEmpty }.joined(separator: " · ")
        let seconds = Int(track.durationSeconds)
        trailingLabel.text = seconds > 0 ? formattedDuration(seconds: seconds) : nil
    }

    func configure(with track: PlaybackTrack, showsAlbumName: Bool = false, trailingText: String? = nil) {
        titleLabel.text = track.title
        if showsAlbumName,
           let albumName = track.albumName,
           !albumName.isEmpty
        {
            subtitleLabel.text = "\(track.artistName) · \(albumName)"
        } else {
            subtitleLabel.text = track.artistName
        }
        trailingLabel.text = trailingText
        artworkView.loadImage(url: track.artworkURL)
    }

    func configure(with entry: PlaylistEntry, artworkURL: URL? = nil) {
        titleLabel.text = entry.title
        subtitleLabel.text = [entry.artistName, entry.albumTitle].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
        trailingLabel.text = entry.durationMillis.map { formattedDuration(millis: $0) }
        artworkView.loadImage(
            url: artworkURL
                ?? APIClient.resolveMediaURL(entry.artworkURL, width: 88, height: 88)
        )
    }

    func loadArtwork(url: URL?) {
        artworkView.loadImage(url: url)
    }

    func setRowInsets(_ insets: UIEdgeInsets) {
        guard rowInsets != insets else {
            return
        }
        rowInsets = insets
        applyRowInsets()
    }

    func setDownloadedIndicatorVisible(_ visible: Bool) {
        downloadedIndicator.isHidden = !visible
    }

    func setTrailingLabelHidden(_ isHidden: Bool) {
        trailingLabel.isHidden = isHidden
    }

    func applyAppearanceStyle(_ style: AppearanceStyle) {
        appearanceStyle = style

        switch style {
        case .standard:
            titleLabel.textColor = .label
            subtitleLabel.textColor = .secondaryLabel
            trailingLabel.textColor = .tertiaryLabel
        case .nowPlaying:
            titleLabel.textColor = .white
            subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.78)
            trailingLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        }
    }

    private func applyRowInsets() {
        rowTopConstraint?.update(inset: rowInsets.top)
        rowLeftConstraint?.update(inset: rowInsets.left)
        rowBottomConstraint?.update(inset: rowInsets.bottom)
        rowRightConstraint?.update(inset: rowInsets.right)
    }
}
