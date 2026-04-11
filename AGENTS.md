# Project Overview

## App Shape

- This is a pure UIKit iOS app with programmatic setup.
- Do not introduce SwiftUI for new UI work; all new screens, components, and overlays must use UIKit.
- App entry remains `AmMusic/main.swift` -> `Application/AppDelegate.swift` -> `Application/SceneDelegate.swift`.
- `Interface/Root/BootProgressController.swift` owns the blocking local-library boot handoff before the main tab shell is shown.
- `Interface/Root/TabBarController.swift` owns the shared `AppEnvironment` reference for the root tab shell.
- Root navigation currently has 4 first-level UIKit tabs: `Library`, `Playlist`, `Settings`, and `Search`.
- `Now Playing` is presented through `LNPopupController`, not as a first-level tab.

## Structure Rules

### Top Level

- `AmMusic/` contains the app target source and resources.
- `AmMusicDatabaseKit/` is the local library runtime package for file-backed library indexing, state, caches, downloads, playlists, and audit data.
- `AmMusicKit/` is a separate package for remote music service integration.
- `AmMusicPlayerKit/` is a separate package for playback engine integration.

### Application Layer

- `Application/` contains only app lifecycle and configuration: `AppDelegate.swift`, `SceneDelegate.swift`, `AppEnvironment.swift`, `AppEnvironment+Bootstrap.swift`, `AppEnvironment+Events.swift`, `AppPreferences.swift`.
- `Configuration/` contains Xcode build configuration files (`Base.xcconfig`, `Development.xcconfig`, `Release.xcconfig`, `Version.xcconfig`).
- All domain logic lives under `Backend/`, not `Application/`.

### Backend Layer

- `Backend/API/`: `APIClient` and intent-level network entry points.
- `Backend/Downloads/`: download orchestration plus persisted download records.
- `Backend/Library/`: local and remote library data providers that bridge app services into browseable media collections.
- `Backend/Logging/`: file-backed logging and log reading. Extend this instead of adding a second diagnostics path.
- `Backend/Lyrics/`: lyrics fetching, parsing, and Chinese script conversion.
- `Backend/MenuProviders/`: shared UIKit menu and action provider helpers used by feature controllers. Also contains `SongExportItem` (data model for export).
- `Backend/Models/`: app-facing media models and adapter types used by the interface layer.
- `Backend/Playback/`: playback state ownership, playback domain models, and the shared `PlaybackController` bridge to `AmMusicPlayerKit`.
- `Backend/Playlist/`: playlist CRUD, persistence, artwork generation, and `PlaylistCoverArtworkCache`.
- `Backend/Supplement/`: cross-cutting utilities (metadata helpers, string sanitization, file name formatting).

### Interface Layer

- `Interface/Root/`: app shell hosting and root composition.
- `Interface/Root/BootProgressController.swift`: blocking library boot controller that initializes the local runtime before presenting the tab shell.
- `Interface/Common/`: shared loading, error, and infrastructure UI.
- `Interface/Collections/`: reusable album and track presentation components.
- `Interface/Common/SongExportPresenter.swift`: UI presenter for sharing/exporting songs (split from `Backend/MenuProviders/`).
- `Interface/Library/`, `Search/`, `AlbumDetail/`, `NowPlaying/`, `Downloads/`, `Playlist/`, `Settings/`: feature-owned UI.
- `Interface/NowPlaying/Controller/`: main view controller and its responsibility-based extensions.
- `Interface/NowPlaying/ViewModel/`: view models for now playing state presentation.
- `Interface/NowPlaying/Sections/`: section views composing the now playing pages (avatar, center, list, lyric, transport).
- `Interface/NowPlaying/Components/`: reusable views and cells within now playing (LyricTimelineView, artwork background, queue cells, route picker).
- `Interface/NowPlaying/LyricSheet/`: lyric selection sheet controller.
- `Interface/NowPlaying/Support/`: logging and diagnostics helpers.

### Extension Layer

- `Extension/`: extensions on system/Apple framework types (UIColor, UIView, UITableView, Bundle, etc.), named `Extension+ClassName.swift`.

### General

- Keep UI state rendering in feature folders, but keep state ownership in `Backend/`.
- Package-localized resources belong under `Sources/<Target>/Resources/` inside each Swift package and must be read with `String(localized: ..., bundle: .module)`.

### Album Menu Rules

- Album detail nav bar menus should be all-English and grouped in this order: download status first, playlist actions second, copy actions last.
- Album detail copy actions should be grouped under `Copy` and include `Copy Album Name`, `Copy Artist Name`, and `Copy All Song Names`.
- Album detail download action should be titled `Download All Songs`.
- If every album track is already downloaded, replace the album detail download action with a disabled `All Downloaded` action.
- Album detail `Save to Playlist` means adding the album tracks to an existing playlist. Its flow should be `Save to Playlist` -> `Add to Playlist` -> existing playlist choices, and it should only appear when at least one playlist exists.
- Album detail `Save as Playlist` means creating a new playlist from the whole album, using the album name as the playlist name, then adding every album track to it.
- Treat `Save to Playlist` and `Save as Playlist` as completely different actions. Do not use `Save as Playlist` for adding album tracks to an existing playlist, and do not use `Save to Playlist` for creating a playlist.
- Do not show `New Playlist…` or any create-playlist action inside the Album detail nav bar `Save to Playlist` flow.
- Playlist menu actions that depend on loaded album tracks must fetch the current songs at action time, not capture the track list when the menu is first created.
- If playlist creation is offered in other screens, creating a playlist and then adding songs must continue the original add/save flow after creation.

## Placement Guide

- New app services belong under the closest `Backend/*` subdomain, not directly under `Backend/`.
- New network calls must extend `APIClient`; UI controllers must not construct raw endpoints.
- New persisted download data must continue to flow through `DownloadStore`; do not add a second store for the same records.
- New playback state and queue mutations must continue to flow through `PlaybackController`; mini player and now playing screens observe it.
- `PlaybackController` is responsible for local-vs-remote playback URL resolution, `MusicPlayerDelegate` bridging, and app-facing playback snapshots.
- New tab-level or browse-level features should usually get a new folder under `AmMusic/Interface/`.
- Shared UI goes into `Interface/Common/` or `Interface/Collections/` only when it is used by more than one feature or is clearly cross-feature infrastructure.
- Shared UIKit menu and action providers belong under `Backend/MenuProviders/`.
- If a UI type is only used by one feature, keep it inside that feature folder even if it looks reusable.

## Dependency Rules

- Thread shared dependencies through `AppEnvironment`.
- Do not introduce new singletons for feature work.
- `APIClient` is the only app-level network orchestration entry point.
- UI code must not depend directly on `RemoteMusicService`.
- Settings flags go through `AppPreferences` and `ConfigurableKit`, not scattered `UserDefaults` keys.

## UIKit File Rules

- Keep `main.swift` as the entry point. Do not switch to `@main`.
- No `Main.storyboard`; keep only `LaunchScreen.storyboard` under `AmMusic/Resources/`.
- Keep Xcode groups aligned with on-disk folders.
- Split large controllers using `XxxViewController.swift` plus focused `XxxViewController+Layout.swift`, `+Actions.swift`, `+Table.swift`, `+Search.swift`, or similar responsibility-based extensions.
- Split by responsibility, not by arbitrary line count.

## Logging Rules

- All diagnostic output **must** go through `AppLog` (`AmMusic/Backend/Logging/AppLog.swift`), which wraps Dog. Never use `print()`, `NSLog()`, `os_log`, or `debugPrint()` in app code.
- Every `catch` block or `try?` that silently swallows an error must log via `AppLog.error` or `AppLog.warning` before returning/continuing.
- Network requests (`APIClient` methods) must log at `.verbose` on entry and `.info` on success with key result metrics, and `.error` on failure.
- File I/O operations (reads, writes, deletes) in persistence stores must log failures via `AppLog.error` and optionally log success at `.verbose`.
- State transitions in core services (playback, downloads) should log at `.info`.
- Do not log sensitive data (tokens, full URLs with auth params). Redact or omit.

## API Verification

- When using iOS/macOS APIs that are new, recently changed, or unfamiliar, search Apple Developer Documentation (via the Apple-docs MCP tools) before writing the code.
- Verify availability annotations, parameter signatures, and deprecation status against the official docs rather than relying on memory alone.

## Code Style

- Indentation: 4 spaces.
- Use early returns and `guard` to reduce nesting.
- Prefer value types over reference types unless identity or UIKit lifecycle requires a class.
- Prefer dependency injection and composition over inheritance and singleton access.
- Use Swift concurrency features where they fit the existing design.
- Keep comments rare and only where they remove real ambiguity.

## Property Rules

- Avoid unnecessary optionals. If a property can have a meaningful default value, use it instead of making the property optional.
- Combine subscriptions must be stored in a single `var cancellables: Set<AnyCancellable> = []` per class, using `.store(in: &cancellables)`. Do not create individual `AnyCancellable?` properties for each subscription.
- Callback closures that are always assigned before use should be non-optional with an empty default (e.g., `var onTap: () -> Void = {}`), not `(() -> Void)?`. Remove optional chaining (`?()`) at call sites.
- For throttle/cooldown dates, use `Date = .distantPast` instead of `Date?`. Check with `Date() < deadline` instead of unwrapping.
- For enum state properties, prefer a concrete default case (e.g., `.idle`) over making the property optional.
- Properties whose values can be derived from other state should be computed properties, not stored.
- Do not introduce stored properties to track state that is already available from an existing source of truth.

## Testing Rules

- The project has a macOS Catalyst destination. Tests can be built and run on Catalyst (`My Mac (Mac Catalyst)`) in addition to iOS simulators.
- Prefer behavior-focused tests over UI-structure tests.
- New tests should validate application logic, persistence, notifications, file processing, and service behavior without depending on view titles, tab counts/order, selected tabs, or other presentation-only details.
- Avoid assertions such as `.title == ...`, `tabs.count == ...`, or similar checks that only verify UIKit configuration text or shell layout.
- When testing UI-adjacent code, prefer asserting observable side effects or state changes rather than labels, tab wiring, or navigation chrome.

## Preferred Libraries

- Use `Kingfisher` for remote artwork loading and caching.
- Use `LRUCache` for bounded in-memory caches.
- Use `ConfigurableKit` for settings and debug pages.
- Use `Logger` (Dog) for diagnostics and log viewing.
- Use `SnapKit`, `Then` (includes `.with {}`) only when they reduce boilerplate without obscuring layout code.
- Use `SwifterSwift` for common Swift/UIKit extensions.
- Use `AlertController` for styled alerts, input prompts, and progress indicators.

## AlertController Rules

- Single-button alerts: the action must always use `attribute: .accent`.
- Multi-button alerts: exactly one action should use `attribute: .accent`, preferably the rightmost one.

## Documentation Sync

- Any structural directory change must update this `AGENTS.md` in the same change.
- If a new subdomain is introduced under `Application/` or `Interface/`, document its scope and placement rules immediately.

---

# Package Reference

## Local Packages

### AmMusicDatabaseKit

- **Path:** `AmMusicDatabaseKit/`
- **Import:** `import AmMusicDatabaseKit`
- **What:** Local library runtime — owns local index/state databases, file lifecycle, cache paths, playlists, downloads, and audit models behind `DatabaseManager`.
- **Key types:** `DatabaseManager`, `LibraryCommand`, `LibraryCommandResult`, `LibraryEvent`, `AudioTrackRecord`, `Playlist`, `DownloadJob`, `AuditSnapshot`
- **Layout:** keep the runtime split by responsibility across `DatabaseManager.swift` and `DatabaseManager+Scope.swift` files rather than regrowing one large implementation file.

### AmMusicKit

- **Path:** `AmMusicKit/`
- **Import:** `import AmMusicKit`
- **What:** Remote music catalog service — search, album/artist/song lookup, storefronts.
- **Key type:** `RemoteMusicService(baseURL:)` with async methods: `search(query:type:limit:offset:)`, `album(id:)`, `artist(id:)`, `song(id:)`.
- **Models:** `CatalogSong`, `CatalogAlbum`, `CatalogArtist`, `Artwork` (with `imageURL(width:height:)`).

### AmMusicPlayerKit

- **Path:** `AmMusicPlayerKit/`
- **Import:** `import AmMusicPlayerKit`
- **What:** Queue-based audio playback with delegate callbacks, lock screen / Control Center integration, and shuffle/repeat modes.
- **Core type:** `MusicPlayer` (`@MainActor final class`)

#### MusicPlayer API

```
// Lifecycle
init()
weak var delegate: (any MusicPlayerDelegate)?

// Properties
var state: PlaybackState              // .idle | .playing | .paused | .buffering | .error(String)
var currentItem: PlayerItem?
var currentTime: TimeInterval
var duration: TimeInterval
var queue: QueueSnapshot              // .history, .nowPlaying, .upcoming, .shuffled, .repeatMode
var shuffled: Bool { get set }
var repeatMode: RepeatMode { get set } // .off | .track | .queue
var timeUpdateInterval: TimeInterval   // default 0.25s

// Playback control
func startPlayback(items: [PlayerItem], startIndex: Int = 0, shuffle: Bool = false)
func play()
func pause()
func togglePlayPause()
func stop()
func seek(to seconds: TimeInterval) async

// Navigation
func next()
func previous()                       // restarts if currentTime > 3s
func skip(to index: Int)              // index into upcoming items
func skipToQueueIndex(_ index: Int)   // absolute index into ordered queue
func skipCurrentItem()                // alias for next()

// Queue editing
func playNext(_ item: PlayerItem)
func playNext(_ items: [PlayerItem])
func addToQueue(_ item: PlayerItem)
func addToQueue(_ items: [PlayerItem])
func insertInQueue(_ item: PlayerItem, at index: Int)
func removeFromQueue(at index: Int) -> PlayerItem?
func removeFromQueue(id: String)
func moveInQueue(from source: Int, to destination: Int)
func clearUpcomingQueue()
func replaceUpcomingQueue(_ items: [PlayerItem])
func replaceQueue(items: [PlayerItem], startIndex: Int = 0)

// Restoration
func restorePlayback(
    items: [PlayerItem], currentIndex: Int, shuffled: Bool,
    repeatMode: RepeatMode, currentTime: TimeInterval, autoPlay: Bool
) async -> Bool

// Media Center
func configureLikeCommand(title: String?, shortTitle: String?, handler: (() -> Bool)?)
func updateNowPlayingSubtitle(_ text: String?)
func setCurrentItemLiked(_ isLiked: Bool)
func setPeriodicTimeObserverSuspended(_ suspended: Bool)
```

#### MusicPlayerDelegate

```
func musicPlayer(_ player: MusicPlayer, didChangeState state: PlaybackState)
func musicPlayer(_ player: MusicPlayer, didTransitionTo item: PlayerItem?, reason: TransitionReason)
func musicPlayer(_ player: MusicPlayer, didChangeQueue snapshot: QueueSnapshot)
func musicPlayer(_ player: MusicPlayer, didUpdateTime currentTime: TimeInterval, duration: TimeInterval)
func musicPlayer(_ player: MusicPlayer, didFailItem item: PlayerItem, error: any Error)
func musicPlayerDidReachEndOfQueue(_ player: MusicPlayer)
```

#### PlayerItem

```
struct PlayerItem: Sendable, Hashable, Identifiable {
    let id: String
    let url: URL
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let durationInSeconds: TimeInterval?
}
```

#### Supporting Types

- `PlaybackState` — `.idle`, `.playing`, `.paused`, `.buffering`, `.error(String)`; `.isActive` computed property.
- `RepeatMode` — `.off`, `.track`, `.queue` (CaseIterable).
- `TransitionReason` — `.natural`, `.userNext`, `.userPrevious`, `.userSkip(toIndex:)`, `.itemFailed`.
- `QueueSnapshot` — `.history`, `.nowPlaying`, `.upcoming`, `.shuffled`, `.repeatMode`, `.totalCount`.

---

## Remote Packages

### Kingfisher 8.x

- **URL:** `https://github.com/onevcat/Kingfisher.git` (>= 8.0.0)
- **Import:** `import Kingfisher`
- **What:** Async image downloading + multi-layer memory/disk caching.

#### UIKit (primary usage in this project)

```swift
imageView.kf.setImage(
    with: url,
    placeholder: UIImage(systemName: "music.note"),
    options: [.transition(.fade(0.2)), .cacheOriginalImage]
)
imageView.kf.cancelDownloadTask()
```

#### SwiftUI

```swift
KFImage(url)
    .placeholder { ProgressView() }
    .resizable()
    .cancelOnDisappear(true)
```

#### Cache control

```swift
let cache = ImageCache.default
cache.memoryStorage.config.totalCostLimit = 300 * 1024 * 1024
cache.diskStorage.config.sizeLimit = 1_000 * 1024 * 1024
cache.diskStorage.config.expiration = .days(7)
cache.clearMemoryCache()
cache.clearDiskCache()
```

#### KingfisherManager (for non-UIImageView targets)

```swift
KingfisherManager.shared.retrieveImage(with: url) { result in
    if case .success(let value) = result { /* value.image */ }
}
```

#### Key options

`.transition(.fade(_))`, `.processor(DownsamplingImageProcessor(size:))`, `.cacheOriginalImage`, `.forceRefresh`, `.onlyFromCache`.

#### Built-in processors

`DownsamplingImageProcessor`, `RoundCornerImageProcessor`, `BlurImageProcessor`, `CroppingImageProcessor`, `ResizingImageProcessor`. Chain with `|>`.

---

### AlertController

- **URL:** `https://github.com/Lakr233/AlertController.git` (>= 1.0.0)
- **Import:** `import AlertController`
- **What:** Styled drop-in replacement for `UIAlertController` with spring animations.

#### Standard alert

```swift
let alert = AlertViewController(title: "Title", message: "Body") { context in
    context.addAction(title: "Cancel") { context.dispose() }
    context.addAction(title: "Delete", attribute: .accent) {
        context.dispose { /* post-dismiss */ }
    }
}
present(alert, animated: true)
```

#### Text input alert

```swift
let alert = AlertInputViewController(
    title: "Rename", message: "Enter a new name.",
    placeholder: "Name...", text: ""
) { text in print(text) }
present(alert, animated: true)
```

#### Progress alert

```swift
let alert = AlertProgressIndicatorViewController(title: "Loading", message: "Please wait...")
present(alert, animated: true)
// later: alert.dismiss(animated: true)
```

#### Global config

```swift
AlertControllerConfiguration.accentColor = .systemBlue
AlertControllerConfiguration.alertImage = UIImage(named: "AppIcon")
```

---

### SwifterSwift

- **URL:** `https://github.com/SwifterSwift/SwifterSwift.git` (>= 7.0.0)
- **Import:** `import SwifterSwift` (umbrella) or individual: `SwifterSwiftSwiftStdlib`, `SwifterSwiftFoundation`, `SwifterSwiftUIKit`
- **What:** 500+ native Swift extensions for stdlib, Foundation, UIKit, CoreGraphics, CoreAnimation, Dispatch.

#### Highlights for this project

- **String:** `.trimmed`, `.isValidURL`, safe subscript by index/range, `.localized(comment:)`
- **Array:** `.withoutDuplicates()`, `.removeDuplicates()`, `.sorted(like:keyPath:)`
- **Sequence:** `.sorted(by:keyPath)`, `.reject(where:)`, `.divided(by:)`, `.sum(for:)`
- **Collection:** `[safe: index]` safe subscript, `.group(by:)` chunking
- **Optional:** `.unwrapped(or:)`, `.isNilOrEmpty`
- **Date:** `.year`, `.month`, `.day`, `.isInToday`, `.isInFuture`, `.iso8601String`
- **UIView:** `.addSubviews(_:)`, `.fadeIn()`, `.fadeOut()`, `.addShadow(ofColor:radius:offset:opacity:)`, `.parentViewController`
- **UIImage:** `.compressed(quality:)`, `.scaled(toWidth:)`, `.cropped(to:)`, `.averageColor()`
- **UITableView:** `.register(cellWithClass:)`, `.dequeueReusableCell(withClass:for:)`

---

### SnapKit

- **URL:** `https://github.com/SnapKit/SnapKit.git` (>= 5.7.0)
- **Import:** `import SnapKit`
- **What:** Chainable Auto Layout DSL.

#### Core API

```swift
view.snp.makeConstraints { make in
    make.edges.equalToSuperview().inset(16)
}
view.snp.updateConstraints { make in   // update constants only
    make.height.equalTo(200)
}
view.snp.remakeConstraints { make in   // remove + recreate
    make.center.equalToSuperview()
}
```

#### Attributes

- Single: `left`, `right`, `top`, `bottom`, `leading`, `trailing`, `width`, `height`, `centerX`, `centerY`
- Composite: `edges`, `size`, `center`, `horizontalEdges`, `verticalEdges`

#### Modifiers

- `.offset(value)` — constant offset
- `.inset(value)` — inward insets (CGFloat, UIEdgeInsets, NSDirectionalEdgeInsets)
- `.multipliedBy(factor)` — proportional sizing
- `.priority(.required | .high | .medium | .low)` — layout priority
- `.labeled(name)` — debug label

---

### Then

- **URL:** `https://github.com/devxoul/Then.git` (>= 3.0.0)
- **Import:** `import Then`
- **What:** Syntactic sugar for object init/config via trailing closures. Includes `.with {}` (no separate "With" package).

#### API

```swift
// .then — configure reference types inline (NSObject subclasses)
let label = UILabel().then {
    $0.textAlignment = .center
    $0.textColor = .black
    $0.text = "Hello"
}

// .with — copy-and-modify value types
let frame = oldFrame.with { $0.size.width = 200 }

// .do — side effects, returns Void
UserDefaults.standard.do {
    $0.set("value", forKey: "key")
}
```

- All `NSObject` subclasses conform automatically.
- Custom types: `extension MyType: Then {}`

---

### LRUCache

- **URL:** `https://github.com/nicklockwood/LRUCache` (>= 1.0.0)
- **Import:** `import LRUCache`
- **What:** Thread-safe LRU cache replacing `NSCache` with predictable eviction. Auto-clears on memory warning.

```swift
let cache = LRUCache<String, UIImage>(countLimit: 100, totalCostLimit: 50 * 1024 * 1024)
cache.setValue(image, forKey: key, cost: dataSize)
let image = cache.value(forKey: key)
cache.removeValue(forKey: key)
cache.removeAll()
```

---

### ConfigurableKit

- **URL:** `https://github.com/Lakr233/ConfigurableKit` (>= 1.0.0)
- **Import:** `import ConfigurableKit`
- **What:** Declarative UIKit settings page builder synced to UserDefaults.

#### Key types

- `ConfigurableObject` — settings item (icon, title, explain, key, defaultValue, annotation)
- `ConfigurableManifest` — group container with title/footer
- `ConfigurableViewController` / `ConfigurableSheetController` — presentation
- Annotations: `.boolean`, `.slider`, `.picker`, etc.
- `whenValueChange(type:)` — observe setting changes
- `ConfigurableKit.storage` — swap in custom `KeyValueStorage`

---

### Dog (Logger)

- **URL:** `https://github.com/Lakr233/Dog` (branch: `main`)
- **Import:** `import Dog`
- **What:** File-backed persistent logging with log retrieval for in-app viewer.

```swift
Dog.shared.initialization(writableDir: logsDir)
Dog.shared.join(self, "message", level: .info)   // .verbose | .info | .warning | .error | .critical
let content = Dog.shared.obtainCurrentLogContent()
let paths = Dog.shared.obtainAllLogFilePath()
```
