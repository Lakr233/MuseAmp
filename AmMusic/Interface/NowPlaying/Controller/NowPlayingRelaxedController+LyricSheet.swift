//
//  NowPlayingRelaxedController+LyricSheet.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import UIKit

extension NowPlayingRelaxedController {
    func presentLyricSelectionSheet(with lyrics: [String], activeIndex: Int?) {
        guard !lyrics.isEmpty,
              presentedViewController == nil
        else {
            return
        }

        let controller = LyricSelectionSheetViewController(lyrics: lyrics, activeIndex: activeIndex)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .formSheet

        if let sheetPresentationController = navigationController.sheetPresentationController {
            sheetPresentationController.prefersGrabberVisible = true
        }

        present(navigationController, animated: true)
    }
}
