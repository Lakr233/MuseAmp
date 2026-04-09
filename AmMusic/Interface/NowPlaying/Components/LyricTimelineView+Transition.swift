import SnapKit
import UIKit

// MARK: - Core state machine

extension LyricTimelineView {
    func apply(mode: Mode, currentTime: TimeInterval, animated: Bool) {
        let previousMode = self.mode
        let modeChanged = previousMode != mode
        let shouldAnimateOutgoingTransition = modeChanged
            && window != nil
            && previousMode.hasLineContent
            && !isAnimationSuspended
            && UIView.areAnimationsEnabled

        let outgoingTransitionOverlay = shouldAnimateOutgoingTransition
            ? makeOutgoingTransitionOverlay()
            : nil

        self.mode = mode
        self.currentTime = currentTime

        if modeChanged {
            AppLog.info(
                self,
                "lyrics view mode changed previous=\(previousMode.logDescription) next=\(mode.logDescription) suspended=\(isAnimationSuspended) animated=\(animated)"
            )
        }

        switch mode {
        case let .message(message):
            if modeChanged {
                activeIndex = nil
                tableView.reloadData()
            }
            messageLabel.text = message
            messageLabel.layer.removeAllAnimations()
            if let outgoingTransitionOverlay {
                messageLabel.alpha = 0
                messageLabel.isHidden = false
                tableView.isHidden = false
                animateOutgoingTransition(
                    overlay: outgoingTransitionOverlay,
                    targetMode: mode,
                    currentTime: currentTime
                )
                return
            }
            messageLabel.alpha = 1
            messageLabel.isHidden = false
            tableView.isHidden = true
        case .plain:
            if modeChanged {
                activeIndex = nil
                shouldAnimateNextSyncedReveal = false
                tableView.reloadData()
                setScrollOffset(to: 0)
            }
            tableView.isHidden = false
            if let outgoingTransitionOverlay {
                messageLabel.alpha = 1
                messageLabel.isHidden = true
                tableView.alpha = 0
                animateOutgoingTransition(
                    overlay: outgoingTransitionOverlay,
                    targetMode: mode,
                    currentTime: currentTime
                )
                return
            }
            let shouldAnimateReveal = modeChanged && window != nil
            if shouldAnimateReveal {
                performPlainReveal(fadingOutMessage: previousMode.isMessage)
            } else {
                messageLabel.alpha = 1
                messageLabel.isHidden = true
                tableView.alpha = 1
            }
        case let .synced(timeline):
            if modeChanged {
                shouldAnimateNextSyncedReveal = true
                activeIndex = nil
                tableView.reloadData()
                setScrollOffset(to: 0)
            }
            tableView.isHidden = false
            let isTransitioningFromMessage = previousMode.isMessage
            if let outgoingTransitionOverlay {
                messageLabel.alpha = 1
                messageLabel.isHidden = true
                setVisibleCellsAlpha(0)
                animateOutgoingTransition(
                    overlay: outgoingTransitionOverlay,
                    targetMode: mode,
                    currentTime: currentTime
                )
                return
            }
            let shouldAnimateReveal = shouldAnimateNextSyncedReveal && window != nil
            if shouldAnimateReveal {
                performInitialSyncedReveal(
                    with: timeline,
                    currentTime: currentTime,
                    fadingOutMessage: isTransitioningFromMessage
                )
            } else {
                messageLabel.alpha = 1
                messageLabel.isHidden = true
                updateSyncedProgress(with: timeline, currentTime: currentTime, animated: animated && window != nil)
            }
        }
    }

    func syncVisibleState(animated: Bool) {
        switch mode {
        case .message, .plain:
            break
        case let .synced(timeline):
            updateSyncedProgress(with: timeline, currentTime: currentTime, animated: animated)
        }
    }

    // MARK: - Table view insets (header/footer spacers)

    func updateTableViewInsets() {
        let viewportHeight = tableView.bounds.height
        guard viewportHeight > 0 else { return }

        let halfActiveLineHeight = Layout.activeLineHeightEstimate / 2
        let headerHeight = max((viewportHeight * Layout.activeLineAnchorFraction) - halfActiveLineHeight, 0)
        let footerHeight = max((viewportHeight * (1 - Layout.activeLineAnchorFraction)) - halfActiveLineHeight, 0)

        let newInsets = UIEdgeInsets(top: headerHeight, left: 0, bottom: footerHeight, right: 0)
        if tableView.contentInset != newInsets {
            tableView.contentInset = newInsets
        }
    }

    // MARK: - Plain mode

    func performPlainReveal(fadingOutMessage: Bool) {
        tableView.layer.removeAllAnimations()

        if fadingOutMessage {
            messageLabel.isHidden = false
            messageLabel.alpha = 1
        } else {
            messageLabel.alpha = 1
            messageLabel.isHidden = true
        }

        tableView.alpha = 0

        guard !isAnimationSuspended, UIView.areAnimationsEnabled else {
            tableView.alpha = 1
            messageLabel.alpha = 1
            messageLabel.isHidden = true
            return
        }

        InterfaceAnimation.animate(
            duration: LyricTimelineAnimation.plainRevealDuration,
            options: LyricTimelineAnimation.easeOutOptions
        ) {
            self.tableView.alpha = 1
            if fadingOutMessage {
                self.messageLabel.alpha = 0
            }
        } completion: { _ in
            guard case .plain = self.mode else { return }
            self.messageLabel.alpha = 1
            self.messageLabel.isHidden = true
        }
    }

    // MARK: - Outgoing transition

    func makeOutgoingTransitionOverlay() -> UIView? {
        let visibleCells = tableView.visibleCells
        guard !visibleCells.isEmpty else { return nil }

        cleanupOutgoingTransitionOverlay()

        let overlay = UIView(frame: tableView.bounds)
        overlay.backgroundColor = .clear
        overlay.isUserInteractionEnabled = false

        var hasSnapshots = false
        for cell in visibleCells {
            guard let snapshot = cell.snapshotView(afterScreenUpdates: false) else { continue }
            snapshot.frame = cell.convert(cell.bounds, to: tableView)
            snapshot.frame.origin.y -= tableView.contentOffset.y
            overlay.addSubview(snapshot)
            hasSnapshots = true
        }

        guard hasSnapshots else { return nil }

        addSubview(overlay)
        overlay.snp.makeConstraints { make in
            make.edges.equalTo(tableView)
        }
        activeOutgoingTransitionOverlay = overlay
        return overlay
    }

    func animateOutgoingTransition(
        overlay: UIView,
        targetMode: Mode,
        currentTime: TimeInterval
    ) {
        lineTransitionSequence += 1
        let transitionSequence = lineTransitionSequence
        let snapshots = overlay.subviews

        guard !snapshots.isEmpty else {
            cleanupOutgoingTransitionOverlay()
            revealTransitionTargetMode(targetMode, currentTime: currentTime, transitionSequence: transitionSequence)
            return
        }

        for (index, snapshot) in snapshots.enumerated() {
            InterfaceAnimation.animate(
                duration: LyricTimelineAnimation.outgoingFadeDuration,
                delay: Double(index) * LyricTimelineAnimation.outgoingFadeStagger,
                options: LyricTimelineAnimation.easeOutOptions
            ) {
                snapshot.alpha = 0
            }
        }

        let totalDuration = LyricTimelineAnimation.outgoingFadeDuration
            + (Double(max(snapshots.count - 1, 0)) * LyricTimelineAnimation.outgoingFadeStagger)

        InterfaceAnimation.animate(
            duration: totalDuration
        ) {} completion: { _ in
            guard transitionSequence == self.lineTransitionSequence else {
                overlay.removeFromSuperview()
                return
            }
            self.cleanupOutgoingTransitionOverlay()
            self.revealTransitionTargetMode(targetMode, currentTime: currentTime, transitionSequence: transitionSequence)
        }
    }

    func revealTransitionTargetMode(
        _ mode: Mode,
        currentTime: TimeInterval,
        transitionSequence: Int
    ) {
        guard transitionSequence == lineTransitionSequence else { return }

        switch mode {
        case let .message(message):
            messageLabel.text = message
            messageLabel.layer.removeAllAnimations()
            messageLabel.isHidden = false
            messageLabel.alpha = 1
            tableView.isHidden = true
        case .plain:
            performPlainReveal(fadingOutMessage: false)
        case let .synced(timeline):
            performInitialSyncedReveal(
                with: timeline,
                currentTime: currentTime,
                fadingOutMessage: false
            )
        }
    }

    // MARK: - Blur interaction cooldown

    static let blurHideDuration: TimeInterval = 2.0

    func beginBlurHideCooldown() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endBlurHideCooldown),
            object: nil
        )

        if !isBlurHiddenByInteraction {
            isBlurHiddenByInteraction = true
            InterfaceAnimation.smoothSpringAnimate {
                self.topBlurView.alpha = 0
                self.bottomBlurView.alpha = 0
            }
        }

        perform(#selector(endBlurHideCooldown), with: nil, afterDelay: Self.blurHideDuration)
    }

    @objc
    func endBlurHideCooldown() {
        isBlurHiddenByInteraction = false
        InterfaceAnimation.smoothSpringAnimate {
            self.topBlurView.alpha = 1
            self.bottomBlurView.alpha = 1
        }
    }

    // MARK: - Auto scroll cooldown

    var shouldSuspendAutoScroll: Bool {
        isAutoScrollInCooldown
    }

    func resumeAutoScrollIfNeeded(animated: Bool) {
        guard pendingAutoScrollToActiveLine else { return }
        syncVisibleState(animated: animated)
    }

    func beginAutoScrollCooldown() {
        isAutoScrollInCooldown = true
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endAutoScrollCooldown),
            object: nil
        )
        perform(#selector(endAutoScrollCooldown), with: nil, afterDelay: Layout.autoScrollCooldown)
    }

    @objc
    func endAutoScrollCooldown() {
        isAutoScrollInCooldown = false
        resumeAutoScrollIfNeeded(animated: true)
    }

    // MARK: - Gesture handlers

    @objc
    func handleScrollViewTap(_ recognizer: UITapGestureRecognizer) {
        guard case .synced = mode else { return }

        beginBlurHideCooldown()

        let location = recognizer.location(in: tableView)
        guard let indexPath = nearestSeekableIndexPath(to: location),
              let cell = tableView.cellForRow(at: indexPath) as? LyricTimelineCell
        else { return }

        cell.performIndirectTapSelection()
    }

    func makeLyricContextMenu() -> UIMenu? {
        let lines = currentLyricLines()
        guard !lines.isEmpty else { return nil }

        let copyAll = UIAction(
            title: String(localized: "Copy"),
            image: UIImage(systemName: "doc.on.doc")
        ) { [weak self] _ in
            self?.onCopyAllLyrics?(lines)
        }

        let selectCopy = UIAction(
            title: String(localized: "Select & Copy"),
            image: UIImage(systemName: "text.badge.checkmark")
        ) { [weak self] _ in
            self?.onRequestManageLyrics?(lines, self?.activeIndex)
        }

        return UIMenu(children: [copyAll, selectCopy])
    }

    func nearestSeekableIndexPath(to point: CGPoint) -> IndexPath? {
        guard case let .synced(timeline) = mode else { return nil }

        var bestIndexPath: IndexPath?
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for row in timeline.lines.indices {
            guard !isSyntheticLeadingPaddingLine(at: row, in: timeline) else {
                continue
            }

            let indexPath = IndexPath(row: row, section: 0)
            let cellRect = tableView.rectForRow(at: indexPath)
            let distance = abs(cellRect.midY - point.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndexPath = indexPath
            }
        }

        return bestIndexPath
    }

    // MARK: - Logging

    func logLyricSwitch(
        from previousActiveIndex: Int?,
        to nextActiveIndex: Int?,
        timeline: LRCLyricsTimeline,
        currentTime: TimeInterval
    ) {
        guard previousActiveIndex != nextActiveIndex else { return }

        guard let nextActiveIndex,
              timeline.lines.indices.contains(nextActiveIndex)
        else {
            AppLog.info(
                self,
                "Lyrics line cleared previousIndex=\(previousActiveIndex.map(String.init) ?? "nil") playbackTime=\(formattedTimestamp(currentTime))"
            )
            return
        }

        let line = timeline.lines[nextActiveIndex]
        AppLog.info(
            self,
            "Lyrics line switched previousIndex=\(previousActiveIndex.map(String.init) ?? "nil") currentIndex=\(nextActiveIndex) lineTime=\(formattedTimestamp(line.time)) playbackTime=\(formattedTimestamp(currentTime)) text=\"\(sanitizedLogPreview(for: line.text))\""
        )
    }

    func formattedTimestamp(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value.rounded(.down)), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func sanitizedLogPreview(for text: String) -> String {
        sanitizedLogText(text, maxLength: 80)
    }

    func currentLyricLines() -> [String] {
        let rawLines: [String] = switch mode {
        case .message:
            []
        case let .plain(lines):
            lines
        case let .synced(timeline):
            timeline.lines.map(\.text)
        }

        return rawLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func isSyntheticLeadingPaddingLine(at row: Int, in timeline: LRCLyricsTimeline) -> Bool {
        guard row == 0, timeline.lines.count > 1, timeline.lines.indices.contains(row) else {
            return false
        }

        let line = timeline.lines[row]
        return line.time == 0 && line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Cleanup

    func stopTransientAnimations() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endAutoScrollCooldown),
            object: nil
        )
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(endBlurHideCooldown),
            object: nil
        )
        isAutoScrollInCooldown = false
        isBlurHiddenByInteraction = false
        pendingAutoScrollToActiveLine = false
        lineTransitionSequence += 1
        cleanupOutgoingTransitionOverlay()
        removeAnimationsRecursively()
    }

    func cleanupOutgoingTransitionOverlay() {
        activeOutgoingTransitionOverlay?.removeFromSuperview()
        activeOutgoingTransitionOverlay = nil
    }
}
