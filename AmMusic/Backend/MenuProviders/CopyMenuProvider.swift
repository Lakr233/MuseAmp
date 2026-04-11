//
//  CopyMenuProvider.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

enum CopyMenuProvider {
    static func menu(children: [UIMenuElement]) -> UIMenu {
        UIMenu(
            title: String(localized: "Copy"),
            image: UIImage(systemName: "square.on.square"),
            children: children,
        )
    }

    static func albumMenu(
        albumName: String,
        artistName: String,
        songNames: [String] = [],
    ) -> UIMenu {
        let copyAlbumName = UIAction(
            title: String(localized: "Copy Album Name"),
            subtitle: albumName,
            image: UIImage(systemName: "square.on.square"),
        ) { _ in
            UIPasteboard.general.string = albumName
        }
        let copyArtistName = UIAction(
            title: String(localized: "Copy Artist Name"),
            subtitle: artistName,
            image: UIImage(systemName: "person.text.rectangle"),
        ) { _ in
            UIPasteboard.general.string = artistName
        }
        let copySongNames = UIAction(
            title: String(localized: "Copy All Song Names"),
            subtitle: songNames.first,
            image: UIImage(systemName: "textformat"),
        ) { _ in
            UIPasteboard.general.string = songNames.joined(separator: "\n")
        }
        var children: [UIMenuElement] = [copyAlbumName, copyArtistName]
        children.append(copySongNames)
        return menu(children: children)
    }
}
