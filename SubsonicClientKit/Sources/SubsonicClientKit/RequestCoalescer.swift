//
//  RequestCoalescer.swift
//  SubsonicClientKit
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
            let result = await existing.result
            try Task.checkCancellation()
            return try result.get()
        }

        let task = Task.detached { try await work() }
        inFlight[key] = task
        let result = await task.result
        inFlight[key] = nil
        try Task.checkCancellation()
        return try result.get()
    }
}
