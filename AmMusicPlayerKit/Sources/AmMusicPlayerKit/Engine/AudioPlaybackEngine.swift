import AVFoundation

@MainActor
protocol AudioPlaybackEngine: AnyObject {
    var rate: Float { get }
    var currentAVItem: AVPlayerItem? { get }
    var mediaCenterPlayer: AVPlayer? { get }

    func replaceCurrentItem(with item: AVPlayerItem?)
    func play()
    func pause()
    func seek(to time: CMTime) async -> Bool
    func currentTime() -> CMTime

    func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping @Sendable (CMTime) -> Void
    ) -> Any

    func removeTimeObserver(_ observer: Any)

    func preloadNextItem(_ item: AVPlayerItem?)
}
