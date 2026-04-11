//
//  NowPlayingLogSupport.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

func nowPlayingLogURLDescription(_ url: URL?) -> String {
    guard let url else {
        return "nil"
    }

    if url.isFileURL {
        return "file:\(url.lastPathComponent)"
    }

    let host = url.host ?? "remote"
    let pathComponent = url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    return "\(host)/\(pathComponent)"
}

func nowPlayingLogIndex(_ index: Int?) -> String {
    index.map(String.init) ?? "nil"
}

func nowPlayingLogTextSummary(_ text: String?) -> String {
    guard let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
          !normalizedText.isEmpty
    else {
        return "empty"
    }

    let lineCount = normalizedText.components(separatedBy: .newlines).count
    return "length=\(normalizedText.count) lines=\(lineCount)"
}
