public enum TransitionReason: Sendable {
    case natural
    case userNext
    case userPrevious
    case userSkip(toIndex: Int)
    case itemFailed
}
