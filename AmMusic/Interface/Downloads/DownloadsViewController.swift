import AlertController
import AmMusicDatabaseKit
import Combine
import SnapKit
import Then
import UIKit

private enum DownloadsSection: Int {
    case tasks
}

final class DownloadsViewController: UIViewController {
    private let downloadManager: DownloadManager
    private let environment: AppEnvironment?
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = EmptyStateView(
        icon: "arrow.down.circle",
        title: String(localized: "No Active Downloads"),
        subtitle: String(localized: "Downloads will appear here")
    )

    private var cancellable: AnyCancellable?
    private var currentTasks: [ActiveDownloadTask] = []
    private var tasksByTrackID: [String: ActiveDownloadTask] = [:]
    private var hasAppliedInitialSnapshot = false
    private let playlistMenuProvider: AddToPlaylistMenuProvider?
    private let availablePlaylists: (() -> [Playlist])?
    private lazy var diffableDataSource = makeDiffableDataSource()

    private lazy var albumNavigationHelper: AlbumNavigationHelper? = environment.map {
        AlbumNavigationHelper(environment: $0, viewController: self)
    }

    private lazy var songContextMenuProvider = SongContextMenuProvider(
        playlistMenuProvider: playlistMenuProvider
    )

    init(
        downloadManager: DownloadManager,
        playlistStore: PlaylistStore? = nil,
        environment: AppEnvironment? = nil
    ) {
        self.downloadManager = downloadManager
        self.environment = environment
        let resolvedPlaylistStore = playlistStore ?? environment?.playlistStore
        if let resolvedPlaylistStore {
            playlistMenuProvider = AddToPlaylistMenuProvider(
                playlistStore: resolvedPlaylistStore,
                viewController: nil
            )
            availablePlaylists = { resolvedPlaylistStore.playlists }
        } else {
            playlistMenuProvider = nil
            availablePlaylists = nil
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Downloads")
        view.backgroundColor = .systemBackground

        configureTableView()
        configureEmptyState()
        updateBarButton()
        bindToManager()
    }
}

private extension DownloadsViewController {
    func configureTableView() {
        tableView.delegate = self
        tableView.rowHeight = 60
        tableView.separatorStyle = .none
        tableView.register(DownloadProgressCell.self, forCellReuseIdentifier: DownloadProgressCell.reuseID)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { $0.edges.equalToSuperview() }
        _ = diffableDataSource
    }

    func configureEmptyState() {
        tableView.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(200)
        }
    }

    func updateBarButton() {
        let hasActiveTasks = currentTasks.contains { $0.state != .failed }
        if hasActiveTasks {
            let paused = downloadManager.isPausedAll
            let image = UIImage(systemName: paused ? "play.circle.fill" : "pause.circle.fill")
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: image,
                style: .plain,
                target: self,
                action: #selector(togglePauseResume)
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc func togglePauseResume() {
        if downloadManager.isPausedAll {
            downloadManager.resumeAll()
        } else {
            downloadManager.pauseAll()
        }
        updateBarButton()
    }

    func bindToManager() {
        cancellable = downloadManager.tasksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTasks in
                self?.applyUpdate(newTasks)
            }
    }

    func makeDiffableDataSource() -> UITableViewDiffableDataSource<DownloadsSection, String> {
        UITableViewDiffableDataSource<DownloadsSection, String>(
            tableView: tableView
        ) { [weak self] tableView, indexPath, trackID -> UITableViewCell? in
            guard let self,
                  let task = tasksByTrackID[trackID],
                  let cell = tableView.dequeueReusableCell(
                      withIdentifier: DownloadProgressCell.reuseID,
                      for: indexPath
                  ) as? DownloadProgressCell
            else {
                return UITableViewCell()
            }
            cell.update(with: task)
            return cell
        }
    }

    func applyUpdate(_ newTasks: [ActiveDownloadTask]) {
        let previousTrackIDs = currentTasks.map(\.trackID)
        let newTrackIDs = newTasks.map(\.trackID)

        currentTasks = newTasks
        tasksByTrackID = Dictionary(uniqueKeysWithValues: newTasks.map { ($0.trackID, $0) })
        emptyStateView.isHidden = !newTasks.isEmpty

        let identityChanged = previousTrackIDs != newTrackIDs
        let shouldAnimate = hasAppliedInitialSnapshot && identityChanged

        var snapshot = NSDiffableDataSourceSnapshot<DownloadsSection, String>()
        snapshot.appendSections([.tasks])
        snapshot.appendItems(newTrackIDs, toSection: .tasks)

        hasAppliedInitialSnapshot = true
        diffableDataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
            self?.refreshVisibleCells()
        }

        updateBarButton()
    }

    func refreshVisibleCells() {
        for cell in tableView.visibleCells {
            guard let progressCell = cell as? DownloadProgressCell,
                  let indexPath = tableView.indexPath(for: cell),
                  currentTasks.indices.contains(indexPath.row)
            else { continue }
            progressCell.update(with: currentTasks[indexPath.row], animated: true)
        }
    }
}

extension DownloadsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard currentTasks.indices.contains(indexPath.row) else { return }
        let task = currentTasks[indexPath.row]

        if task.state == .failed {
            downloadManager.retryFailed(trackID: task.trackID)
            return
        }

        guard task.state == .waitingForNetwork,
              downloadManager.isPausedForNetwork
        else {
            return
        }

        ConfirmationAlertPresenter.present(
            on: self,
            title: task.title,
            message: downloadConfirmationMessage(),
            confirmTitle: String(localized: "Download")
        ) { [weak self] in
            self?.downloadManager.allowCellularDownload(trackID: task.trackID)
        }
    }

    private func downloadConfirmationMessage() -> String {
        var messageComponents = [String(localized: "Are you sure you want to download now?")]
        if environment?.networkMonitor.connectionType == .cellular {
            messageComponents.append(String(localized: "This will use cellular data."))
        }
        return messageComponents.joined(separator: "\n\n")
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard currentTasks.indices.contains(indexPath.row) else { return nil }
        let task = currentTasks[indexPath.row]

        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let entry = PlaylistEntry(
                trackID: task.trackID,
                title: task.title,
                artistName: task.artistName,
                albumID: task.albumID,
                artworkURL: task.artworkURL?.absoluteString
            )
            var primaryActions: [UIMenuElement] = []
            if task.state == .waitingForNetwork,
               downloadManager.isPausedForNetwork
            {
                primaryActions.append(UIAction(
                    title: String(localized: "Allow Cellular Download"),
                    image: UIImage(systemName: "antenna.radiowaves.left.and.right")
                ) { [weak self] _ in
                    self?.downloadManager.allowCellularDownload(trackID: task.trackID)
                })
            }

            return songContextMenuProvider.menu(
                title: task.title,
                for: entry,
                context: .downloads,
                configuration: .init(
                    availablePlaylists: availablePlaylists,
                    showInAlbum: environment == nil ? nil : { [weak self] in
                        self?.openAlbum(for: task)
                    },
                    primaryActions: primaryActions
                )
            )
        }
    }

    func tableView(
        _: UITableView,
        previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _: UITableView,
        previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        CellContextMenuPreviewHelper.targetedPreview(for: configuration, in: tableView)
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard currentTasks.indices.contains(indexPath.row) else { return nil }
        let task = currentTasks[indexPath.row]
        let title = task.state == .failed
            ? String(localized: "Delete")
            : String(localized: "Cancel")
        let action = UIContextualAction(style: .destructive, title: title) { [weak self] _, _, completion in
            self?.downloadManager.cancelTask(trackID: task.trackID)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func openAlbum(for task: ActiveDownloadTask) {
        albumNavigationHelper?.pushAlbumDetail(songID: task.trackID, albumID: task.albumID)
    }
}
