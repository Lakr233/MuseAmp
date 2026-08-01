//
//  SkippedSongsViewController.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/08/01.
//

import MuseAmpDatabaseKit
import UIKit

final class SkippedSongsViewController: UIViewController {
    private var items: [PreparedTransferSkippedItem]
    private let trackRemovalService: MusicLibraryTrackRemovalService?
    private var hasAppliedInitialSnapshot = false
    private var didNotifyDismiss = false

    var onDismiss: () -> Void = {}

    private let tableView = UITableView(frame: UIScreen.main.bounds, style: .insetGrouped)
    private lazy var dataSource = makeDataSource()
    private lazy var removeButton = UIBarButtonItem(
        title: String(localized: "Remove"),
        style: .plain,
        target: self,
        action: #selector(removeSelectedTapped),
    )

    init(
        items: [PreparedTransferSkippedItem],
        trackRemovalService: MusicLibraryTrackRemovalService?,
        title: String = String(localized: "Skipped Songs"),
    ) {
        self.items = items
        self.trackRemovalService = trackRemovalService
        super.init(nibName: nil, bundle: nil)
        self.title = title
        preferredContentSize = CGSize(width: 500, height: 600)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            },
        )
        if trackRemovalService != nil {
            removeButton.isEnabled = false
            navigationItem.rightBarButtonItem = removeButton
        }

        tableView.delegate = self
        tableView.register(
            SkippedSongCell.self,
            forCellReuseIdentifier: String(describing: SkippedSongCell.self),
        )
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.setEditing(trackRemovalService != nil, animated: false)

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map(\.trackID), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
        hasAppliedInitialSnapshot = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let dismissed = isBeingDismissed
            || navigationController?.isBeingDismissed == true
            || presentingViewController == nil
        guard dismissed, !didNotifyDismiss else {
            return
        }
        didNotifyDismiss = true
        onDismiss()
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Int, String> {
        UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, trackID in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: SkippedSongCell.self),
                for: indexPath,
            )
            if let skippedCell = cell as? SkippedSongCell,
               let item = self?.items.first(where: { $0.trackID == trackID })
            {
                skippedCell.configure(item: item)
            }
            return cell
        }
    }

    private func updateRemoveButton() {
        let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0
        removeButton.isEnabled = selectedCount > 0
        removeButton.title = selectedCount > 0
            ? String(format: String(localized: "Remove (%lld)"), selectedCount)
            : String(localized: "Remove")
    }

    @objc private func removeSelectedTapped() {
        guard let trackRemovalService else {
            return
        }
        let selectedTrackIDs = (tableView.indexPathsForSelectedRows ?? [])
            .compactMap { dataSource.itemIdentifier(for: $0) }
        guard !selectedTrackIDs.isEmpty else {
            return
        }

        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Remove from Library"),
            message: String(
                format: String(localized: "Remove %lld songs from the library? Their files will be deleted from this device."),
                selectedTrackIDs.count,
            ),
            confirmTitle: String(localized: "Remove"),
        ) { [weak self] in
            self?.removeTracks(selectedTrackIDs, using: trackRemovalService)
        }
    }

    private func removeTracks(_ trackIDs: [String], using service: MusicLibraryTrackRemovalService) {
        for trackID in trackIDs {
            service.removeTrack(trackID: trackID)
        }
        AppLog.info(self, "removed \(trackIDs.count) skipped track(s) from library")

        let removedIDs = Set(trackIDs)
        items.removeAll { removedIDs.contains($0.trackID) }

        guard !items.isEmpty else {
            dismiss(animated: true)
            return
        }
        var snapshot = dataSource.snapshot()
        snapshot.deleteItems(trackIDs)
        dataSource.apply(snapshot, animatingDifferences: hasAppliedInitialSnapshot)
        updateRemoveButton()
    }
}

extension SkippedSongsViewController: UITableViewDelegate {
    func tableView(_: UITableView, didSelectRowAt _: IndexPath) {
        updateRemoveButton()
    }

    func tableView(_: UITableView, didDeselectRowAt _: IndexPath) {
        updateRemoveButton()
    }
}

private final class SkippedSongCell: TableBaseCell {
    func configure(item: PreparedTransferSkippedItem) {
        var content = defaultContentConfiguration()
        content.text = item.title.nilIfEmpty ?? item.trackID
        content.secondaryText = [item.artistName.nilIfEmpty, item.reason.nilIfEmpty]
            .compactMap(\.self)
            .joined(separator: " · ")
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: "exclamationmark.triangle")
        content.imageProperties.tintColor = .systemOrange
        contentConfiguration = content
    }
}
