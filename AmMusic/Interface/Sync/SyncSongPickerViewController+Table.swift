//
//  SyncSongPickerViewController+Table.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

extension SyncSongPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let trackID = dataSource.itemIdentifier(for: indexPath) else {
            return
        }

        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
        } else {
            selectedTrackIDs.insert(trackID)
        }
        applySnapshot()
    }
}
