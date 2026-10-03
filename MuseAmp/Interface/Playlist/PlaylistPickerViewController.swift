//
//  PlaylistPickerViewController.swift
//  MuseAmp
//
//  Created by qaq on 2/7/2026.
//

import MuseAmpDatabaseKit
import UIKit

final class PlaylistPickerViewController: UIViewController {
    private let playlists: [Playlist]
    private let onPick: (Playlist) -> Void

    private let tableView = UITableView(frame: UIScreen.main.bounds, style: .insetGrouped)
    private lazy var dataSource = makeDataSource()

    init(title: String, playlists: [Playlist], onPick: @escaping (Playlist) -> Void) {
        self.playlists = playlists
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        self.title = title
        preferredContentSize = CGSize(width: 500, height: 500 - 44)
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
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            },
        )

        tableView.delegate = self
        tableView.register(
            PlaylistPickerCell.self,
            forCellReuseIdentifier: String(describing: PlaylistPickerCell.self),
        )
        view.addSubview(tableView)
        tableView.frame = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.backgroundColor = .clear
        tableView.applySoftEdgeEffects()

        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(playlists.map(\.id), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Int, UUID> {
        UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, playlistID in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: String(describing: PlaylistPickerCell.self),
                for: indexPath,
            )
            if let pickerCell = cell as? PlaylistPickerCell,
               let playlist = self?.playlists.first(where: { $0.id == playlistID })
            {
                pickerCell.configure(name: playlist.name, songCount: playlist.songs.count)
            }
            return cell
        }
    }
}

extension PlaylistPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let playlistID = dataSource.itemIdentifier(for: indexPath),
              let playlist = playlists.first(where: { $0.id == playlistID })
        else { return }
        let onPick = onPick
        dismiss(animated: true) {
            onPick(playlist)
        }
    }
}

private final class PlaylistPickerCell: TableBaseCell {
    func configure(name: String, songCount: Int) {
        var content = defaultContentConfiguration()
        content.text = name
        content.secondaryText = String(localized: "\(songCount) songs")
        content.image = UIImage(systemName: "music.note.list")
        contentConfiguration = content
    }
}
