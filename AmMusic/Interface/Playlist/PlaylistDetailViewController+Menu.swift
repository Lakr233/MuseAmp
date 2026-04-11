//
//  PlaylistDetailViewController+Menu.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import AlertController
import AmMusicDatabaseKit
import UIKit

extension PlaylistDetailViewController {
    func updateOptionsMenu() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: buildOptionsMenu(),
        )
    }

    func buildOptionsMenu() -> UIMenu {
        var sections: [UIMenuElement] = []

        if let playbackMenuProvider,
           let playbackSection = MenuSectionProvider.inline(
               playbackMenuProvider.listPrimaryActions(
                   tracksProvider: { [weak self] in
                       self?.playlistPlaybackTracks() ?? []
                   },
                   sourceProvider: { [weak self] in
                       .playlist(self?.playlistID ?? UUID())
                   },
               ),
           )
        {
            sections.append(playbackSection)
        }

        if let renameSection = MenuSectionProvider.inline([
            UIAction(
                title: String(localized: "Rename"),
                image: UIImage(systemName: "pencil"),
            ) { [weak self] _ in
                self?.showRenameAlert()
            },
        ]) {
            sections.append(renameSection)
        }

        if let coverSection = MenuSectionProvider.inline([buildCoverMenu()]) {
            sections.append(coverSection)
        }

        if let downloadSection = buildDownloadSection() {
            sections.append(downloadSection)
        }

        if environment != nil, let refreshSection = MenuSectionProvider.inline([
            UIAction(
                title: String(localized: "Refresh"),
                image: UIImage(systemName: "arrow.clockwise"),
            ) { [weak self] _ in
                self?.refreshPlaylistSongs()
            },
        ]) {
            sections.append(refreshSection)
        }

        if let organizeSection = MenuSectionProvider.inline([
            UIAction(
                title: isEditing ? String(localized: "Done") : String(localized: "Reorder Songs"),
                image: UIImage(systemName: isEditing ? "checkmark" : "arrow.up.arrow.down"),
            ) { [weak self] _ in
                guard let self else { return }
                setEditing(!isEditing, animated: true)
                updateOptionsMenu()
            },
        ]) {
            sections.append(organizeSection)
        }

        return UIMenu(children: sections)
    }

    func buildCoverMenu() -> UIMenu {
        let showCoverAction = UIAction(
            title: String(localized: "Show Cover"),
            image: UIImage(systemName: "photo.on.rectangle"),
            attributes: canPreviewCover ? [] : .disabled,
        ) { [weak self] _ in
            self?.showCoverPreview()
        }

        let changeCoverAction = UIAction(
            title: String(localized: "Change Cover"),
            image: UIImage(systemName: "photo"),
        ) { [weak self] _ in
            self?.showImagePicker()
        }

        var children: [UIMenuElement] = [showCoverAction, changeCoverAction]

        if canRegenerateCover {
            let regenerateAction = UIAction(
                title: String(localized: "Regenerate Cover"),
                image: UIImage(systemName: "arrow.triangle.2.circlepath"),
            ) { [weak self] _ in
                self?.regenerateCover()
            }
            children.append(regenerateAction)
        }

        return UIMenu(
            title: String(localized: "Cover"),
            image: UIImage(systemName: "photo.stack"),
            children: children,
        )
    }

    func buildDownloadSection() -> UIMenu? {
        guard let playlist, !playlist.songs.isEmpty, let environment else {
            return nil
        }

        let allDownloaded = playlist.songs.allSatisfy { environment.downloadStore.isDownloaded(trackID: $0.trackID) }
        let action = DownloadMenuProvider.downloadAllAction(
            allDownloaded: allDownloaded,
        ) { [weak self] in
            Task { await self?.downloadAllSongs() }
        }

        return MenuSectionProvider.inline([action])
    }

    var canPreviewCover: Bool {
        guard let playlist else {
            return false
        }
        return playlist.coverImageData != nil || !playlist.songs.isEmpty
    }

    var canRegenerateCover: Bool {
        guard let playlist, environment != nil else {
            return false
        }
        return playlist.coverImageData == nil && !playlist.songs.isEmpty
    }

    func regenerateCover() {
        guard let environment, let playlist, !playlist.songs.isEmpty else {
            return
        }

        headerCoverTask?.cancel()
        headerArtworkImage = nil
        reloadHeaderCell()

        headerCoverTask = Task { @MainActor [weak self, playlist] in
            guard let self else { return }

            await environment.playlistCoverArtworkCache.invalidateCache(for: playlist)

            guard let image = await generatedCoverImage(for: playlist, sideLength: 200, shuffled: true) else {
                return
            }

            guard !Task.isCancelled, playlistID == playlist.id else {
                return
            }

            headerArtworkImage = image
            reloadHeaderCell()
            AppLog.info(self, "regenerateCover completed playlistID=\(playlist.id)")
        }
    }

    func showCoverPreview() {
        guard let playlist else {
            return
        }

        if let coverData = playlist.coverImageData, let image = UIImage(data: coverData) {
            coverPreviewPresenter.present(image: image, fileName: "\(playlist.name) Cover")
            return
        }

        guard !playlist.songs.isEmpty else {
            return
        }

        Task { @MainActor [weak self, playlist] in
            guard let self else { return }
            guard let image = await generatedCoverImage(for: playlist, sideLength: 1200) else { return }

            guard !Task.isCancelled, playlistID == playlist.id else {
                return
            }

            coverPreviewPresenter.present(image: image, fileName: "\(playlist.name) Cover")
        }
    }
}
