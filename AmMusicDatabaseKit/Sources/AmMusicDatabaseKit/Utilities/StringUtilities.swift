//
//  StringUtilities.swift
//  AmMusicDatabaseKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

public extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public extension String? {
    var nilIfEmpty: String? {
        self?.nilIfEmpty
    }
}

public func sanitizePathComponent(_ component: String) -> String {
    let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return "unknown"
    }

    let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        .union(.newlines)
        .union(.illegalCharacters)
        .union(.controlCharacters)
    let sanitizedScalars = trimmed.unicodeScalars.map { scalar -> Character in
        invalidCharacters.contains(scalar) ? "_" : Character(scalar)
    }
    let sanitized = String(sanitizedScalars)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "..", with: "_")
    return sanitized.isEmpty ? "unknown" : sanitized
}

public func sanitizeDisplayFileName(_ value: String, fallback: String = "") -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        .union(.newlines)
        .union(.controlCharacters)
    let sanitized = value
        .components(separatedBy: invalidCharacters)
        .joined(separator: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? fallback : sanitized
}
