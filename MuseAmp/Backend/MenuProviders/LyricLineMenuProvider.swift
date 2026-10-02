//
//  LyricLineMenuProvider.swift
//  MuseAmp
//
//  Created by qaq on 2/7/2026.
//

import UIKit

@MainActor
final class LyricLineMenuProvider {
    enum InteractionType: CaseIterable {
        case playFromLine
        case copyLine
        case copyAllLyrics
        case selectAndCopy
    }

    struct Context {
        var allowedInteractionTypes: Set<InteractionType> = Set(InteractionType.allCases)
        /// The track the line belongs to. `Play from Here` does nothing once
        /// another track is playing, since `lineTime` is a time in this one.
        var trackID: String?
        var lineText: String
        var lineTime: TimeInterval?
        var allLines: [String]
        var selectedLineIndex: Int?
    }

    private let playbackController: PlaybackController
    #if os(iOS)
        private let feedbackGenerator = UINotificationFeedbackGenerator()
    #endif

    var onSelectAndCopy: (_ lines: [String], _ selectedIndex: Int?) -> Void = { _, _ in }

    init(playbackController: PlaybackController) {
        self.playbackController = playbackController
    }

    func menu(context: Context) -> UIMenu? {
        var playActions: [UIAction] = []
        if context.allowedInteractionTypes.contains(.playFromLine), let time = context.lineTime {
            playActions.append(UIAction(
                title: String(localized: "Play from Here"),
                subtitle: Self.formatTimestamp(time),
                image: UIImage(systemName: "play.fill"),
            ) { [weak self, trackID = context.trackID] _ in
                guard let self else { return }
                let currentTrackID = playbackController.snapshot.currentTrack?.id
                guard currentTrackID == trackID else {
                    AppLog.info(self, "playFromLine ignored, track changed from=\(trackID ?? "nil") to=\(currentTrackID ?? "nil")")
                    return
                }
                playbackController.seek(to: time)
                playbackController.play()
            })
        }

        var copyActions: [UIAction] = []
        let lineText = context.lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if context.allowedInteractionTypes.contains(.copyLine), !lineText.isEmpty {
            copyActions.append(UIAction(
                title: String(localized: "Copy Line"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { [weak self] _ in
                UIPasteboard.general.string = lineText
                self?.notifyCopySuccess()
            })
        }
        if context.allowedInteractionTypes.contains(.copyAllLyrics), !context.allLines.isEmpty {
            let allLines = context.allLines
            copyActions.append(UIAction(
                title: String(localized: "Copy All Lyrics"),
                image: UIImage(systemName: "doc.on.doc.fill"),
            ) { [weak self] _ in
                UIPasteboard.general.string = allLines.joined(separator: "\n")
                self?.notifyCopySuccess()
            })
        }
        if context.allowedInteractionTypes.contains(.selectAndCopy), !context.allLines.isEmpty {
            let allLines = context.allLines
            let selectedIndex = context.selectedLineIndex
            copyActions.append(UIAction(
                title: String(localized: "Select & Copy"),
                image: UIImage(systemName: "text.badge.checkmark"),
            ) { [weak self] _ in
                self?.onSelectAndCopy(allLines, selectedIndex)
            })
        }

        var sections: [UIMenuElement] = []
        if let playSection = MenuSectionProvider.inline(playActions) {
            sections.append(playSection)
        }
        if let copySection = MenuSectionProvider.inline(copyActions) {
            sections.append(copySection)
        }
        guard !sections.isEmpty else { return nil }
        return UIMenu(children: sections)
    }

    private func notifyCopySuccess() {
        #if os(iOS)
            feedbackGenerator.notificationOccurred(.success)
        #endif
    }

    nonisolated static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
