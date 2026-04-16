//
//  ArtistDetailViewController+Table.swift
//  MuseAmp
//
//  Created by @libr on 2026/04/16.
//

import SubsonicClientKit
import UIKit

extension ArtistDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .header, .loading:
            return
        case let .song(id):
            playSong(id: id)
        case .songsShowMore:
            showMoreSongs()
        case let .album(id):
            guard let album = albumsByID[id] else { return }
            albumNavigationHelper.pushAlbumDetail(album: album)
        case .albumsShowMore:
            showMoreAlbums()
        }
    }

    func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return false }
        switch item {
        case .header, .loading:
            return false
        case .song, .songsShowMore, .album, .albumsShowMore:
            return true
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard dataSource.snapshot().sectionIdentifiers.indices.contains(section) else {
            return nil
        }

        let title: String
        switch dataSource.snapshot().sectionIdentifiers[section] {
        case .header:
            return nil
        case .songs:
            title = SearchType.song.title
        case .albums:
            title = SearchType.album.title
        }

        let headerView = tableView.dequeueReusableHeaderFooterView(
            withIdentifier: SearchSectionHeaderView.reuseID,
        ) as! SearchSectionHeaderView
        headerView.configure(title: title)
        return headerView
    }

    func tableView(_: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard dataSource.snapshot().sectionIdentifiers.indices.contains(section) else {
            return .leastNonzeroMagnitude
        }

        switch dataSource.snapshot().sectionIdentifiers[section] {
        case .header:
            return .leastNonzeroMagnitude
        case .songs, .albums:
            return UITableView.automaticDimension
        }
    }

    func tableView(_: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        guard dataSource.snapshot().sectionIdentifiers.indices.contains(section) else {
            return .leastNonzeroMagnitude
        }

        switch dataSource.snapshot().sectionIdentifiers[section] {
        case .header:
            return .leastNonzeroMagnitude
        case .songs, .albums:
            return 44
        }
    }
}
