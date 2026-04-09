import AmMusicDatabaseKit
import Foundation

extension MusicLibraryDatabase {
    func ingestAudioFile(url: URL, metadata: ImportedTrackMetadata) async throws -> AudioTrackRecord {
        let result = try await sendCommand(.ingestAudioFile(url: url, metadata: metadata))
        guard case let .ingestedTrack(record) = result else {
            throw NSError(domain: "MusicLibraryDatabase", code: 3)
        }
        return record
    }
}
