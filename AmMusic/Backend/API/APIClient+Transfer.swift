//
//  APIClient+Transfer.swift
//  AmMusic
//
//  Created by @Lakr233 on 2026/04/11.
//

import Foundation

extension APIClient {
    nonisolated func authenticateTransfer(
        endpoint: SyncEndpoint,
        password: String,
    ) async throws -> String {
        AppLog.verbose(self, "authenticateTransfer endpoint=\(endpoint.displayString)")
        let requestBody = SyncAuthRequest(password: password)
        let request = try makeTransferRequest(
            endpoint: endpoint,
            path: "/auth",
            method: "POST",
            token: nil,
            body: requestBody,
        )

        do {
            let (data, response) = try await performRequest(for: request)
            let httpResponse = try requireTransferHTTPResponse(response, data: data)
            let authResponse = try JSONDecoder().decode(SyncAuthResponse.self, from: data)
            guard httpResponse.statusCode == 200,
                  authResponse.success
            else {
                AppLog.error(self, "authenticateTransfer failed endpoint=\(endpoint.displayString) status=\(httpResponse.statusCode)")
                throw SyncTransferError.httpFailure(httpResponse.statusCode, authResponse.message)
            }
            guard let token = authResponse.token, !token.isEmpty else {
                AppLog.error(self, "authenticateTransfer missing token endpoint=\(endpoint.displayString)")
                throw SyncTransferError.missingAuthToken
            }
            AppLog.info(self, "authenticateTransfer succeeded endpoint=\(endpoint.displayString)")
            return token
        } catch {
            AppLog.error(self, "authenticateTransfer failed endpoint=\(endpoint.displayString) error=\(error.localizedDescription)")
            throw error
        }
    }

    nonisolated func fetchTransferManifest(
        endpoint: SyncEndpoint,
        token: String,
    ) async throws -> SyncManifest {
        AppLog.verbose(self, "fetchTransferManifest endpoint=\(endpoint.displayString)")
        let request = try makeTransferRequest(
            endpoint: endpoint,
            path: "/manifest",
            method: "GET",
            token: token,
            body: String?.none,
        )

        do {
            let (data, response) = try await performRequest(for: request)
            let httpResponse = try requireTransferHTTPResponse(response, data: data)
            guard httpResponse.statusCode == 200 else {
                AppLog.error(self, "fetchTransferManifest failed endpoint=\(endpoint.displayString) status=\(httpResponse.statusCode)")
                throw SyncTransferError.httpFailure(httpResponse.statusCode, String(data: data, encoding: .utf8))
            }
            let manifest = try JSONDecoder().decode(SyncManifest.self, from: data)
            AppLog.info(self, "fetchTransferManifest succeeded endpoint=\(endpoint.displayString) entries=\(manifest.entries.count)")
            return manifest
        } catch {
            AppLog.error(self, "fetchTransferManifest failed endpoint=\(endpoint.displayString) error=\(error.localizedDescription)")
            throw error
        }
    }

    nonisolated func downloadTransferTrack(
        endpoint: SyncEndpoint,
        token: String,
        entry: SyncManifestEntry,
        to destinationURL: URL,
        progress: (@MainActor (_ fractionCompleted: Double) -> Void)? = nil,
    ) async throws -> URL {
        AppLog.verbose(
            self,
            "downloadTransferTrack endpoint=\(endpoint.displayString) trackID=\(entry.trackID) size=\(entry.fileSizeBytes)",
        )
        let request = try makeTransferRequest(
            endpoint: endpoint,
            path: "/track/\(entry.trackID)",
            method: "GET",
            token: token,
            body: String?.none,
        )

        do {
            let parentDirectoryURL = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parentDirectoryURL,
                withIntermediateDirectories: true,
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)

            let (data, response) = try await performRequest(for: request)
            let httpResponse = try requireTransferHTTPResponse(response, data: data)
            guard httpResponse.statusCode == 200 else {
                AppLog.error(self, "downloadTransferTrack failed trackID=\(entry.trackID) status=\(httpResponse.statusCode)")
                throw SyncTransferError.httpFailure(
                    httpResponse.statusCode,
                    String(data: data, encoding: .utf8),
                )
            }

            try data.write(to: destinationURL)
            let receivedBytes = Int64(data.count)

            await progress?(1)
            AppLog.info(self, "downloadTransferTrack succeeded trackID=\(entry.trackID) bytes=\(receivedBytes)")
            return destinationURL
        } catch {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            AppLog.error(self, "downloadTransferTrack failed trackID=\(entry.trackID) error=\(error.localizedDescription)")
            throw error
        }
    }
}

private extension APIClient {
    nonisolated func makeTransferRequest(
        endpoint: SyncEndpoint,
        path: String,
        method: String,
        token: String?,
        body: (some Encodable)?,
    ) throws -> URLRequest {
        guard let url = endpoint.url(path: path) else {
            throw SyncTransferError.invalidServerResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    nonisolated func requireTransferHTTPResponse(
        _ response: URLResponse,
        data: Data?,
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            if let data, !data.isEmpty {
                AppLog.error(self, "requireTransferHTTPResponse invalid response body=\(sanitizedLogText(String(data: data, encoding: .utf8) ?? "", maxLength: 120))")
            } else {
                AppLog.error(self, "requireTransferHTTPResponse invalid non-HTTP response")
            }
            throw SyncTransferError.invalidServerResponse
        }
        return httpResponse
    }
}
