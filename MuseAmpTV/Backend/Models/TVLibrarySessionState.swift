import Foundation

enum AMTVLibrarySessionState: Equatable {
    case awaitingUpload
    case receivingTracks
    case playing
    case failed(message: String)

    var rootFlowState: AMTVRootFlowState {
        switch self {
        case .awaitingUpload: .awaitingUpload
        case .receivingTracks: .receivingTracks
        case .playing: .playing
        case .failed: .failed
        }
    }
}
