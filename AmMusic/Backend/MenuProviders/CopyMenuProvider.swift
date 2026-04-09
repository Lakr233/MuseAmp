import UIKit

enum CopyMenuProvider {
    static func menu(children: [UIMenuElement]) -> UIMenu {
        UIMenu(
            title: String(localized: "Copy"),
            image: UIImage(systemName: "square.on.square"),
            children: children
        )
    }

    static func albumMenu(
        albumName: String,
        artistName: String,
        songNames: [String] = []
    ) -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(
                title: String(localized: "Copy Album Name"),
                image: UIImage(systemName: "square.on.square")
            ) { _ in
                UIPasteboard.general.string = albumName
            },
            UIAction(
                title: String(localized: "Copy Artist Name"),
                image: UIImage(systemName: "person.text.rectangle")
            ) { _ in
                UIPasteboard.general.string = artistName
            },
        ]
        children.append(UIAction(
            title: String(localized: "Copy All Song Names"),
            image: UIImage(systemName: "textformat")
        ) { _ in
            UIPasteboard.general.string = songNames.joined(separator: "\n")
        })
        return menu(children: children)
    }
}
