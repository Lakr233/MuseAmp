//
//  AppleMusicImportViewController.swift
//  MuseAmp
//
//  Created by Hwang on 2026/07/20.
//

import AlertController
import SnapKit
import Then
import UIKit

@available(iOS 16.0, macCatalyst 17.0, *)
final class AppleMusicImportViewController: UIViewController {
    fileprivate nonisolated enum Section: Int, Hashable {
        case playlists
    }

    fileprivate enum DisplayState {
        case loading
        case denied
        case empty
        case loaded
    }

    private let environment: AppEnvironment
    private lazy var importer = AppleMusicPlaylistImporter(
        apiClient: environment.apiClient,
        playlistStore: environment.playlistStore,
    )

    private let tableView = UITableView(frame: UIScreen.main.bounds, style: .insetGrouped)
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let deniedStateView = EmptyStateView(
        icon: "music.note.house",
        title: String(localized: "Apple Music Access Denied"),
        subtitle: String(localized: "Allow access to your Apple Music library in the Settings app, then try again."),
    )
    private let emptyStateView = EmptyStateView(
        icon: "music.note.list",
        title: String(localized: "No Playlists Found"),
        subtitle: String(localized: "Your Apple Music library has no playlists to import."),
    )
    private let openSettingsButton = UIButton(configuration: .borderedProminent()).then {
        $0.configuration?.title = String(localized: "Open Settings")
    }

    private var playlists: [AppleMusicPlaylistSummary] = []
    private var hasAppliedInitialSnapshot = false
    private lazy var dataSource = makeDataSource()

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Import from Apple Music")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            primaryAction: UIAction { [weak self] _ in
                self?.reload()
            },
        )

        configureTableView()
        configureStateViews()

        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.playlists])
        dataSource.apply(snapshot, animatingDifferences: false)
        hasAppliedInitialSnapshot = true

        reload()
    }

    private func reload() {
        Task { @MainActor [weak self] in
            await self?.connectAndLoad()
        }
    }

    private func connectAndLoad() async {
        setDisplayState(.loading)
        var state = importer.authorizationState
        if state == .notDetermined {
            state = await importer.requestAuthorization()
        }
        guard state == .authorized else {
            setDisplayState(.denied)
            return
        }
        await loadPlaylists()
    }

    private func loadPlaylists() async {
        do {
            playlists = try await importer.fetchLibraryPlaylists()
            applySnapshot()
            setDisplayState(playlists.isEmpty ? .empty : .loaded)
        } catch {
            AppLog.error(self, "loadPlaylists failed error=\(error)")
            playlists = []
            applySnapshot()
            setDisplayState(.empty)
            presentErrorAlert(
                title: String(localized: "Could Not Load Playlists"),
                message: error.localizedDescription,
            )
        }
    }
}

@available(iOS 16.0, macCatalyst 17.0, *)
private extension AppleMusicImportViewController {
    func configureTableView() {
        tableView.delegate = self
        tableView.register(
            AppleMusicPlaylistCell.self,
            forCellReuseIdentifier: String(describing: AppleMusicPlaylistCell.self),
        )
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.applySoftEdgeEffects()
    }

    func configureStateViews() {
        let deniedStack = UIStackView(arrangedSubviews: [deniedStateView, openSettingsButton]).then {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = InterfaceStyle.Spacing.medium
        }
        view.addSubview(deniedStack)
        deniedStack.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(InterfaceStyle.Spacing.large)
        }

        view.addSubview(emptyStateView)
        emptyStateView.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(InterfaceStyle.Spacing.large)
        }

        view.addSubview(loadingIndicator)
        loadingIndicator.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
        }

        deniedStack.isHidden = true
        emptyStateView.isHidden = true

        openSettingsButton.addAction(
            UIAction { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            },
            for: .touchUpInside,
        )
    }

    func setDisplayState(_ state: DisplayState) {
        if state == .loading {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }
        deniedStateView.superview?.isHidden = state != .denied
        emptyStateView.isHidden = state != .empty
        tableView.isHidden = state != .loaded
    }

    func makeDataSource() -> UITableViewDiffableDataSource<Section, String> {
        UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, playlistID in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: AppleMusicPlaylistCell.self),
                for: indexPath,
            )
            if let playlistCell = cell as? AppleMusicPlaylistCell,
               let playlist = self?.playlists.first(where: { $0.id == playlistID })
            {
                playlistCell.configure(name: playlist.name, curatorName: playlist.curatorName)
            }
            return cell
        }
    }

    func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, String>()
        snapshot.appendSections([.playlists])
        snapshot.appendItems(playlists.map(\.id), toSection: .playlists)
        dataSource.apply(snapshot, animatingDifferences: hasAppliedInitialSnapshot)
    }

    func presentErrorAlert(title: String, message: String) {
        let alert = AlertViewController(title: .init(title), message: .init(message)) { context in
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }
}

@available(iOS 16.0, macCatalyst 17.0, *)
extension AppleMusicImportViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let playlistID = dataSource.itemIdentifier(for: indexPath),
              let playlist = playlists.first(where: { $0.id == playlistID })
        else { return }
        confirmImport(of: playlist)
    }
}

@available(iOS 16.0, macCatalyst 17.0, *)
private extension AppleMusicImportViewController {
    func confirmImport(of playlist: AppleMusicPlaylistSummary) {
        ConfirmationAlertPresenter.present(
            on: self,
            title: String(localized: "Import Playlist"),
            message: String(
                format: String(localized: "Import “%@” from Apple Music? Each song will be matched against your music library."),
                playlist.name,
            ),
            confirmTitle: String(localized: "Import"),
        ) { [weak self] in
            self?.performImport(of: playlist)
        }
    }

    func performImport(of playlist: AppleMusicPlaylistSummary) {
        let progressAlert = AlertProgressIndicatorViewController(
            title: "Importing Playlist",
            message: "Fetching songs from Apple Music...",
        )
        present(progressAlert, animated: true)

        Task { @MainActor [weak self, weak progressAlert] in
            guard let self else { return }
            do {
                let result = try await importer.importPlaylist(playlist) { processed, total in
                    progressAlert?.progressContext.purpose(
                        message: String(
                            format: String(localized: "Matching songs %d/%d..."),
                            processed, total,
                        ),
                    )
                }
                progressAlert?.dismiss(animated: true) { [weak self] in
                    self?.presentImportResult(result)
                }
            } catch {
                AppLog.error(self, "performImport failed name=\(playlist.name) error=\(error)")
                progressAlert?.dismiss(animated: true) { [weak self] in
                    self?.presentErrorAlert(
                        title: String(localized: "Import Failed"),
                        message: error.localizedDescription,
                    )
                }
            }
        }
    }

    func presentImportResult(_ result: AppleMusicPlaylistImporter.ImportResult) {
        let title: String
        var message: String
        if result.importedCount > 0 {
            title = String(localized: "Import Complete")
            message = String(
                format: String(localized: "Imported %1$d of %2$d songs into “%3$@”."),
                result.importedCount, result.totalSongCount, result.playlistName,
            )
            if !result.unmatchedSongs.isEmpty {
                message += "\n" + String(
                    format: String(localized: "%d songs were not found in your library."),
                    result.unmatchedSongs.count,
                )
            }
        } else if result.totalSongCount == 0 {
            title = String(localized: "Nothing to Import")
            message = String(format: String(localized: "“%@” has no songs."), result.playlistName)
        } else {
            title = String(localized: "No Matches Found")
            message = String(
                format: String(localized: "None of the %1$d songs in “%2$@” were found in your music library."),
                result.totalSongCount, result.playlistName,
            )
        }
        presentErrorAlert(title: title, message: message)
    }
}

private final class AppleMusicPlaylistCell: TableBaseCell {
    func configure(name: String, curatorName: String?) {
        var content = defaultContentConfiguration()
        content.text = name
        if let curatorName, !curatorName.isEmpty {
            content.secondaryText = curatorName
        } else {
            content.secondaryText = String(localized: "Apple Music Playlist")
        }
        content.image = UIImage(systemName: "music.note.list")
        contentConfiguration = content
    }
}
