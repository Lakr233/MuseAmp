//
//  RequestCoalescer.swift
//  AmMusicKit
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

actor RequestCoalescer {
    private var inFlight: [String: Task<Data, Error>] = [:]

    func perform(
        forKey key: String,
        work: @escaping @Sendable () async throws -> Data,
    ) async throws -> Data {
        if let existing = inFlight[key] {
            do {
                let result = try await existing.value
                try Task.checkCancellation()
                return result
            } catch {
                try Task.checkCancellation()
                throw error
            }
        }

        let task = Task.detached { try await work() }
        inFlight[key] = task
        do {
            let result = try await task.value
            inFlight[key] = nil
            try Task.checkCancellation()
            return result
        } catch {
            inFlight[key] = nil
            try Task.checkCancellation()
            throw error
        }
    }
}
