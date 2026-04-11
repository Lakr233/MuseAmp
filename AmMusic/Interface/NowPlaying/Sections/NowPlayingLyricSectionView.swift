//
//  NowPlayingLyricSectionView.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import SnapKit
import UIKit

final class NowPlayingLyricSectionView: UIView {
    private let lyricView = LyricTimelineView()
    private var displayedLyricsText: String?
    private var isDisplayingLoading = false

    var onSeekToLineTime: (TimeInterval) -> Void = { _ in } {
        didSet {
            lyricView.onSelectLineTime = { [weak self] selectedTime in
                self?.lyricView.updateCurrentTime(selectedTime)
                self?.onSeekToLineTime(selectedTime)
            }
        }
    }

    var onCopyAllLyrics: ([String]) -> Void = { _ in } {
        didSet {
            lyricView.onCopyAllLyrics = onCopyAllLyrics
        }
    }

    var onRequestManageLyrics: (_ lyrics: [String], _ activeIndex: Int?) -> Void = { _, _ in } {
        didSet {
            lyricView.onRequestManageLyrics = onRequestManageLyrics
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(lyricView)

        lyricView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        updateLyrics(text: nil, isLoading: false, currentTime: 0)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateLyrics(text: String?, isLoading: Bool, currentTime: TimeInterval) {
        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isDisplayingLoading != isLoading || displayedLyricsText != normalizedText else {
            lyricView.updateCurrentTime(currentTime)
            return
        }

        AppLog.info(
            self,
            "lyrics refresh apply loading=\(isLoading) \(nowPlayingLogTextSummary(normalizedText)) currentTime=\(String(format: "%.2f", currentTime))",
        )
        isDisplayingLoading = isLoading
        displayedLyricsText = normalizedText
        lyricView.update(text: normalizedText, isLoading: isLoading, currentTime: currentTime)
    }

    func setAnimationSuspended(_ suspended: Bool) {
        lyricView.setAnimationSuspended(suspended)
    }
}
