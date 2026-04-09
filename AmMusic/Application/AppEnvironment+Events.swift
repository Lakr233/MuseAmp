import AmMusicDatabaseKit
import Combine
import Foundation

extension AppEnvironment {
    func observeDatabaseEvents() {
        databaseEventCancellable = databaseManager.events
            .receive(on: DispatchQueue.main)
            .sink { event in
                self.handleDatabaseEvent(event)
            }
    }

    func handleDatabaseEvent(_ event: LibraryEvent) {
        switch event {
        case .indexRebuildFinished, .tracksChanged:
            NotificationCenter.default.post(name: .libraryDidSync, object: nil)
        case let .artworkCacheChanged(trackIDs):
            NotificationCenter.default.post(
                name: .artworkDidUpdate,
                object: nil,
                userInfo: [AppNotificationUserInfoKey.trackIDs: Array(trackIDs)]
            )
        default:
            break
        }
    }
}
