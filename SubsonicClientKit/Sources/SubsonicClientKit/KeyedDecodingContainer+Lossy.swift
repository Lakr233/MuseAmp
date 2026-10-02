//
//  KeyedDecodingContainer+Lossy.swift
//  SubsonicClientKit
//
//  Created by @Lakr233 on 2026/04/14.
//

import Foundation

extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "Missing string-compatible value"))
    }

    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeLossyInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }
}
