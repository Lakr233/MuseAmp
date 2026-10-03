struct AlbumHeaderContent: Hashable {
    let albumName: String
    let artistName: String
    let metadataText: String?
    let playButtonTitle: String
    let shuffleButtonTitle: String

    init(
        albumName: String,
        artistName: String,
        metadataText: String? = nil,
        playButtonTitle: String,
        shuffleButtonTitle: String,
    ) {
        self.albumName = albumName
        self.artistName = artistName
        self.metadataText = metadataText
        self.playButtonTitle = playButtonTitle
        self.shuffleButtonTitle = shuffleButtonTitle
    }
}
