//
//  MainController+Sidebar.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AmMusicDatabaseKit
import Combine
import SnapKit
import Then
import UIKit

// MARK: - Sidebar Data Model

nonisolated enum SidebarSection: Int, Hashable {
    case navigation
    case library
    case playlists
}

nonisolated enum SidebarItem: Hashable {
    case destination(RootDestination)
    case playlist(UUID, String)
}

// MARK: - SidebarViewController

final class SidebarViewController: UIViewController {
    let environment: AppEnvironment

    var onDestinationSelected: (RootDestination) -> Void = { _ in }
    var onPlaylistSelected: (UUID) -> Void = { _ in }
    var onSettingsTapped: () -> Void = {}
    var onPlaylistsDidReload: ([UUID]) -> Void = { _ in }

    private(set) var selectedPlaylistID: UUID?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SidebarSection, SidebarItem>!
    private var cancellables: Set<AnyCancellable> = []
    private var playlistObserver: NSObjectProtocol?
    private var currentDownloadBadgeCount = 0

    private let settingsButton = UIButton(type: .system)

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        setupCollectionView()
        setupSettingsButton()
        configureDataSource()
        applyInitialSnapshot()
        observePlaylistChanges()
        observeDownloadBadge()

        selectItem(.destination(.albums))
    }

    deinit {
        if let playlistObserver {
            NotificationCenter.default.removeObserver(playlistObserver)
        }
    }

    // MARK: - Collection View Setup

    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { sectionIndex, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            let section = SidebarSection(rawValue: sectionIndex)
            configuration.headerMode = (section == .library || section == .playlists) ? .supplementary : .none
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout).then {
            $0.backgroundColor = .clear
            $0.delegate = self
        }

        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
    }

    // MARK: - Settings Button

    private func setupSettingsButton() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "gearshape")
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        settingsButton.configuration = config
        settingsButton.addTarget(self, action: #selector(settingsButtonTapped), for: .touchUpInside)
        settingsButton.contentHorizontalAlignment = .leading

        view.addSubview(settingsButton)

        settingsButton.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(4)
            make.leading.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-4)
            make.height.equalTo(40)
        }
    }

    @objc private func settingsButtonTapped() {
        onSettingsTapped()
    }

    // MARK: - Data Source Configuration

    private func configureDataSource() {
        let destinationRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, RootDestination> {
            cell, _, destination in
            var content = UIListContentConfiguration.sidebarCell()
            content.text = destination.title
            content.image = UIImage(systemName: destination.imageName)
            cell.contentConfiguration = content
        }

        let playlistRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, (UUID, String)> {
            [weak self] cell, _, playlist in
            guard let self else { return }
            var content = UIListContentConfiguration.sidebarCell()
            content.text = playlist.1
            content.image = UIImage(systemName: "music.note.list")
            content.imageProperties.cornerRadius = 4
            content.imageProperties.maximumSize = CGSize(width: 28, height: 28)

            let playlistID = playlist.0
            if let playlistModel = environment.playlistStore.playlist(for: playlistID) {
                if let coverData = playlistModel.coverImageData, let coverImage = UIImage(data: coverData) {
                    content.image = coverImage
                } else if !playlistModel.songs.isEmpty {
                    let apiBaseURL = environment.apiClient.baseURL
                    let paths = environment.paths
                    Task { @MainActor [weak self, weak cell, weak collectionView = self.collectionView] in
                        guard let self, let cell, let collectionView else { return }
                        let resolver: (PlaylistEntry, Int, Int) -> URL? = { entry, width, height in
                            let localURL = paths.artworkCacheURL(for: entry.trackID)
                            if FileManager.default.fileExists(atPath: localURL.path) {
                                return localURL
                            }
                            return APIClient.resolveMediaURL(entry.artworkURL, width: width, height: height, baseURL: apiBaseURL)
                        }
                        let image = await environment.playlistCoverArtworkCache.image(
                            for: playlistModel, sideLength: 28, scale: UIScreen.main.scale,
                            urlResolver: resolver,
                        )
                        guard let currentIndexPath = collectionView.indexPath(for: cell),
                              let currentItem = dataSource.itemIdentifier(for: currentIndexPath),
                              case let .playlist(currentID, _) = currentItem,
                              currentID == playlistID
                        else { return }
                        var updated = content
                        updated.image = image
                        cell.contentConfiguration = updated
                    }
                }
            }

            cell.contentConfiguration = content
        }

        let headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
            elementKind: UICollectionView.elementKindSectionHeader,
        ) { [weak self] headerView, _, indexPath in
            guard let self else { return }
            var content = UIListContentConfiguration.sidebarHeader()
            let section = dataSource.snapshot().sectionIdentifiers[indexPath.section]
            switch section {
            case .library:
                content.text = String(localized: "Library")
            case .playlists:
                content.text = String(localized: "Playlists")
            default:
                break
            }
            headerView.contentConfiguration = content
        }

        dataSource = UICollectionViewDiffableDataSource<SidebarSection, SidebarItem>(collectionView: collectionView) {
            (collectionView: UICollectionView, indexPath: IndexPath, item: SidebarItem) -> UICollectionViewCell? in
            switch item {
            case let .destination(destination):
                return collectionView.dequeueConfiguredReusableCell(
                    using: destinationRegistration, for: indexPath, item: destination,
                )
            case let .playlist(id, name):
                return collectionView.dequeueConfiguredReusableCell(
                    using: playlistRegistration, for: indexPath, item: (id, name),
                )
            }
        }

        dataSource.supplementaryViewProvider = {
            (collectionView: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? in
            guard kind == UICollectionView.elementKindSectionHeader else { return nil }
            return collectionView.dequeueConfiguredReusableSupplementary(
                using: headerRegistration, for: indexPath,
            )
        }
    }

    // MARK: - Snapshots

    private func buildSnapshot() -> NSDiffableDataSourceSnapshot<SidebarSection, SidebarItem> {
        var snapshot = NSDiffableDataSourceSnapshot<SidebarSection, SidebarItem>()

        snapshot.appendSections([.navigation])
        snapshot.appendItems([.destination(.search)], toSection: .navigation)

        snapshot.appendSections([.library])
        var libraryItems: [SidebarItem] = [
            .destination(.albums),
            .destination(.songs),
        ]
        if currentDownloadBadgeCount > 0 {
            libraryItems.append(.destination(.downloads))
        }
        libraryItems.append(.destination(.playlistList))
        snapshot.appendItems(libraryItems, toSection: .library)

        snapshot.appendSections([.playlists])
        let playlists = environment.playlistStore.playlists
        snapshot.appendItems(playlists.map { SidebarItem.playlist($0.id, $0.name) }, toSection: .playlists)

        return snapshot
    }

    private func applyInitialSnapshot() {
        dataSource.apply(buildSnapshot(), animatingDifferences: false)
    }

    func reloadPlaylistsSection() {
        environment.playlistStore.reload()

        dataSource.apply(buildSnapshot(), animatingDifferences: true)

        let playlists = environment.playlistStore.playlists
        if let selectedPlaylistID,
           let playlist = playlists.first(where: { $0.id == selectedPlaylistID })
        {
            selectItem(.playlist(playlist.id, playlist.name))
        }

        onPlaylistsDidReload(playlists.map(\.id))
    }

    // MARK: - Observers

    private func observePlaylistChanges() {
        playlistObserver = NotificationCenter.default.addObserver(
            forName: .playlistsDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            self?.reloadPlaylistsSection()
        }
    }

    private func observeDownloadBadge() {
        environment.downloadManager.tasksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tasks in
                guard let self else { return }
                let count = tasks.count
                let wasActive = currentDownloadBadgeCount > 0
                let isActive = count > 0
                currentDownloadBadgeCount = count
                guard wasActive != isActive else { return }
                reloadLibrarySection()
            }
            .store(in: &cancellables)
    }

    private func reloadLibrarySection() {
        let downloadsGone = currentDownloadBadgeCount == 0
        dataSource.apply(buildSnapshot(), animatingDifferences: true)

        if downloadsGone, selectedPlaylistID == nil {
            let currentDestination = dataSource.itemIdentifier(
                for: collectionView.indexPathsForSelectedItems?.first ?? IndexPath(),
            )
            if currentDestination == nil {
                onDestinationSelected(.albums)
                selectItem(.destination(.albums))
            }
        }
    }

    // MARK: - Selection

    func selectItem(_ item: SidebarItem) {
        guard let indexPath = dataSource.indexPath(for: item) else { return }
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])

        switch item {
        case .destination:
            selectedPlaylistID = nil
        case let .playlist(id, _):
            selectedPlaylistID = id
        }
    }
}

// MARK: - UICollectionViewDelegate

extension SidebarViewController: UICollectionViewDelegate {
    func collectionView(_: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case let .destination(destination):
            selectedPlaylistID = nil
            onDestinationSelected(destination)
        case let .playlist(id, _):
            selectedPlaylistID = id
            onPlaylistSelected(id)
        }
    }
}
