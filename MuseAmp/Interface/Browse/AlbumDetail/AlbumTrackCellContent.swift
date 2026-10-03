struct AlbumTrackCellContent: Hashable {
    let number: Int
    let title: String
    let durationText: String?
    let isExplicit: Bool
    let isHighlighted: Bool
    let isDownloaded: Bool
    let isPlaying: Bool

    init(
        number: Int,
        title: String,
        durationText: String? = nil,
        isExplicit: Bool = false,
        isHighlighted: Bool = false,
        isDownloaded: Bool = false,
        isPlaying: Bool = false,
    ) {
        self.number = number
        self.title = title
        self.durationText = durationText
        self.isExplicit = isExplicit
        self.isHighlighted = isHighlighted
        self.isDownloaded = isDownloaded
        self.isPlaying = isPlaying
    }
}
