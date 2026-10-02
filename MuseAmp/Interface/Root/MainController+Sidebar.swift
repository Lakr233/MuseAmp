//
//  MainController+Sidebar.swift
//  MuseAmp
//
//  Created by @Lakr233 on 2026/04/11.
//

import Combine
import MuseAmpDatabaseKit
import SnapKit
import Then
import UIKit

// MARK: - Sidebar Data Model

nonisolated enum SidebarSection: Int, Hashable {
    case navigation
    case library
    case playlists
    case settings

    var showsHeader: Bool {
        self == .library || self == .playlists
    }
}

nonisolated enum SidebarItem: Hashable {
    case destination(RootDestination)
    case playlist(UUID)
}

// MARK: - SidebarPlaylistCell

private final class SidebarPlaylistCell: UICollectionViewListCell {
    let placeholderImageView = UIImageView()
    let coverImageView = UIImageView()
    private(set) var representedPlaylistID: UUID?
    private var imageViewsConfigured = false
    private weak var internalImageView: UIImageView?

    private static let spacerImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { _ in }

    private static let defaultPlaceholder = UIImage(named: "Avatar")

    func applyPlaylist(name: String, coverImage: UIImage?, playlistID: UUID) {
        representedPlaylistID = playlistID
        var content = UIListContentConfiguration.sidebarCell()
        content.text = name
        content.image = Self.spacerImage
        content.imageProperties.cornerRadius = 4
        content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        contentConfiguration = content

        configureImageViewsIfNeeded()
        internalImageView = nil

        placeholderImageView.image = Self.defaultPlaceholder
        if let coverImage {
            coverImageView.image = coverImage
            coverImageView.alpha = 1
            placeholderImageView.alpha = 0
        } else {
            coverImageView.alpha = 0
            placeholderImageView.alpha = 1
        }
    }

    func updateCover(_ image: UIImage) {
        coverImageView.image = image
        coverImageView.alpha = 1
        placeholderImageView.alpha = 0
        setNeedsLayout()
        layoutIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard imageViewsConfigured else { return }

        contentView.bringSubviewToFront(placeholderImageView)
        contentView.bringSubviewToFront(coverImageView)

        let ref: UIImageView
        if let cached = internalImageView {
            ref = cached
        } else if let found = findInternalImageView(in: contentView) {
            internalImageView = found
            ref = found
        } else {
            return
        }

        let frame = ref.convert(ref.bounds, to: contentView)
        guard frame.width > 0 else { return }
        placeholderImageView.frame = frame
        coverImageView.frame = frame
    }

    private func configureImageViewsIfNeeded() {
        guard !imageViewsConfigured else { return }
        imageViewsConfigured = true

        for iv in [placeholderImageView, coverImageView] {
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.layer.cornerRadius = 4
            iv.isUserInteractionEnabled = false
            contentView.addSubview(iv)
        }
        coverImageView.alpha = 0
    }

    private func findInternalImageView(in view: UIView) -> UIImageView? {
        for subview in view.subviews where subview !== placeholderImageView && subview !== coverImageView {
            if let iv = subview as? UIImageView {
                return iv
            }
            if let found = findInternalImageView(in: subview) {
                return found
            }
        }
        return nil
    }
}

// MARK: - SidebarViewController

final class SidebarViewController: UIViewController {
    let environment: AppEnvironment

    var onDestinationSelected: (RootDestination) -> Void = { _ in }
    var onPlaylistSelected: (UUID) -> Void = { _ in }
    var onPlaylistsDidReload: ([UUID]) -> Void = { _ in }
    var onImportPlaylistRequested: (() -> Void)?

    private(set) var selectedDestination: RootDestination = .albums
    private(set) var selectedPlaylistID: UUID?

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SidebarSection, SidebarItem>!
    private var cancellables: Set<AnyCancellable> = []
    private nonisolated(unsafe) var playlistObserver: NSObjectProtocol?
    private nonisolated(unsafe) var playlistArtworkObserver: NSObjectProtocol?
    private nonisolated(unsafe) var serverConfigurationObserver: NSObjectProtocol?
    private lazy var playlistMenuProvider = PlaylistContextMenuProvider(
        playlistStore: environment.playlistStore,
        viewController: self,
    )

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
        configureDataSource()
        applyInitialSnapshot()
        observePlaylistChanges()
        observePlaylistArtworkChanges()
        observeServerConfigurationChanges()

        selectItem(.destination(.albums))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        #if targetEnvironment(macCatalyst)
            // The sidebar has no title or bar items. On Mac its empty bar
            // would only push the first row down below the traffic lights.
            navigationController?.setNavigationBarHidden(true, animated: false)
        #endif
    }

    deinit {
        if let playlistObserver {
            NotificationCenter.default.removeObserver(playlistObserver)
        }
        if let playlistArtworkObserver {
            NotificationCenter.default.removeObserver(playlistArtworkObserver)
        }
        if let serverConfigurationObserver {
            NotificationCenter.default.removeObserver(serverConfigurationObserver)
        }
    }

    // MARK: - Collection View Setup

    private func setupCollectionView() {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, layoutEnvironment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            let sections = self?.dataSource?.snapshot().sectionIdentifiers ?? []
            configuration.headerMode = Self.headerMode(forSectionAt: sectionIndex, in: sections)
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: layoutEnvironment)
        }

        collectionView = UICollectionView(frame: UIScreen.main.bounds, collectionViewLayout: layout).then {
            $0.backgroundColor = .clear
            $0.delegate = self
        }

        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    /// Sections are looked up by position in the current snapshot: the
    /// Search section is left out when no server is configured, so a
    /// section's position is not its raw value.
    nonisolated static func headerMode(
        forSectionAt sectionIndex: Int,
        in sections: [SidebarSection],
    ) -> UICollectionLayoutListConfiguration.HeaderMode {
        guard sections.indices.contains(sectionIndex), sections[sectionIndex].showsHeader else {
            return .none
        }
        return .supplementary
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

        let playlistRegistration = UICollectionView.CellRegistration<SidebarPlaylistCell, UUID> {
            [weak self] cell, _, playlistID in
            guard let self else { return }
            let playlistModel = environment.playlistStore.playlist(for: playlistID)
            let name = playlistModel?.name ?? String(localized: "Playlist")

            var coverImage: UIImage?
            if let playlistModel,
               let coverData = playlistModel.coverImageData,
               let image = UIImage(data: coverData)
            {
                coverImage = image
            }

            cell.applyPlaylist(name: name, coverImage: coverImage, playlistID: playlistID)

            if coverImage == nil, let playlistModel, !playlistModel.songs.isEmpty {
                let apiBaseURL = environment.apiClient.baseURL
                let paths = environment.paths
                Task { @MainActor [weak self, weak cell] in
                    guard let self, let cell else { return }
                    let resolver: @Sendable (PlaylistEntry, Int, Int) -> URL? = { entry, width, height in
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
                    guard cell.representedPlaylistID == playlistID else { return }
                    cell.updateCover(image)
                }
            }
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
            case let .playlist(id):
                return collectionView.dequeueConfiguredReusableCell(
                    using: playlistRegistration, for: indexPath, item: id,
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

        if isSearchAvailable {
            snapshot.appendSections([.navigation])
            snapshot.appendItems([.destination(.search)], toSection: .navigation)
        }

        snapshot.appendSections([.library])
        var libraryItems: [SidebarItem] = [
            .destination(.albums),
            .destination(.songs),
        ]
        if isDownloadsAvailable {
            libraryItems.append(.destination(.downloads))
        }
        libraryItems.append(.destination(.playlistList))
        snapshot.appendItems(libraryItems, toSection: .library)

        snapshot.appendSections([.playlists])
        let playlists = orderedSidebarPlaylists()
        snapshot.appendItems(playlists.map { SidebarItem.playlist($0.id) }, toSection: .playlists)

        snapshot.appendSections([.settings])
        snapshot.appendItems([.destination(.settings)], toSection: .settings)

        return snapshot
    }

    private func applyInitialSnapshot() {
        dataSource.apply(buildSnapshot(), animatingDifferences: false)
    }

    func reloadPlaylistsSection() {
        environment.playlistStore.reload()

        var snapshot = buildSnapshot()
        let playlistItems = snapshot.itemIdentifiers(inSection: .playlists)
        if !playlistItems.isEmpty {
            snapshot.reconfigureItems(playlistItems)
        }
        dataSource.apply(snapshot, animatingDifferences: true)

        let playlists = environment.playlistStore.playlists
        if let selectedPlaylistID,
           let playlist = playlists.first(where: { $0.id == selectedPlaylistID })
        {
            selectItem(.playlist(playlist.id))
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
            MainActor.assumeIsolated {
                self?.reloadPlaylistsSection()
            }
        }
    }

    private func observePlaylistArtworkChanges() {
        playlistArtworkObserver = NotificationCenter.default.addObserver(
            forName: .playlistArtworkDidUpdate,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let playlistIDs = notification.userInfo?[AppNotificationUserInfoKey.playlistIDs] as? [UUID],
                  !playlistIDs.isEmpty
            else {
                return
            }
            MainActor.assumeIsolated {
                self?.reconfigurePlaylistItems(Set(playlistIDs))
            }
        }
    }

    private func observeServerConfigurationChanges() {
        serverConfigurationObserver = NotificationCenter.default.addObserver(
            forName: .serverConfigurationDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleServerConfigurationDidChange()
            }
        }
    }

    private func handleServerConfigurationDidChange() {
        handleDestinationAvailabilityDidChange()
    }

    private func handleDestinationAvailabilityDidChange() {
        let fallbackToAlbums = (selectedDestination == .search && !isSearchAvailable)
            || (selectedDestination == .downloads && !isDownloadsAvailable)
        dataSource.apply(buildSnapshot(), animatingDifferences: true) { [weak self] in
            guard let self else { return }

            if fallbackToAlbums {
                selectItem(.destination(.albums))
                onDestinationSelected(.albums)
                return
            }

            if let selectedPlaylistID {
                selectItem(.playlist(selectedPlaylistID))
                return
            }

            selectItem(.destination(selectedDestination))
        }
    }

    private func reconfigurePlaylistItems(_ playlistIDs: Set<UUID>) {
        guard !playlistIDs.isEmpty else {
            return
        }

        var snapshot = dataSource.snapshot()
        let itemsToReconfigure = snapshot.itemIdentifiers.filter { item in
            guard case let .playlist(playlistID) = item else {
                return false
            }
            return playlistIDs.contains(playlistID)
        }
        guard !itemsToReconfigure.isEmpty else {
            return
        }

        snapshot.reconfigureItems(itemsToReconfigure)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func orderedSidebarPlaylists() -> [Playlist] {
        let playlists = environment.playlistStore.playlists
        guard let likedSongs = playlists.first(where: { $0.isLikedSongsPlaylist }) else {
            return Array(playlists.sorted { $0.updatedAt > $1.updatedAt }.prefix(8))
        }

        let others = playlists
            .filter { $0.id != likedSongs.id }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(7)
        return [likedSongs] + others
    }

    private var isSearchAvailable: Bool {
        AppPreferences.currentSubsonicConfiguration != nil
    }

    private var isDownloadsAvailable: Bool {
        isSearchAvailable
    }

    // MARK: - Selection

    func selectItem(_ item: SidebarItem) {
        guard let indexPath = dataSource.indexPath(for: item) else { return }
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])

        switch item {
        case let .destination(destination):
            selectedDestination = destination
            selectedPlaylistID = nil
        case let .playlist(id):
            selectedPlaylistID = id
        }
    }

    private func contextMenu(for playlistID: UUID) -> UIMenu? {
        playlistMenuProvider.menu(
            playlistProvider: { [weak self] in
                self?.environment.playlistStore.playlist(for: playlistID)
            },
            onOpen: { [weak self] playlist in
                self?.selectedPlaylistID = playlist.id
                self?.onPlaylistSelected(playlist.id)
            },
            onImport: { [weak self] in
                self?.onImportPlaylistRequested?()
            },
            onRename: { [weak self] _ in
                self?.reloadPlaylistsSection()
            },
            onDuplicate: { [weak self] _ in
                self?.reloadPlaylistsSection()
            },
            onClear: { [weak self] _ in
                self?.reloadPlaylistsSection()
            },
            onDelete: { [weak self] _ in
                self?.reloadPlaylistsSection()
            },
        )
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
        case let .playlist(id):
            selectedPlaylistID = id
            onPlaylistSelected(id)
        }
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case let .playlist(playlistID) = item,
              environment.playlistStore.playlist(for: playlistID) != nil
        else {
            return nil
        }

        return UIContextMenuConfiguration(
            identifier: playlistID.uuidString as NSString,
            previewProvider: nil,
        ) { [weak self] _ in
            self?.contextMenu(for: playlistID)
        }
    }
}
