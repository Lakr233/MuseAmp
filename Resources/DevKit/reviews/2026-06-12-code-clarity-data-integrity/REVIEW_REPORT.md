# MuseAmp 全量 Review 报告

多智能体编排：loop-until-dry，13 个 code-clarity scope + 9 个数据完整性维度 + 2 个横切审查，每条发现经对抗验证（clarity = refute + AGENTS.md 约定检查；integrity = correctness-trace + impact 双票全过才确认）。

- 总计 surfaced: 413，**confirmed: 183**，refuted: 13
- 轮次: 3（结束时 dry streak 2）。注意：因 session 限额与 agent 配额触顶，约 200 条 surfaced 发现未完成验证即被丢弃，r2/r3 增量轮与 completeness critic 未完成 —— 本报告覆盖的是已完成对抗验证的 183 条。

严重度: high=4 / medium=67 / low=112；类型: integrity=0 / clarity=183

## 目录（按 scope）

- clarity / **app-shell** — 29 条
- clarity / **backend-api-library** — 18 条
- clarity / **backend-downloads** — 22 条
- clarity / **backend-playback-models** — 19 条
- clarity / **backend-playlist-lyrics** — 19 条
- clarity / **backend-sync-support** — 20 条
- clarity / **interface-browse** — 24 条
- clarity / **interface-nowplaying** — 32 条

---

## [clarity] app-shell (29)

### [MEDIUM] Dead background-URLSession plumbing in AppDelegate

`MuseAmp/Application/AppDelegate.swift:207` · seams-duplication

**问题**: AppDelegate stores a `backgroundCompletionHandler` in `application(_:handleEventsForBackgroundURLSession:completionHandler:)` (line 207) and exposes `urlSessionDidFinishEvents(forBackgroundURLSession:)` (line 215) to fire it. Repo-wide greps show: (1) no `URLSession(configuration:` / `URLSessionConfiguration.background` exists anywhere in MuseAmp, MuseAmpDatabaseKit, MuseAmpPlayerKit, or SubsonicClientKit, so the system will never call the handleEvents callback; (2) `urlSessionDidFinishEvents` has zero callers and AppDelegate does not conform to URLSessionDelegate, so the stored handler can never be invoked even if it were set. This is speculative seam/dead plumbing that misleads readers into believing background downloads exist.

**建议**: Delete the `// MARK: - Background URL Session` block (lines 203-224). If background download sessions are a planned feature, add the plumbing in the same change that introduces a background URLSessionConfiguration in DownloadManager.

<details><summary>验证记录</summary>

Verified all factual claims. AppDelegate.swift:203-224 contains the background-session block exactly as described. Repo-wide grep (including Vendor/) finds zero uses of URLSessionConfiguration.background or background(withIdentifier:), so the system can never call handleEventsForBackgroundURLSession. urlSessionDidFinishEvents(forBackgroundURLSession:) has zero callers, and AppDelegate conforms only to UIApplicationDelegate — it is never any URLSession's delegate — so the stored completion handler is unreachable. git log shows the block has been dead since the initial commit. AGENTS.md does not endorse speculative seams; deleting the block conflicts with no rule and matches the repo's otherwise lean Application/ layer. The block is not merely dead: it is a half-wired pattern that would silently fail to fire even if a background session were added later (the delegate callback belongs on the session delegate, not AppDelegate), making it a latent trap as well as misleading documentation-by-code that background downloads exist.

</details>

### [MEDIUM] hasExecutingTasks name hides that playback alone triggers the quit prompt

`MuseAmp/Application/AppDelegate.swift:119` · naming

**问题**: `private var hasExecutingTasks` returns `MacCatalystTerminationPolicy.shouldConfirmTermination(for:hasExecutingDownloads:)`, which is true while audio is merely playing or buffering — not an "executing task". It also shadows `environment.downloadManager.hasExecutingTasks` (used on line 125), which has the narrower downloads-only meaning. In `requestProtectedTermination` (line 130), `guard hasExecutingTasks else { action(); return }` reads as "no tasks running, exit", obscuring that playback state is part of the gate.

**建议**: Rename the AppDelegate property to `shouldConfirmTermination` or `requiresExitConfirmation` so it matches the policy method it wraps and no longer collides with DownloadManager.hasExecutingTasks.

<details><summary>验证记录</summary>

Verified: AppDelegate.swift:119 `hasExecutingTasks` wraps MacCatalystTerminationPolicy.shouldConfirmTermination, which returns true for .playing/.buffering playback alone (MacCatalystTerminationPolicy.swift:12-26), so the name overstates "tasks". Worse, the identical identifier `hasExecutingTasks` on DownloadManager (DownloadManager+Queue.swift:19) means downloads-only and is referenced inside the very same property body (line 125), giving one name two semantics in one expression. The guard at line 130 reads as a downloads/tasks check while playback is the dominant gate. AGENTS.md contains no convention endorsing this naming; the suggested rename to `shouldConfirmTermination` matches the policy method it delegates to and is consistent with repo style. Severity medium: the collision actively misleads readers of requestProtectedTermination and could breed bugs during refactors of exit/download handling.

</details>

### [MEDIUM] configureImageRequestAuthorization does not configure authorization

`MuseAmp/Application/AppEnvironment+Bootstrap.swift:131` · naming

**问题**: The method body sets Kingfisher memory/disk cache limits (lines 132-135) and rewrites `KingfisherManager.shared.defaultOptions` to REMOVE any `.requestModifier` (the mechanism authorization would use) and append `.backgroundDecode` (lines 137-143). Nothing authorization-related is configured — if anything, authorization is stripped. The name actively misleads anyone searching for where image requests get auth headers.

**建议**: Rename to something honest such as `configureImageCacheAndRequestOptions()` (or split cache limits and option rewriting into two named steps), keeping the call site in `AppEnvironment.init` updated.

<details><summary>验证记录</summary>

Confirmed at MuseAmp/Application/AppEnvironment+Bootstrap.swift:131-144 (mirrored in MuseAmpTV/Application/TVAppContext+Bootstrap.swift:136). The method only sets Kingfisher cache limits and rewrites defaultOptions to remove .requestModifier and add .backgroundDecode; no authorization is ever configured. Git history shows the body has been authorization-free since the init commit, and .requestModifier appears nowhere else in either target, so the name has never described the behavior. AGENTS.md contains nothing endorsing the name or pattern. The rename suggestion is local, safe, and consistent with repo style (call sites at AppEnvironment.swift:60 and TVAppContext.swift:70 plus the tvOS mirror). The name actively misleads anyone searching for where image requests get auth headers, so medium severity stands.

</details>

### [MEDIUM] Strong self captured in .sink violates the explicit weak-self Combine rule

`MuseAmp/Application/AppEnvironment+Events.swift:16` · repository-conventions

**问题**: `observeDatabaseEvents` subscribes with `.sink { event in self.handleDatabaseEvent(event) }` — a strong `self` capture stored into `self.cancellables`, creating a retain cycle (self -> cancellables -> closure -> self). AGENTS.md Combine Observation Rules state unconditionally: "Always capture `[weak self]` in `.sink` closures". AppEnvironment is app-lifetime in production, but the type takes a `baseDirectory` parameter for test instances, which would leak.

**建议**: Use `.sink { [weak self] event in self?.handleDatabaseEvent(event) }`.

<details><summary>验证记录</summary>

Verified at MuseAmp/Application/AppEnvironment+Events.swift:16-19: .sink captures strong self and is stored in self.cancellables on final class AppEnvironment, forming a retain cycle. AGENTS.md ("Combine Observation Rules", line 156) unconditionally mandates [weak self] in .sink closures, and a repo-wide grep shows all other ~40 .sink closures touching self use [weak self] — this is the sole violation, so the dominant convention endorses the fix, not the flagged pattern. The leak claim is also concrete: observeDatabaseEvents() runs from the designated init (AppEnvironment.swift:115) and MuseAmpTests/TestSupport.swift:24 builds AppEnvironment(baseDirectory:) instances, so every test environment leaks. The suggested fix matches repo style exactly. Severity stays medium: production instance is app-lifetime so no user-visible bug, but it actively breeds leaks in tests and contradicts an explicit unconditional rule.

</details>

### [MEDIUM] Pending-import drain logic duplicated between drainPendingImports and scheduleCoalescedImport

`MuseAmp/Application/SceneDelegate.swift:230` · seams-duplication

**问题**: Lines 161-183 (`drainPendingImports`) and lines 237-255 (inside `scheduleCoalescedImport`) contain the same five-step sequence: copy the three pending URL arrays, `removeAll()` each, call `performFileImport`, `performPlaylistImport`, then the identical first-server-profile-only block including the duplicated `AppLog.warning(self, "Multiple server profile files received; importing the first one only")`. Any change to import dispatch (a fourth file type, different multi-profile policy) must be made twice.

**建议**: Extract a single `@MainActor func dispatchPendingImports(to mainController: MainController)` that snapshots+clears the pending arrays and performs the three dispatches; call it from both paths.

<details><summary>验证记录</summary>

Confirmed in MuseAmp/Application/SceneDelegate.swift: drainPendingImports (lines 154-184) and scheduleCoalescedImport's task body (lines 237-255) duplicate the same snapshot-and-clear of the three pending URL arrays followed by the same three dispatches, including the byte-identical AppLog.warning("Multiple server profile files received; importing the first one only"). Only the wrapping differs (DispatchQueue.main.async + optional mainController vs. 200ms coalescing Task + guard let mainController), which is precisely what an extracted dispatchPendingImports(to:) helper would preserve. These are the only two file-import entry paths (cold launch vs. warm openURLContexts), so any policy change (fourth file type, different multi-profile handling) must be made twice and can drift silently. AGENTS.md does not endorse this duplication, and a private helper in the existing private extension matches the file's local style and all project rules. Severity stays medium: duplicated dispatch policy across both import entry points actively breeds divergence bugs rather than being merely cosmetic.

</details>

### [MEDIUM] Importable audio extension list duplicated with AudioFileImporter

`MuseAmp/Application/SceneDelegate.swift:138` · named-constants

**问题**: `Self.importableExtensions` (lines 138-140: mp3, m4a, flac, wav, aac, aiff, alac, ogg, wma, opus) is byte-for-byte duplicated as a local `audioExtensions` set inside MuseAmp/Backend/Library/AudioFileImporter.swift (lines 387-389). The two copies define the same concept — "what counts as an importable audio file" — and will drift if a format is added to only one.

**建议**: Centralize as `static let importableAudioExtensions: Set<String>` on AudioFileImporter (the Backend owner of import behavior) and have SceneDelegate's `isImportableAudioFile` reference it.

<details><summary>验证记录</summary>

Confirmed byte-for-byte duplication: SceneDelegate.importableExtensions (SceneDelegate.swift:138-140) and the local audioExtensions set in AudioFileImporter.isAudioFile (AudioFileImporter.swift:387-389) both list mp3/m4a/flac/wav/aac/aiff/alac/ogg/wma/opus. They define the same concept (importable audio formats) and the SceneDelegate-gated URLs feed the same import pipeline owned by AudioFileImporter, so drift would cause real behavioral inconsistency (open-in rejecting formats the importer accepts, or vice versa). AGENTS.md does not endorse the duplication; its rule that domain logic lives under Backend/ actually supports the suggested fix of a single static constant on AudioFileImporter referenced by SceneDelegate. The fix is small, target-internal, and stylistically consistent with the repo.

</details>

### [MEDIUM] Popup engine duplicated with TabBarController+Popup and already drifting

`MuseAmp/Interface/Root/MainController+Popup.swift:156` · seams-duplication

**问题**: Roughly 200 lines are near-verbatim duplicates of TabBarController+Popup.swift: `updateNowPlayingPopupItem` (156-198 vs 128-169), `updatePopupProgress`, `popupProgress`/`progress(for:)`, `updatePopupBarButtonState`, `updatePopupArtwork` (225-262 vs 198-237), `retrievePopupArtwork`, and `buildPopupContextMenu` (351-399 vs 325-372). The copies have already drifted in subtle ways a reader cannot tell are intentional: (a) syncPopupPresentation here dismisses when state `!= .barHidden` and returns before updating the item (lines 106-111), while TabBar updates the item first and dismisses only when `== .barPresented` (TabBarController+Popup.swift:86-93); (b) TabBar resets `isNowPlayingPopupOpen = false` in willClose AND didClose (lines 290, 299) while this file does so only in didClose (line 331), so `childForStatusBarHidden` differs during the close animation; (c) TabBar's didClose also dismisses the bar when no track remains (lines 302-306) — absent here. The mapping notes call the duplication deliberate, but the drift shows the cost; the repo already proved the shared-seam pattern with PopupBarPagingHandler.

**建议**: Extract the verbatim-identical parts (popup item updates, artwork loading/retrieval, progress math, bar-button state) into a shared @MainActor helper alongside PopupBarPagingHandler, parameterized with the popup container and content VC; keep only genuinely shell-specific presentation policy (dismiss conditions, lyricsActionsBeforeReload) in each controller — or document each intentional divergence at the divergent line.

<details><summary>验证记录</summary>

Verified by reading both files. ~200 lines (updateNowPlayingPopupItem, updatePopupProgress, progress math, updatePopupBarButtonState, updatePopupArtwork, retrievePopupArtwork, buildPopupContextMenu, Combine bindings) are near-verbatim duplicates between MainController+Popup.swift and TabBarController+Popup.swift. All three cited drift points check out exactly: (a) dismiss condition and ordering in syncPopupPresentation differ (lines 106-111 vs 86-93), (b) isNowPlayingPopupOpen reset in willClose+didClose vs didClose only (290/299 vs 331), (c) TabBar didClose dismisses bar when no track remains (302-306) with no MainController counterpart. None of the divergences are documented, so a reader cannot tell drift from policy. AGENTS.md does not endorse this duplication (only tvOS Sync symlink mirroring, which is sharing not copying), and the suggested fix matches existing local convention: PopupBarPagingHandler in the same Interface/Root/ folder is already a shared seam used by both controllers. Genuine shell-specific differences (content VC type, popup container access, lyricsActionsBeforeReload, nav-controller resolution) are exactly what the suggestion keeps per-controller, so extraction is feasible without violating repo style.

</details>

### [MEDIUM] File named MainController+Sidebar contains no MainController extension

`MuseAmp/Interface/Root/MainController+Sidebar.swift:124` · file-organization

**问题**: The file's 537 lines define `SidebarSection`, `SidebarItem`, the private `SidebarPlaylistCell`, the full `SidebarViewController` class (line 124), and its UICollectionViewDelegate extension — there is no `extension MainController` anywhere in it. The repo convention (and principle: filename = primary export) is that `Type+Feature.swift` holds an extension of Type; a reader looking for SidebarViewController.swift will not find it, and a reader opening this file expecting MainController code finds a different controller.

**建议**: Rename to `SidebarViewController.swift` (keeping it in Interface/Root/), optionally splitting `SidebarPlaylistCell` into its own file; update the Xcode group to match per AGENTS.md.

<details><summary>验证记录</summary>

Verified: MainController+Sidebar.swift contains zero `extension MainController` declarations. It defines SidebarSection/SidebarItem enums, a private SidebarPlaylistCell, the full SidebarViewController class (line 124), and a SidebarViewController UICollectionViewDelegate extension (line 503). The dominant local convention is the opposite of the flagged pattern: sibling files MainController+Layout.swift and MainController+Popup.swift genuinely extend MainController, and AGENTS.md mandates `XxxViewController+Layout.swift`-style files as responsibility-based extensions of the named controller, while standalone controllers in Interface/Root (TabBarController.swift, BootProgressController.swift, MainController.swift) are named after their primary class. So the name actively misleads: a reader is trained by the neighboring files to expect MainController code here, and a search for SidebarViewController.swift finds nothing. The suggested fix (rename to SidebarViewController.swift in Interface/Root/, update the Xcode group per the 'Keep Xcode groups aligned with on-disk folders' rule) makes the code read MORE like the rest of the repo, not less, and violates no AGENTS.md rule. Severity stays medium: not bug-breeding, but it actively misleads navigation in a directory where the +Feature convention is otherwise consistently honored.

</details>

### [MEDIUM] selectDestination and openPlaylistDetail duplicate the popup-close + sidebar-collapse sequence

`MuseAmp/Interface/Root/MainController.swift:275` · seams-duplication

**问题**: Lines 266-281 (`selectDestination`) and lines 287-301 (`openPlaylistDetail`) share a verbatim tail: close the open popup, install the nav controller, then the identical `if rootSplitViewController.displayMode == .oneOverSecondary { Interface.quickAnimate(duration: 0.25) { ...preferredDisplayMode = .secondaryOnly } completion: { ...preferredDisplayMode = .automatic } }` dance. The overlay-collapse animation trick is exactly the kind of subtle UIKit workaround that should exist once.

**建议**: Extract a private `func presentContent(_ nav: UINavigationController)` (close popup, installContentNavigationController, collapse oneOverSecondary overlay) and call it from both methods after they set their selection state.

<details><summary>验证记录</summary>

Confirmed by reading MainController.swift: selectDestination (253-282) and openPlaylistDetail (284-302) end with a verbatim shared tail — popup-open check + closePopup, installContentNavigationController(nav), and the identical 7-line oneOverSecondary overlay-collapse animation (quickAnimate setting preferredDisplayMode to .secondaryOnly then back to .automatic). Grep shows these are the only two occurrences of the trick in the repo, so a single private helper would own the entire workaround. AGENTS.md does not endorse this duplication; the repo's convention actually favors shared helpers and responsibility-based extensions (installContentNavigationController already lives in MainController+Layout.swift as a shared seam), so the suggested extraction reads like the surrounding code. The duplicated block is a subtle, non-obvious UIKit workaround whose divergence between the two paths would produce a silent UI inconsistency, which supports medium severity despite the two sites being adjacent in one file.

</details>

### [MEDIUM] Playlist tab located by comparing localized display titles

`MuseAmp/Interface/Root/MainController.swift:520` · state-modeling

**问题**: `revealPlaylistImportSurface` finds the compact Playlist tab via `compactTabBarController.viewControllers?.firstIndex(where: { $0.tabBarItem.title == playlistTitle })` where `playlistTitle = String(localized: "Playlist")` (lines 519-523). Tab identity is derived from presentation text: if the tab title wording or its localization changes, the import flow silently stops switching tabs. TabBarController already assigns stable identifiers (`identifier: "playlist"` for UITab, `tab.playlist` accessibility identifiers on the legacy path).

**建议**: Expose a `func selectPlaylistTab()` on TabBarController that resolves the tab by its stable identifier (UITab `identifier == "playlist"` on iOS 18+, root VC `is PlaylistViewController` on legacy), and call that instead of title matching.

<details><summary>验证记录</summary>

Verified at MainController.swift:516-528: the compact Playlist tab is located by comparing tabBarItem.title against String(localized: "Playlist"), coupling tab identity to localized presentation text duplicated across two files (TabBarController.swift:138/193). TabBarController already assigns a stable identifier "playlist" (line 140, UITab path) and "tab.playlist" accessibility identifiers (line 210, legacy path), and itself resolves tabs structurally elsewhere ($0.identifier == "settings" at line 265, `first is SearchViewController` at lines 275-278), so identifier-based lookup is an established in-module pattern, not foreign style. Failure mode is a silent no-op (if-let with no log). On the iOS 18+ UITab path the providers never set tabBarItem.title on the wrapped nav controllers, so the match additionally relies on implicit UIKit bridging. AGENTS.md does not endorse title matching anywhere; its Testing Rules treat .title comparisons as presentation-only details. The suggested selectPlaylistTab() on TabBarController fits the repo's dependency-threading and existing identifier-lookup conventions. Severity stays medium: it breeds a silent bug on rewording/relocalization but has not demonstrably broken yet.

</details>

### [MEDIUM] Popup userInfo keys "trackID"/"queueIndex" repeated as raw literals in three files

`MuseAmp/Interface/Root/PopupBarPagingHandler.swift:32` · named-constants

**问题**: The string keys "queueIndex" and "trackID" form an implicit contract between producers (MainController+Popup.swift:183-184, TabBarController+Popup.swift:154-155, PopupBarPagingHandler.swift:82-83) and consumers (PopupBarPagingHandler.swift lines 32, 40, 50-51) — 10 raw-literal sites total. A typo in any one site silently breaks popup paging (the guards just return nil).

**建议**: Define the keys once, e.g. `enum PopupItemUserInfoKey { static let trackID = "trackID"; static let queueIndex = "queueIndex" }` next to PopupBarPagingHandler, and use it at all 10 sites.

<details><summary>验证记录</summary>

Verified all 10 cited sites exist: producers in TabBarController+Popup.swift:153-156 and MainController+Popup.swift:182-185, producer+consumers in PopupBarPagingHandler.swift (lines 32, 40, 50-51, 82-83). The "queueIndex" key forms a genuine cross-file implicit contract; consumers guard-return nil silently (no AppLog), so a typo in any producer would silently break popup paging exactly as described. The fix aligns with the repo's documented convention — AGENTS.md explicitly says "User info keys are centralized in AppNotificationUserInfoKey", and LibraryChangeNotifications.swift:18-19 already implements precisely the suggested enum-of-static-strings pattern — so the refactor would read like existing repo code, not against it. Minor caveat: "trackID" is produced at 3 sites but never read back from popup userInfo, so only the "queueIndex" half of the contract carries live risk; still, 7 live sites across 3 files with a silent failure mode justifies medium (breeds bugs on modification) rather than low.

</details>

### [MEDIUM] Downloads badge target found by localized Settings title

`MuseAmp/Interface/Root/TabBarController.swift:228` · state-modeling

**问题**: `updateDownloadsBadge` locates the badge host with `tabBar.items?.first(where: { $0.title == String(localized: "Settings") })` (lines 227-231). Like MainController.swift:520, identity is derived from localized display text; if the Settings title changes or localizes differently the badge silently disappears (the guard just returns). The method name also hides that the downloads badge intentionally lives on the Settings tab — only reading the body reveals it.

**建议**: Resolve the Settings tab by stable identity (UITab `identifier == "settings"` on iOS 18+, root `is SettingsViewController` on legacy), and log via AppLog.warning when the tab cannot be found instead of silently returning.

<details><summary>验证记录</summary>

Confirmed at TabBarController.swift:226-232: the downloads badge host is found by comparing tab titles against String(localized: "Settings"), with a silent guard return on miss. Crucially, the same file already resolves the settings tab by stable identity elsewhere — `$0.identifier == "settings"` (line 265) and `first is SettingsViewController` (lines 294-297) — so the title-match is an outlier against the file's own convention, and the suggested fix would make the code MORE consistent with surrounding code, not less. The "Settings" literal appears in three independent places; retitling the tab without updating the lookup silently disables the badge with no log, which conflicts with the repo's Logging Rules requiring silent-failure paths to log. AGENTS.md does not endorse title-based identity anywhere (its Testing Rules explicitly discourage `.title ==` checks). One sibling occurrence exists in MainController.swift but it is itself flagged and does not constitute a dominant convention. Not a live bug today (construction and lookup use the same localized string at runtime), but it is a genuine bug-breeding fragility plus the method name conceals that the badge intentionally lives on the Settings tab, so medium severity is honest.

</details>

### [MEDIUM] Tab titles/icons re-stated and search-tab construction triplicated

`MuseAmp/Interface/Root/TabBarController.swift:163` · seams-duplication

**问题**: Tab metadata pairs ("Albums"/square.stack, "Songs"/music.note, "Playlist"/music.note.list, "Settings"/gearshape, "Search"/magnifyingglass) are already encoded once in `RootDestination.title`/`imageName` (MainController.swift:25-61) yet re-stated literally in `setupWithUITab` (lines 110-172) and `setupWithViewControllers` (lines 190-198). Worse, the UISearchTab construction block (lines 163-172) is verbatim duplicated in `handleServerConfigurationDidChange` (lines 254-261), and the legacy search nav construction (lines 282-293) duplicates the `setupWithViewControllers` entry a fourth time. The 60-line `handleServerConfigurationDidChange` then re-implements insert/remove positioning for both API generations.

**建议**: Extract `makeSearchTab()` (iOS 18+) and `makeSearchNavigationController()` (legacy) helpers used by both initial setup and the configuration-change handler, and drive titles/images from RootDestination instead of re-typed literals.

<details><summary>验证记录</summary>

Verified in TabBarController.swift: the UISearchTab closure (lines 163-172) is duplicated verbatim in handleServerConfigurationDidChange (lines 254-261), and the legacy search nav construction (lines 282-293) re-implements the setupWithViewControllers entry, giving four construction sites for the search tab. Tab title/icon pairs are re-typed as literals despite RootDestination.title/imageName (MainController.swift:25-61) encoding them and being used by the sibling sidebar shell. AGENTS.md does not endorse this pattern; extracting makeSearchTab()/makeSearchNavigationController() helpers and sourcing metadata from RootDestination matches the module's existing conventions. The setup-vs-change-handler duplication is a genuine drift-bug breeder (an existing prefersLargeTitles divergence between generations is already hard to audit as intentional), so medium severity stands.

</details>

### [LOW] terminateApplication uses unexplained suspend trick and magic delays

`MuseAmp/Application/AppDelegate.swift:227` · named-constants

**问题**: The non-Catalyst branch sends `#selector(NSXPCConnection.suspend)` to UIApplication (a selector-smuggling trick to suspend the app gracefully), then sleeps 1 second in a detached task before `exit(0)`, then `sleep(5)` + `fatalError()` as a watchdog (lines 231-237). None of this is explained, and the 1s/5s literals are unnamed. AGENTS.md says comments belong exactly where they remove real ambiguity — this is that case.

**建议**: Name the delays (e.g. `private let exitGraceDelay: Duration = .seconds(1)`, `watchdogSeconds: UInt32 = 5`) and add a one-line comment explaining the suspend-then-exit sequence (suspend to background gracefully, exit after the OS snapshot, fatalError if exit never happens).

<details><summary>验证记录</summary>

Verified in MuseAmp/Application/AppDelegate.swift: terminateApplication() uses UIApplication.shared.perform(#selector(NSXPCConnection.suspend)) (selector-smuggling to invoke UIApplication's private suspend), a detached Task sleeping 1s before exit(0), then sleep(5) + fatalError() as a watchdog — all uncommented with bare 1/5 literals. This is exactly the kind of non-obvious code AGENTS.md's comment rule ('Keep comments rare and only where they remove real ambiguity') says should be commented; no repo convention endorses unexplained magic delays or undocumented selector tricks. The suggested fix (named durations + one-line comment) is small, local, and consistent with repo style. Severity remains low: purely a clarity issue in a rarely-touched exit path, though the trick could be broken by a naive refactor if left unexplained.

</details>

### [LOW] 40-line inspectAudioFile closure mixes factory orchestration with raw path/attribute parsing

`MuseAmp/Application/AppEnvironment+Bootstrap.swift:83` · abstraction-levels

**问题**: Inside `makeRuntimeDependencies`, the `inspectAudioFile` closure (lines 83-122) does relative-path splitting with `split(separator:maxSplits:)`, trackID derivation from path components, FileManager attribute extraction, and a 15-field `ImportedTrackMetadata` assembly — all inline in the dependency-bag factory next to one-line closures like `fetchLyrics`. The factory's abstraction level (wire dependencies) is buried under low-level parsing detail.

**建议**: Extract a `private static func inspectAudioFile(at fileURL: URL, paths: LibraryPaths, metadataReader: EmbeddedMetadataReader) async throws -> AudioFileInspection` and reduce the closure to a one-line forward. The AGENTS-sanctioned closure-based RuntimeDependencies shape is preserved.

<details><summary>验证记录</summary>

Confirmed: the inspectAudioFile closure at AppEnvironment+Bootstrap.swift:83-122 inlines ~40 lines of path splitting, FileManager attribute parsing, and 15-field ImportedTrackMetadata assembly inside a factory whose other closures are 1-7 lines, so the abstraction-level mismatch is real. AGENTS.md does not endorse inline factory closures; its rule that domain logic lives under Backend/ (not Application/) actually leans against the current code. The only 'local convention' counterargument fails: the sole other RuntimeDependencies factory (MuseAmpTV/Application/TVAppContext+Bootstrap.swift:88-127) is a verbatim paste of the same 40-line closure — duplication, not convention — and the suggested static-func extraction is the natural deduplication seam. The fix preserves the closure-based RuntimeDependencies shape and matches surrounding style. Severity stays low: cosmetic clarity plus a mild cross-target drift risk, no active bug or misleading behavior.

</details>

### [LOW] Anonymous NSError(domain:code:) carries no failure description

`MuseAmp/Application/AppEnvironment+Bootstrap.swift:69` · error-boundaries

**问题**: `resolveDownloadURL` throws `NSError(domain: "AppEnvironment", code: 1)` when the playback URL string fails to parse. The error has no userInfo/localizedDescription, so logs and user-facing failure paths downstream show an opaque "AppEnvironment error 1" with no hint that the server returned an unparseable playbackURL.

**建议**: Throw a descriptive error, e.g. `NSError(domain: "AppEnvironment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid playback URL for track \(trackID)"])` or a small dedicated error enum.

<details><summary>验证记录</summary>

Confirmed: AppEnvironment+Bootstrap.swift:69 throws NSError(domain: "AppEnvironment", code: 1) with no userInfo inside resolveDownloadURL, producing an opaque "AppEnvironment error 1" in logs and AlertController-based error UI. The repo's dominant convention contradicts the flagged pattern: MuseAmpDatabaseKit NSErrors all carry NSLocalizedDescriptionKey, and the app target uses LocalizedError enums throughout (e.g. PlaybackResolutionError handles the exact analogous playback-URL failure). Only three bare NSErrors exist in non-test code (this one, its tvOS mirror in TVAppContext+Bootstrap.swift:74, and MusicLibraryDatabase+Ingest.swift:15) — stragglers, not a convention. AGENTS.md does not endorse anonymous errors; its logging rules favor meaningful diagnostics. The suggested fix matches existing repo styles. Severity remains low: rare failure path, clarity-of-diagnosis issue only.

</details>

### [LOW] librarySummary swallows the thrown error's content from the log

`MuseAmp/Application/AppEnvironment.swift:147` · error-boundaries

**问题**: The catch block logs `"libraryDatabase.storedLibrarySummary() threw - returning empty summary"` without interpolating the caught error, so the diagnostic trail (required by AGENTS.md Logging Rules for swallowed errors) records that something failed but not why. Contrast with `refreshTrackTitleSanitizer` (line 159) in the same file, which logs `error=\(error)`.

**建议**: Include the error: `AppLog.warning(self, "storedLibrarySummary failed, returning empty summary error=\(error)")`.

<details><summary>验证记录</summary>

Verified at /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Application/AppEnvironment.swift lines 144-153: the catch in librarySummary() logs "libraryDatabase.storedLibrarySummary() threw - returning empty summary" without interpolating the caught error. The same file (line 47 bootstrap catch, line 159 refreshTrackTitleSanitizer) and the dominant repo-wide convention (APIClient, PlaylistStore, DownloadStore, DownloadManager, etc., ~68+ catch logs) consistently include error=\(error) or \(error.localizedDescription). AGENTS.md Logging Rules mandate logging swallowed errors but do not endorse omitting the error payload; the suggested fix aligns the code with the surrounding convention rather than diverging from it. Cosmetic/diagnostic-quality only, so severity remains low.

</details>

### [LOW] Inbound-URL classification chain duplicated between willConnectTo and openURLContexts

`MuseAmp/Application/SceneDelegate.swift:48` · seams-duplication

**问题**: The four-way classification `if url.isFileURL, isImportableAudioFile(url) ... else if isImportablePlaylistFile ... else if isImportableServerProfileFile ... else if let receiverInfo = parseAppleTVURL(url)` appears verbatim at lines 48-59 and again at lines 94-105, differing only in which buffer/handler receives the result. Adding a new inbound URL kind requires editing both chains in lockstep.

**建议**: Introduce a single classifier, e.g. `enum InboundURL { case audio(URL), playlist(URL), serverProfile(URL), tvHandshake(SyncReceiverHandshakeInfo) }` with `func classify(_ url: URL) -> InboundURL?`, and switch on it in both scene callbacks.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Application/SceneDelegate.swift: the four-branch classification chain (audio / playlist / server-profile / parseAppleTVURL) appears verbatim at lines 48-59 and 94-105, differing only in where results are routed. Adding a new inbound URL kind requires editing both chains in lockstep, and the file already shows the same copy-paste pressure in drainPendingImports vs scheduleCoalescedImport. AGENTS.md does not endorse this pattern; its style rules (early returns, responsibility splits, value types) are compatible with the suggested InboundURL enum classifier, which is idiomatic Swift and would keep per-callback handling differences at each call site. The finding is technically accurate and the fix is a real clarity gain, but it is cosmetic: only two call sites, predicates already factored into named helpers, chains currently in sync, no bug bred. Severity remains low.

</details>

### [LOW] defer used for ordinary end-of-function window activation

`MuseAmp/Application/SceneDelegate.swift:63` · function-design

**问题**: Lines 63-66 use `defer { window.makeKeyAndVisible(); self.window = window }` purely to run after the `window.rootViewController = bootController` assignment at line 87. There are no early returns between the defer and the end of the function, so the defer is a non-linear ordering trick where straight-line statements at the end of the method would express the same sequence directly.

**建议**: Delete the defer and place `window.makeKeyAndVisible()` and `self.window = window` after the `window.rootViewController = bootController` line.

<details><summary>验证记录</summary>

Verified in MuseAmp/Application/SceneDelegate.swift: the defer at lines 63-66 has no early returns, throws, or other exit paths between it and the end of scene(_:willConnectTo:) at line 88, so it executes exactly as straight-line statements placed after window.rootViewController = bootController would. The suggested fix is behavior-identical and reads in execution order. Repo convention check: all other defer uses in the codebase (AudioFileImporter, SyncServer, PlaylistTransferCoordinator, ServerProfileImportCoordinator) are genuine cleanup (security-scoped resource release, lock unlock, freeifaddrs); this is the sole instance using defer as an ordering trick, so the fix aligns with rather than violates local convention. AGENTS.md says nothing endorsing the pattern. Impact is purely cosmetic (small backward scan for the reader), so severity stays low.

</details>

### [LOW] shiftedHue captures alpha then silently discards it

`MuseAmp/Extension/Extension+UIColor.swift:29` · function-design

**问题**: `getHue(&hue, saturation:, brightness:, alpha: &alpha)` fills the local `alpha` (line 21), but the returned color hardcodes `alpha: 1` (line 33) and the failure fallback is `withAlphaComponent(1)` (line 22). The captured-but-unused `alpha` variable suggests preservation was intended; as written, the function has an invisible side effect — it strips translucency — that neither the name `shiftedHue(by:saturationMultiplier:brightnessMultiplier:)` nor any call-site hint conveys.

**建议**: Either pass the captured value (`alpha: alpha`) to preserve translucency, or remove the unused capture (pass nil-equivalent and `alpha: 1`) and note the opaque-output behavior in the function name or a one-line comment.

<details><summary>验证记录</summary>

Confirmed: alpha is captured via getHue(&alpha) at line 21 but never read; the return hardcodes alpha: 1 (line 33) and the fallback is withAlphaComponent(1) (line 22). getHue accepts nil pointers, so the capture is genuinely superfluous, and the suggested fix (pass nil + brief comment, or preserve alpha) is minimal and consistent with repo style (AGENTS.md Property Rules discourage unnecessary state; comments allowed where they remove real ambiguity). However, the finding overstates intent: both branches consistently force alpha=1, suggesting deliberate opaque output rather than forgotten preservation. Also, shiftedHue has zero call sites anywhere in the repo, so the call-site confusion is theoretical — capping severity at low rather than refuting, since the unused capture is still a real clarity defect in checked-in code.

</details>

### [LOW] User-facing "Boot Failed" string is not localized

`MuseAmp/Interface/Root/BootProgressController.swift:80` · repository-conventions

**问题**: `statusLabel.text = "Boot Failed"` assigns a raw literal to a label shown to the user on boot failure. AGENTS.md Localization Rules require all user-facing strings in the app target to use `String(localized:)` with matching entries in MuseAmp/Resources/Localizable.xcstrings (en + zh-Hans).

**建议**: Use `statusLabel.text = String(localized: "Boot Failed")` and add the key with en/zh-Hans localizations to MuseAmp/Resources/Localizable.xcstrings in the same change.

<details><summary>验证记录</summary>

Verified: MuseAmp/Interface/Root/BootProgressController.swift line 80 assigns the raw literal "Boot Failed" to statusLabel, which showFailureState() unhides for the user — it is user-facing, not a hidden diagnostic (the AppLog.error call on line 70 handles diagnostics separately). AGENTS.md Localization Rules explicitly mandate String(localized:) for all user-facing app-target strings with en + zh-Hans entries in MuseAmp/Resources/Localizable.xcstrings; the key is not present in that file. The dominant convention in the same folder (TabBarController.swift, MainController+Popup.swift, TabBarController+Popup.swift) and across the app target (679 String(localized:) call sites) endorses the suggested fix, not the flagged pattern. The fix is a one-line change plus an xcstrings entry and reads exactly like the rest of the repo. Severity adjusted to low: it is a single untranslated string on a rare boot-failure path; it does not mislead maintainers or block safe modification, though it would fail the repo's own validate-xcstrings hygiene intent.

</details>

### [LOW] onImportPlaylistRequested is optional, deviating from the non-optional-callback rule

`MuseAmp/Interface/Root/MainController+Sidebar.swift:130` · repository-conventions

**问题**: `var onImportPlaylistRequested: (() -> Void)?` sits beside three sibling callbacks declared per convention with empty defaults (`onDestinationSelected`, `onPlaylistSelected`, `onPlaylistsDidReload`, lines 127-129). It is always assigned before use (MainController.viewDidLoad line 179) and invoked with optional chaining `self?.onImportPlaylistRequested?()` (line 483). AGENTS.md Property Rules: callbacks always assigned before use should be non-optional with an empty default.

**建议**: Declare `var onImportPlaylistRequested: () -> Void = {}` and drop the `?()` at the call site.

<details><summary>验证记录</summary>

Verified: line 130 of MainController+Sidebar.swift declares the callback as optional `(() -> Void)?` while its three immediate siblings (lines 127-129) use the non-optional empty-default convention. It is always assigned in MainController.viewDidLoad (line 179) before its only call site (line 483, a user-triggered sidebar action), so the AGENTS.md Property Rule (line 229) directly mandates the non-optional form with `?()` removed. The pattern is the opposite of both the documented rule and the dominant local convention; the suggested fix aligns with both. Severity remains low: a cosmetic consistency issue with no behavioral impact.

</details>

### [LOW] Coupled magic numbers: 28pt cover size in three places, prefix(8)/prefix(7) playlist caps

`MuseAmp/Interface/Root/MainController+Sidebar.swift:440` · named-constants

**问题**: The sidebar cover side length 28 appears at line 37 (spacerImage size), line 47 (imageProperties.maximumSize), and line 245 (`sideLength: 28` in the artwork fetch) — three sites that must agree or covers render misaligned/blurry. In `orderedSidebarPlaylists`, `prefix(8)` (line 440) and `prefix(7)` (line 446) encode the hidden relationship "8 rows max, liked-songs occupies one slot" with no name connecting them.

**建议**: Hoist `private static let coverSideLength: CGFloat = 28` and `private static let maxSidebarPlaylists = 8`, deriving the second prefix as `maxSidebarPlaylists - 1`.

<details><summary>验证记录</summary>

All cited sites exist as described in MainController+Sidebar.swift: the 28pt cover side appears at lines 37 (spacer image), 47 (maximumSize), and 245 (sideLength in the artwork cache fetch), and PlaylistCoverArtworkCache rasterizes at sideLength*scale, so the three sites must agree or covers render at the wrong resolution. prefix(8)/prefix(7) at lines 440/446 encode the unnamed invariant that liked-songs occupies one of 8 sidebar slots. The fix matches, not violates, repo convention: sibling PlaylistCell.swift hoists `private let artworkSideLength: CGFloat = 44` for the identical pattern. AGENTS.md does not endorse inline magic dimensions (its only hardcode rules are the 200pt lyric spacer and a ban on hardcoding artwork URL dimensions). Minor caveat: the 28s span two types, so the constant needs file-private scope rather than a single type's static let — trivial. Values currently agree and no bug exists, so severity remains low (cosmetic clarity / latent coupling).

</details>

### [LOW] Undocumented overlay hack on UIKit's internal list-cell image view

`MuseAmp/Interface/Root/MainController+Sidebar.swift:109` · abstraction-levels

**问题**: `SidebarPlaylistCell` renders a transparent `spacerImage` into the list content configuration (line 45), then in `layoutSubviews` recursively searches the contentView for UIKit's private internal UIImageView (`findInternalImageView`, lines 109-119) and pins two custom image views to its converted frame (lines 89-92). This depends on UIKit's private view hierarchy and on the spacer reserving layout space — genuinely ambiguous machinery with zero comments. AGENTS.md keeps comments rare but mandates them exactly where they remove real ambiguity.

**建议**: Add a short comment above `findInternalImageView`/`spacerImage` explaining the technique (spacer reserves the sidebarCell image slot; custom views overlay it to support placeholder/cover crossfade) and why the configuration API alone is insufficient.

<details><summary>验证记录</summary>

Verified at MuseAmp/Interface/Root/MainController+Sidebar.swift: spacerImage (line 37) is a transparent 28x28 image assigned as the list configuration image (line 45) purely to reserve UIKit's sidebarCell image slot; layoutSubviews (72-93) then recursively locates UIKit's private internal UIImageView via findInternalImageView (109-119) and overlays two custom image views on its converted frame. The mechanism is genuinely non-obvious — deleting the 'useless' transparent spacer or the recursive search would silently break cover rendering — and the class has zero comments. AGENTS.md line 221 ('Keep comments rare and only where they remove real ambiguity') endorses commenting exactly this case, and the repo's own convention confirms it: EdgeFadeBlurView.swift:41-43 and PopupBarSplitViewController.swift:37 (same Interface/Root folder) both annotate comparable private-API/magic hacks with short comments. The suggested brief comment matches local style and would not violate any rule. Severity stays low: code is self-contained and recoverable by a careful reader; it invites unsafe cleanup but does not actively mislead.

</details>

### [LOW] RootDestination.library is a dead case threaded through three switches

`MuseAmp/Interface/Root/MainController.swift:17` · state-modeling

**问题**: No code ever constructs `RootDestination.library`: grep shows zero `.destination(.library)` or `RootDestination.library` construction sites — the only `.library` matches on this enum are its own switch arms (title line 27, imageName line 46) and `case .library, .albums:` in `contentNavigationController` (line 364), where it behaves identically to `.albums`. The dead case forces every switch over RootDestination to handle a destination that cannot occur and implies a distinct "Library" screen exists.

**建议**: Remove `case library` from RootDestination and the corresponding arms in `title`, `imageName`, and `contentNavigationController(for:)`.

<details><summary>验证记录</summary>

Verified: RootDestination.library (MainController.swift:17) is never constructed anywhere in the repo. RootDestination appears only in MainController.swift and MainController+Sidebar.swift; the sidebar snapshot constructs .albums/.songs/.downloads/.playlistList/.search/.settings only, there is no rawValue init, allCases usage, or persisted raw value that could produce .library, and the compact TabBarController does not use the enum at all. Its only switch arm with behavior (line 364) aliases .albums exactly. AGENTS.md documents root navigation destinations without any Library destination, so removal aligns the enum with documented shell structure; no convention endorses keeping dead enum cases. The suggested removal is safe and improves clarity. Severity stays low: the dead case slightly misleads (implies a distinct Library screen) but breeds no bug.

</details>

### [LOW] cleanupInbox swallows per-file removal failures without logging

`MuseAmp/Interface/Root/MainController.swift:509` · error-boundaries

**问题**: Inside `cleanupInbox`, `try? FileManager.default.removeItem(at: file)` (line 509) silently discards removal errors; the surrounding do/catch only logs `contentsOfDirectory` failures. AGENTS.md Logging Rules: every `try?` that silently swallows an error must log via AppLog.error or AppLog.warning, and file-delete failures in particular must be logged.

**建议**: Replace with a do/catch per file: `do { try FileManager.default.removeItem(at: file) } catch { AppLog.warning("MainController", "cleanupInbox failed to remove \(file.lastPathComponent): \(error)") }`.

<details><summary>验证记录</summary>

Confirmed: MainController.swift line 509 uses `try? FileManager.default.removeItem(at: file)` inside cleanupInbox, and the enclosing do/catch only logs contentsOfDirectory failures. AGENTS.md Logging Rules explicitly require every error-swallowing `try?` to log via AppLog.error/AppLog.warning, so the pattern is forbidden, not endorsed. Other `try? removeItem` sites in the repo are pre-write/pre-move cleanup where failure is expected, and they don't override the explicit written rule. The suggested per-file do/catch with AppLog.warning matches the method's existing logging style. Severity lowered to low: the consequence is leftover Inbox files with no diagnostic trail, an observability gap rather than something that misleads readers into bugs.

</details>

### [LOW] 0.5s paging cooldown literal duplicated and enforced via perform(afterDelay:)

`MuseAmp/Interface/Root/PopupBarPagingHandler.swift:55` · named-constants

**问题**: The cooldown interval appears twice and must stay in sync: `cooldownDate = Date().addingTimeInterval(0.5)` (line 55) and `perform(#selector(deferredSyncAfterPaging), with: nil, afterDelay: 0.5)` (line 63). If one changes without the other, the cooldown gate (`isCooldownActive`) and the deferred resync fire out of step. Additionally, the run-loop `NSObject.cancelPreviousPerformRequests` + `perform(afterDelay:)` pair is the only selector-timer in this scope; the repo's established cancellable-delay idiom is a stored Task with `Task.sleep` (AGENTS.md Search Rules; SceneDelegate.importCoalesceTask).

**建议**: Hoist `private static let pagingCooldownInterval: TimeInterval = 0.5` and use it at both sites; optionally replace the perform(afterDelay:) machinery with a cancellable `Task` + `Task.sleep` to match the repo's debounce idiom.

<details><summary>验证记录</summary>

Confirmed at lines 55 and 63 of MuseAmp/Interface/Root/PopupBarPagingHandler.swift: the 0.5s interval appears twice and the two sites are genuinely coupled — the cooldownDate gate and the deferred resync must use the same interval or the gate and resync fire out of step. The perform(afterDelay:)/cancelPreviousPerformRequests pair is unique in the repo; the dominant cancellable-delay idiom is a stored Task + Task.sleep (SceneDelegate.importCoalesceTask, search debounceTask per AGENTS.md Search Rules). AGENTS.md endorses the Date = .distantPast cooldown-gate pattern (Property Rules) but says nothing endorsing duplicated inline interval literals or selector timers, so conventionEndorsed=false. Hoisting a named constant matches existing file style (private static let placeholderArtwork) and violates no rule. Severity stays low: two literals eight lines apart in one short method — a sync hazard, not an active bug.

</details>

### [LOW] Popup-bar frame math duplicated with magic 3/5 width fraction

`MuseAmp/Interface/Root/PopupBarSplitViewController.swift:12` · seams-duplication

**问题**: `popupBarLayoutFrameForPopupBar` (lines 8-14) and `animatePopupBarToCurrentLayout` (lines 24-28) independently re-derive sidebarWidth/availableWidth/`availableWidth * 3.0 / 5.0`/origin-x. If the two formulas drift, the animation lands the bar at a frame inconsistent with the layout override. The 3.0/5.0 fraction is unnamed in both places. (The file is also the only one in scope missing the standard `//  File.swift  MuseAmp` header comment.)

**建议**: Extract `private func popupBarFrame(sidebarVisible: Bool) -> CGRect` used by both the override and the animator, with a named `private static let popupBarWidthFraction: CGFloat = 0.6`; add the standard file header.

<details><summary>验证记录</summary>

Verified in MuseAmp/Interface/Root/PopupBarSplitViewController.swift: the layout override (lines 6-15) and animatePopupBarToCurrentLayout (lines 24-28) each re-derive sidebarWidth/availableWidth, the unnamed 3.0/5.0 width fraction, and the centered origin-x; the animator's no-sidebar branch is just the sidebarWidth==0 case of the same formula, so the two must be kept in sync manually. The 'dont touch it' comment covers only the DispatchQueue.main.async animation hop, not the frame math, so a shared popupBarFrame(sidebarVisible:) helper with a named fraction is safe and matches repo style. The file is also the only one in Interface/Root/ lacking the standard file header that all 9 sibling files carry. AGENTS.md neither mandates nor endorses inline magic fractions or duplicated geometry; the fix would read like the rest of the repo. Severity remains low: single small file, duplication visible side by side, no evidence of an existing drift bug.

</details>

### [LOW] Unlabeled 4-tuple of (UIViewController, String, String, String) for tab specs

`MuseAmp/Interface/Root/TabBarController.swift:190` · naming

**问题**: `setupWithViewControllers` models tab specs as `[(UIViewController, String, String, String)]` — three positionally-distinguished strings (title, SF Symbol name, identifier). A reordered element compiles fine and produces a tab titled "square.stack". The destructure names at line 200 help, but the declaration itself conveys nothing.

**建议**: Use a labeled tuple `(controller: UIViewController, title: String, systemImage: String, identifier: String)` or a tiny private struct TabSpec.

<details><summary>验证记录</summary>

Confirmed at TabBarController.swift:190: `[(UIViewController, String, String, String)]` with three positionally-distinguished strings (title, SF Symbol, identifier); a reordered element compiles silently. AGENTS.md does not endorse unlabeled tuples, and the dominant repo convention is the opposite — all other tuple arrays use labeled elements (TrackTitleSanitizer `(open:close:)`, LyricParser `(order:line:)`, PlaylistViewController+Search `(playlist:matchingSongNames:)`, LibraryPaths `(from:to:)`). The suggested labeled tuple therefore aligns the code with existing repo style. Severity stays low: single local variable in a legacy iOS 16-17 path, used once, named at the destructure site, no evidence of an actual bug.

</details>

## [clarity] backend-api-library (18)

### [MEDIUM] authenticateTransfer decodes the body before checking HTTP status, opposite of fetchTransferManifest

`MuseAmp/Backend/API/APIClient+Transfer.swift:29` · error-boundaries

**问题**: Line 29 runs `JSONDecoder().decode(SyncAuthResponse.self, from: data)` before the `httpResponse.statusCode == 200` guard at lines 30-31. If the server (or a proxy) returns a non-JSON error body — plain-text 401, HTML 502 — the thrown error is a DecodingError that masks the real HTTP failure, and the catch at line 43 logs a decode failure instead of the status. The sibling fetchTransferManifest handles the identical boundary in the opposite order (status check at lines 64-67, decode at line 68), so the two methods encode contradictory conventions for the same failure mode.

**建议**: Check `httpResponse.statusCode == 200` first and throw SyncTransferError.httpFailure(status, String(data:encoding:)); decode SyncAuthResponse only on the success path (optionally `try?`-decode the failure body just to harvest `message`).

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/API/APIClient+Transfer.swift: authenticateTransfer decodes SyncAuthResponse (line 29) before the statusCode==200 guard (lines 30-35), while siblings fetchTransferManifest (lines 64-68) and downloadTransferTrack (lines 116-122) in the same file check status first — the contradictory-convention claim is exact, and decode-first is the outlier (1 of 3). The masking is reachable against MuseAmp's own SyncServer, which sends plain-text bodies on the /auth connection path (sendPlainResponse for oversized/malformed requests at SyncServer.swift lines 251-255 and 425-429), turning an HTTP failure into a DecodingError that the line-43 catch logs as a decode error. The only defense — harvesting authResponse.message for the JSON 401 wrong-password response — is preserved by the suggestion's optional try?-decode of the failure body, so the fix loses nothing and aligns the method with the file's dominant convention. AGENTS.md contains no guidance endorsing decode-before-status. Medium severity holds: contradictory sibling conventions actively mislead maintainers and the masking degrades diagnostics on real server paths, though the common 401 case still works correctly.

</details>

### [MEDIUM] downloadTransferTrack pre-creates a dead empty file and its `fractionCompleted` callback fires exactly once with 1

`MuseAmp/Backend/API/APIClient+Transfer.swift:112` · function-design

**问题**: Line 112 `FileManager.default.createFile(atPath: destinationURL.path, contents: nil)` creates an empty stub that the fully-buffered `data.write(to: destinationURL)` at line 124 simply replaces; its only effect is forcing the catch-side cleanup (lines 131-133) to delete an empty file. Meanwhile the parameter `progress: (@MainActor (_ fractionCompleted: Double) -> Void)?` (line 89) promises incremental download progress but is invoked exactly once with the literal `1` (line 127) after the entire body is already in memory via performRequest/session.data — the signature advertises streaming behavior the implementation cannot deliver.

**建议**: Either stream via URLSession bytes/download APIs and report real fractions, or remove the createFile pre-allocation and rename the callback to reflect reality (e.g. drop it or call it `onComplete`), so the signature stops promising granularity it does not have.

<details><summary>验证记录</summary>

All cited facts verified in MuseAmp/Backend/API/APIClient+Transfer.swift: line 112 pre-creates an empty file (return value ignored) that line 124's fully-buffered data.write immediately replaces — its only effect is making the catch block delete an empty stub; and the `fractionCompleted` progress callback (line 89) fires exactly once with literal 1 (line 127) after the whole body is in memory. The misleading signature has demonstrably propagated: MuseAmpTV/Backend/Sync/TVSessionStateAdapter.swift:369-377 wrote real interpolation math `(completed + fractionCompleted)/total` expecting genuine fractions that never arrive, while the iOS caller discards the parameter. The repo's own convention (DownloadManager+Digger.swift) reports real fractional progress, so the suggestion aligns with local style; AGENTS.md does not endorse the flagged pattern. Medium severity stands: it actively misleads readers and already induced dead granularity logic in a consumer, though no correctness bug results (math degenerates to current/total).

</details>

### [MEDIUM] extractString duplicates EmbeddedMetadataReader.stringValue and the asset is parsed twice per import

`MuseAmp/Backend/Library/AudioFileImporter.swift:393` · seams-duplication

**问题**: AudioFileImporter.extractString(in:matching:) (lines 393-408) is a near-verbatim copy of EmbeddedMetadataReader.stringValue(in:matching:) (EmbeddedMetadataReader.swift:103-120), missing only the `.load(.value) as? String` fallback, even though the importer already holds a `metadataReader` property. importSingleFile uses its own copy to extract title/artist/album for dedup decisions (lines 204-206), then calls metadataReader.makeTrackRecord(fileURL:) (line 248) which re-creates the AVURLAsset, re-loads duration, and re-collects all metadata items (EmbeddedMetadataReader.swift:54-61) to extract the same strings again with the other implementation. Two parallel extraction implementations feed the dedup key and the persisted record respectively, and the whole file is parsed twice per import.

**建议**: Expose one canonical string-extraction API (on EmbeddedMetadataReader or AVMetadataHelper) and delete AudioFileImporter.extractString; add a makeTrackRecord overload accepting pre-collected metadata items + duration so the asset is loaded once per file.

<details><summary>验证记录</summary>

Verified against source: AudioFileImporter.extractString (393-408) duplicates EmbeddedMetadataReader.stringValue (103-120) minus the .load(.value) fallback, and importSingleFile parses the asset twice (lines 179-182 + makeTrackRecord at 248 re-creating the asset and re-collecting metadata at EmbeddedMetadataReader 54-61). The missing fallback means the dedup/.noMetadata gate (line 208) can reject files whose strings makeTrackRecord would extract, so the two parallel implementations can genuinely disagree. The importer already holds metadataReader and already uses its pre-collected-items API (extractLyrics(from:) at line 266), so the suggested consolidation matches existing module conventions. AGENTS.md does not endorse the duplication. Medium severity stands: actively misleading seam plus possible misclassification, but no confirmed shipped bug.

</details>

### [MEDIUM] Catalog-comment predicate and JSON payload parsing re-inlined despite existing canonical helpers

`MuseAmp/Backend/Library/AudioFileImporter.swift:308` · seams-duplication

**问题**: extractCatalogIDs re-inlines the comment-item predicate `item.identifier == .iTunesMetadataUserComment || AVMetadataHelper.matches(item, tokens: ["comment", "cmt"])` (lines 308-309) and the trackID/albumID/artworkURL JSON parsing (lines 311-332). ExportMetadataProcessor already centralizes the predicate as matchesComment (Backend/Downloads/ExportMetadataProcessor.swift:271-274) and parses the same payload (lines 106-107). TrackArtworkRepairService re-inlines the predicate a third time (TrackArtworkRepairService.swift:135-136) plus a third partial JSON parser (lines 84-92), and EmbeddedMetadataReader.lyricsStringValue (EmbeddedMetadataReader.swift:159-160) re-inlines the exact body of ExportMetadataProcessor.matchesLyrics (lines 276-279). The embedded catalog comment now has one producer and three hand-rolled parsers; adding a payload field means editing three files.

**建议**: Hoist a single catalog-comment codec into Backend/Supplement (next to AVMetadataHelper), e.g. `EmbeddedCatalogComment` with matchesComment(_:) and parse(from:) returning trackID/albumID/artworkURL, and reuse it from AudioFileImporter, TrackArtworkRepairService, and ExportMetadataProcessor; likewise reuse matchesLyrics in EmbeddedMetadataReader.

<details><summary>验证记录</summary>

Verified all four cited sites. AudioFileImporter.extractCatalogIDs inlines the comment predicate and full trackID/albumID/artworkURL JSON parse; ExportMetadataProcessor.matchesComment/matchesLyrics exist but are file-private (private extension, line 121), so the predicate is re-inlined in TrackArtworkRepairService (~line 135) and the lyrics predicate body is re-inlined in EmbeddedMetadataReader.lyricsStringValue. The embedded catalog-comment JSON has one producer (ExportMetadataProcessor.catalogMetadataItem) and three independent hand-rolled parsers that have already drifted: the repair-service parser extracts only artworkURL with no isCatalogID validation, while the importer and verifier validate both IDs. Adding a payload field means editing three files. AGENTS.md does not endorse this pattern; it explicitly designates Backend/Supplement for cross-cutting metadata helpers (AVMetadataHelper already lives there) and has an anti-ad-hoc-duplication rule for shared helpers, so the suggested hoist matches repo conventions. Medium severity: real schema-drift/bug-breeding risk, not just cosmetic.

</details>

### [MEDIUM] Two inconsistent encodings of the 2-second duplicate-duration tolerance

`MuseAmp/Backend/Library/AudioFileImporter.swift:161` · named-constants

**问题**: DuplicateKey buckets duration with `Int((duration / 2.0).rounded())` (line 161, comment claims "±1s tolerance") while isDuplicate uses `abs(track.durationSeconds - duration) < 2.0` (line 345), i.e. ±2s. The same concept — "same duration for dedup purposes" — is implemented twice with unlinked magic 2.0 literals and different effective tolerances, so intra-batch dedup and against-DB dedup disagree on which files are duplicates.

**建议**: Define one `private static let duplicateDurationTolerance: TimeInterval = 2` and a single shared predicate (or use DuplicateKey for both checks, e.g. build keys for existing tracks once) so both dedup layers share one definition.

<details><summary>验证记录</summary>

Verified in MuseAmp/Backend/Library/AudioFileImporter.swift. Line 160-161: `// Bucket durations to the nearest 2s so ±1s tolerance matches` / `durationBucket = Int((duration / 2.0).rounded())`. Line 345 (inside isDuplicate): `abs(track.durationSeconds - duration) < 2.0`. The two dedup layers genuinely encode different tolerances with two unlinked 2.0 literals: the DB check accepts any difference under 2s (±2s), while the bucket check only matches files landing in the same 2s-wide bucket (effective tolerance varies from 0 to <2s depending on where values fall relative to bucket boundaries). Concrete disagreement: durations 2.9s and 3.1s differ by 0.2s, so isDuplicate treats them as duplicates, but they bucket to 1 vs 2, so intra-batch dedup treats them as distinct. The line-160 comment ("±1s tolerance") also misdescribes the actual ±2s predicate at line 345, actively misleading a maintainer. Both checks are called back-to-back on the same inputs in importSingleFile (lines 217-233), so a reader is invited to assume they implement one rule when they do not, and editing one literal silently desyncs the other. AGENTS.md contains nothing endorsing duplicated inline tolerance literals; the suggestion (one named tolerance constant plus a shared predicate or key-based comparison) fits the repo's style and the named-constants principle. Caveat: bucketing can never exactly replicate an abs-diff predicate, so the fix should pick one mechanism rather than just sharing the constant, but that does not refute the finding — it reinforces that the current code conflates two non-equivalent encodings. Severity stays medium: the comment is factually wrong and the two layers can disagree on real inputs, which misleads readers and can breed duplicate-import bugs, but no confirmed user-visible bug was demonstrated.

</details>

### [MEDIUM] SyncResult.purged is hardcoded to 0 on every path but rendered in the user-facing summary

`MuseAmp/Backend/Library/SongLibraryIndexer.swift:16` · naming

**问题**: Both return paths of syncLibrary pass `purged: 0` (lines 45 and 50); nothing in the codebase ever computes a purge count. Yet SettingsViewController+Actions.swift:164-165 formats `"Scanned %d, updated %d, removed %d, purged %d"` from this struct, so the UI permanently shows "purged 0" for a metric that does not exist. The field's name promises accounting the type never produces, misleading both maintainers and users.

**建议**: Remove `purged` from SyncResult and from the settings summary string (updating Localizable.xcstrings in the same change), or wire it to a real value carried back by the .rebuildIndex command result.

<details><summary>验证记录</summary>

Confirmed against source. SyncResult.purged (SongLibraryIndexer.swift:16) is hardcoded to 0 on both return paths (lines 45, 50). The upstream LibraryCommandResult.rebuild case only carries (scanned, upserted, deleted) — no purge concept exists anywhere in MuseAmpDatabaseKit (repo-wide grep for "purge" finds nothing). Yet SettingsViewController+Actions.swift:164-165 renders "Scanned %d, updated %d, removed %d, purged %d" from this struct, so users permanently see "purged 0", and four test assertions (SongLibraryIndexerTests.swift:34,64; CatalogIDValidationTests.swift:72,98) tautologically assert purged == 0, reinforcing the illusion that the metric is real. AGENTS.md does not endorse this pattern; its Property Rules discourage stored state with no source of truth and its Localization Rules require removing orphaned keys, so the suggested fix (remove the field and the string, update Localizable.xcstrings) conforms to repo conventions. Severity medium fits: it actively misleads both maintainers (phantom accounting) and end users (a metric that does not exist), and has already produced meaningless tests.

</details>

### [LOW] Every transfer failure is logged twice by nested error paths

`MuseAmp/Backend/API/APIClient+Transfer.swift:33` · error-boundaries

**问题**: Inside the do-blocks, failures are logged and then thrown (e.g. line 33 logs then line 34 throws SyncTransferError.httpFailure), but the throw lands in the same function's own catch which logs the identical failure again (lines 42-43). The same double-log pattern repeats in fetchTransferManifest (line 65 then 78-79) and downloadTransferTrack (line 117 then 130-134), producing two AppLog.error lines per failure and obscuring which log line is the boundary.

**建议**: Log each failure once: let the outer catch be the single error-logging boundary and drop the inner AppLog.error calls before locally-thrown SyncTransferErrors (or log inner-only and rethrow without re-logging).

<details><summary>验证记录</summary>

Confirmed: in APIClient+Transfer.swift, all three transfer functions log failures with AppLog.error inside the do-block guards (lines 33, 37, 65, 70, 117) and then throw SyncTransferError, which lands in the same function's outer catch that logs the identical failure again (lines 43, 79, 134) — two error lines per failure. AGENTS.md Logging Rules only require '.error on failure' (once) and do not endorse double logging. The dominant module convention is the sibling APIClient.swift, where every method logs failures exactly once in the outer catch with no inner pre-throw error logs; the Transfer extension is the deviation. The fix loses no diagnostics because SyncTransferError is LocalizedError and its errorDescription already carries status code, server message, and protocol version, so the outer-catch log retains the detail. The suggestion makes the file consistent with the rest of Backend/API. Severity remains low: log noise and boundary ambiguity, not actively bug-breeding.

</details>

### [LOW] playback(id:) drops to manual 8-field struct reconstruction for URL fix-up

`MuseAmp/Backend/API/APIClient.swift:147` · abstraction-levels

**问题**: Inside the intent-level playback(id:) method, lines 147-159 mix orchestration with low-level mechanics: a `hasPrefix("http")` string test followed by rebuilding PlaybackInfo field-by-field (8 fields copied verbatim) just to absolutize a relative playbackURL. The actual intent — "resolve relative playback URLs against baseURL" — is buried under the copy boilerplate, and any new PlaybackInfo field must be remembered here.

**建议**: Extract a private helper in the existing private extension, e.g. `func resolvingPlaybackURL(_ info: PlaybackInfo, against baseURL: URL) -> PlaybackInfo` (or add a `with(playbackURL:)` copy helper on PlaybackInfo in SubsonicClientKit), keeping playback(id:) at one abstraction level.

<details><summary>验证记录</summary>

Confirmed at APIClient.swift:146-159: playback(id:) mixes intent-level orchestration with an 8-field manual PlaybackInfo reconstruction (forced by the struct's all-let memberwise-init design) just to absolutize a relative URL, while sibling methods (album/song/lyrics) stay at one abstraction level. Not endorsed by AGENTS.md, and the file's own dominant convention contradicts the inline pattern: artwork URL resolution is already extracted into resolveMediaURL, and a private extension exists at line 200 for exactly this kind of helper, so the suggested fix would make the code read MORE like the surrounding module. One overstatement in the finding: a new PlaybackInfo field cannot be silently forgotten here — the memberwise init has no defaults, so the compiler would flag this call site. Hence the issue is genuine but purely cosmetic; severity stays low.

</details>

### [LOW] importSingleFile is a 130-line function mixing many responsibilities

`MuseAmp/Backend/Library/AudioFileImporter.swift:171` · function-design

**问题**: importSingleFile (lines 171-303) does asset inspection, catalog-ID extraction, display-string extraction, three different duplicate checks, destination-path computation, file-attribute reads, record construction, staging-directory creation and copy, lyrics extraction, ImportedTrackMetadata assembly, DB ingest, and rollback cleanup — orchestration interleaved with raw file IO and string formatting. The repo convention is responsibility-based splitting; this function is the single hardest-to-follow block in the scope.

**建议**: Extract focused helpers in the existing private extension, e.g. `duplicateStatus(title:artist:album:duration:existing:batch:)`, `stageCopy(of:fileExtension:)`, and `makeImportMetadata(from:lyrics:)`, leaving importSingleFile as a short orchestration spine of named steps.

<details><summary>验证记录</summary>

Verified: importSingleFile in MuseAmp/Backend/Library/AudioFileImporter.swift spans lines 171-303 (~133 lines) and performs every responsibility the finding enumerates (asset inspection, catalog-ID and display-string extraction, three duplicate checks, path computation, attribute reads, record construction, staging copy, lyrics extraction, metadata assembly, DB ingest, rollback). AGENTS.md does not endorse the pattern — it mandates responsibility-based splitting — and the file's own private extension already extracts focused helpers, so the suggested fix (stageCopy, makeImportMetadata, duplicate-status helper) matches local style rather than violating it. Hence real=true. However, severity is downgraded to low: the body is a strictly linear guard/early-return pipeline with stage-naming AppLog calls at each step, the intricate logic is already in helpers, the inline remainder is mostly declarative field copying, and the order-sensitive parts (three duplicate checks; batchImported.insert only after successful ingest) arguably benefit from staying visible inline. It does not actively mislead readers or demonstrably breed bugs — it is a cosmetic length/abstraction-level improvement.

</details>

### [LOW] `ext.isEmpty ? "m4a" : ext` fallback expression repeated

`MuseAmp/Backend/Library/AudioFileImporter.swift:236` · named-constants

**问题**: The default-extension fallback `ext.isEmpty ? "m4a" : ext` appears twice in importSingleFile: in destinationRelativePath (line 236) and again for stagingURL (line 259). The two occurrences must stay in sync or staging and destination get different extensions.

**建议**: Compute `let resolvedExtension = ext.isEmpty ? "m4a" : ext` once near the top of importSingleFile and use it in both places (also centralizing the "m4a" default literal).

<details><summary>验证记录</summary>

Confirmed: `ext.isEmpty ? "m4a" : ext` appears exactly twice in importSingleFile (lines 236 and 259 of MuseAmp/Backend/Library/AudioFileImporter.swift), the only two occurrences in the repo. Line 236 builds destinationRelativePath (used for the destURL duplicate check and makeTrackRecord's relativePath); line 259 builds the staging file extension for the file actually ingested. Editing one without the other would make the recorded path/duplicate check diverge from the ingested file's extension, so the sync claim holds. AGENTS.md does not endorse this repetition (its only M4A mention is the unrelated CFBundleDocumentTypes rule), and the function already hoists `let ext` to the top, so hoisting a `resolvedExtension` constant matches local style. Impact is cosmetic clarity within a single function, so severity remains low.

</details>

### [LOW] duration-or-nil conversion idiom duplicated three times

`MuseAmp/Backend/Library/AudioTrackRecord+AppModels.swift:20` · seams-duplication

**问题**: The millis conversion `durationSeconds > 0 ? Int((durationSeconds * 1000).rounded()) : nil` is duplicated verbatim in playlistEntry (line 20) and catalogSong (line 30), and a third variant of the same positive-duration-or-nil idiom appears in playbackTrack (line 57: `durationSeconds > 0 ? durationSeconds : nil`). Three sites re-encode the rule "non-positive duration means unknown".

**建议**: Add private computed helpers in this extension, e.g. `var durationMillisOrNil: Int?` and `var durationSecondsOrNil: TimeInterval?`, and use them from all three adapters.

<details><summary>验证记录</summary>

Confirmed: the millis conversion `durationSeconds > 0 ? Int((durationSeconds * 1000).rounded()) : nil` appears verbatim at lines 20 and 30 of AudioTrackRecord+AppModels.swift, and the seconds variant at line 57. Repo-wide grep shows the duplication extends further: PlaylistViewController.swift:284 repeats the exact millis ternary while manually rebuilding a PlaylistEntry instead of using the existing `track.playlistEntry` adapter (call-site reimplementation already occurring), and TVAppContext+Session.swift:214 repeats the seconds variant. AGENTS.md does not endorse inline duplication; its Property Rules explicitly favor computed properties for derived values, so the suggested private computed helpers fit repo conventions and would genuinely centralize the "non-positive duration means unknown" rule. Severity stays low: one-line rule, no manifest bug, but real divergence risk.

</details>

### [LOW] extractArtwork re-implements AVMetadataHelper.matches inline, diverging from hasArtwork in the same file

`MuseAmp/Backend/Library/EmbeddedMetadataReader.swift:27` · seams-duplication

**问题**: extractArtwork hand-builds the identifier/commonKey/key lowercase token matching (lines 24-29), including the unreachable `(item.key as? NSString)?.lowercased` branch copied from AVMetadataHelper.matches (AVMetadataHelper.swift:24 — `as? String` already bridges NSString, so the second cast can never add anything). hasArtwork in the same file (line 174) checks the same ["artwork", "coverart"] tokens via the matches helper. Two artwork-detection predicates now live in one file and can drift independently.

**建议**: Replace lines 24-29 with `guard matches(item: item, tokens: ["artwork", "coverart"]) else { continue }` so both artwork checks share the single helper.

<details><summary>验证记录</summary>

Verified: extractArtwork (EmbeddedMetadataReader.swift:24-29) inlines the exact token-matching logic of AVMetadataHelper.matches (AVMetadataHelper.swift:21-28), including the unreachable NSString fallback, while hasArtwork (line 174) checks the same ["artwork","coverart"] tokens through the matches helper. All five other metadata predicates in the file use the helper, making extractArtwork the sole outlier; the suggested one-line fix conforms to the file's own dominant style and is semantics-preserving (tokens already lowercase, helper accessible from the same file). AGENTS.md does not endorse the duplication. Severity stays low: the predicates currently agree, so this is drift risk, not an active bug.

</details>

### [LOW] Pure pass-through wrappers around AVMetadataHelper

`MuseAmp/Backend/Library/EmbeddedMetadataReader.swift:99` · seams-duplication

**问题**: collectMetadataItems(from:) (lines 99-101) and matches(item:tokens:) (lines 185-187) are zero-behavior pass-throughs to AVMetadataHelper. Sibling files in the same scope call AVMetadataHelper directly (AudioFileImporter.swift:182, 309; TrackArtworkRepairService.swift:136), so the wrappers add an inconsistent indirection layer a reader must step through for no variance in behavior.

**建议**: Delete both private wrappers and call AVMetadataHelper.collectMetadataItems / AVMetadataHelper.matches directly, matching the rest of Backend/Library.

<details><summary>验证记录</summary>

Confirmed: collectMetadataItems(from:) (lines 99-101) and matches(item:tokens:) (lines 185-187) in EmbeddedMetadataReader.swift are pure pass-throughs to AVMetadataHelper with no added behavior. Grep shows all eight other consumer files across Backend/Library, Backend/Downloads, Backend/Lyrics, Backend/Sync, and Interface call AVMetadataHelper directly — this file is the sole outlier. AGENTS.md contains no rule endorsing wrappers around AVMetadataHelper (its wrapper mandates cover only UIView animation helpers), so the dominant convention is direct calls and the suggested deletion aligns the file with the rest of the repo. Severity stays low: the indirection is cosmetic, costing readers one extra hop without misleading them.

</details>

### [LOW] Empty placeholder extension file with no declarations

`MuseAmp/Backend/Library/MusicLibraryDatabase+Bridge.swift:1` · file-organization

**问题**: MusicLibraryDatabase+Bridge.swift contains only the header comment and two imports (9 lines total, zero declarations). The filename promises a "Bridge" responsibility that does not exist, misleading readers navigating the responsibility-split files and polluting search results.

**建议**: Delete the file (and its Xcode group entry) until an actual Bridge responsibility exists; recreate it when there is content to hold.

<details><summary>验证记录</summary>

Verified: MuseAmp/Backend/Library/MusicLibraryDatabase+Bridge.swift contains only a header comment and two imports (9 lines, zero declarations), unchanged since the initial commit. Sibling +Downloads/+Ingest/+Tracks files all hold real code, so the empty +Bridge file misrepresents the responsibility split. AGENTS.md endorses responsibility-based extension files but nothing endorses empty placeholders. The project uses filesystem-synchronized groups, so deletion needs no Xcode group edit. Cosmetic-only impact, so severity remains low.

</details>

### [LOW] Anonymous NSError(domain:code: 3) instead of a typed error

`MuseAmp/Backend/Library/MusicLibraryDatabase+Ingest.swift:15` · error-boundaries

**问题**: ingestAudioFile throws `NSError(domain: "MusicLibraryDatabase", code: 3)` when the command result shape is unexpected. The repo convention everywhere else in this scope is domain-specific LocalizedError enums (SyncTransferError, TrackArtworkRepairService.RepairError, EmbeddedMetadataReaderError). The magic code 3 has no codes 1/2 anywhere in the app target, carries no message, and gives callers and logs nothing actionable.

**建议**: Introduce `enum MusicLibraryDatabaseError: LocalizedError { case unexpectedCommandResult }` (with an errorDescription) and throw that instead of the anonymous NSError.

<details><summary>验证记录</summary>

Confirmed: MusicLibraryDatabase+Ingest.swift line 15 throws anonymous NSError(domain: "MusicLibraryDatabase", code: 3) with no message, and no codes 1/2 exist in that domain anywhere in the app targets. AGENTS.md is silent on error typing, but the dominant convention in the same module (Backend/Library: TrackArtworkRepairService.RepairError, EmbeddedMetadataReaderError; Backend/Sync: SyncTransferError, SyncEndpointParseError) is domain-specific error enums, mostly LocalizedError. Anonymous NSError appears only 3 times codebase-wide (two in bootstrap shims). The suggested typed-enum fix aligns with surrounding style. Severity downgraded to low: the throw guards an effectively unreachable command/result shape mismatch (programming-error path), so it is a diagnosability/clarity nit rather than something that misleads readers or breeds bugs.

</details>

### [LOW] Generic sendCommand transport buried in the +Tracks responsibility file

`MuseAmp/Backend/Library/MusicLibraryDatabase+Tracks.swift:12` · file-organization

**问题**: sendCommand(_:) (lines 12-19) is the generic LibraryCommand routing primitive (sync-if-supported, async fallback) used by other responsibility files — MusicLibraryDatabase+Ingest.swift:13 calls it — yet it lives in the Tracks extension. The split convention is filename = responsibility, and command transport is cross-cutting infrastructure, not a tracks concern; a reader of +Ingest has no reason to look in +Tracks for it. The core MusicLibraryDatabase.swift currently holds only init and stored dependencies.

**建议**: Move sendCommand into MusicLibraryDatabase.swift (the core file) so the command-routing seam lives with the type's stored DatabaseManager dependency.

<details><summary>验证记录</summary>

Verified: sendCommand(_:) (MusicLibraryDatabase+Tracks.swift:12-19) is the generic LibraryCommand routing primitive (sync-if-supported, async fallback) and is consumed cross-file by MusicLibraryDatabase+Ingest.swift:13, while the core MusicLibraryDatabase.swift contains only stored dependencies and init. AGENTS.md mandates responsibility-named extension splits (UIKit File Rules; DatabaseManager layout rule), and command transport is not a tracks responsibility, so the placement contradicts the repo's own dominant convention rather than following it. The suggested move into the core file (next to the stored databaseManager it wraps) is small, convention-aligned, and improves discoverability for readers of +Ingest. Severity stays low: one external caller, easily greppable, no correctness risk — purely a cosmetic clarity/organization issue.

</details>

### [LOW] Inline magic result cap 50 and obscure .map(\.self) slice conversion in searchTracks

`MuseAmp/Backend/Library/MusicLibraryDatabase+Tracks.swift:90` · named-constants

**问题**: Line 90 caps search results with an unexplained inline `.prefix(50)`, and line 91 converts the ArraySlice back to Array via `.map(\.self)` — an identity map that reads as a no-op rather than a type conversion. The 50 encodes a product decision (max local search results) with no name.

**建议**: Hoist `private static let maxSearchResults = 50` (or a file-scope constant) and end the chain with `Array(... .prefix(Self.maxSearchResults))` instead of `.map(\.self)`.

<details><summary>验证记录</summary>

Confirmed at MusicLibraryDatabase+Tracks.swift lines 90-91: `.prefix(50)` is an unnamed search-result cap and `.map(\.self)` is an identity map used solely as an ArraySlice->Array conversion that reads as a no-op. Grep shows `.map(\.self)` occurs exactly once in the repo, while the dominant convention everywhere else is `Array(... .prefix(n))` (PlaybackSnapshot, PlaylistTransferCoordinator, SearchState, MainController+Sidebar, PlaylistCoverArtworkCache), often with named limits (queueLimit, limit, tileCount). The suggested fix therefore aligns the code WITH repo style rather than against it. AGENTS.md does not endorse the flagged pattern (only the unrelated 200pt spacer rule mentions hardcoding). Severity remains low: cosmetic clarity, behavior is correct and the cap is method-local.

</details>

### [LOW] redownloadArtworkData re-implements DownloadArtworkProcessor.cachedArtworkData's download+cache-write and hides the cache side effect

`MuseAmp/Backend/Library/TrackArtworkRepairService.swift:153` · seams-duplication

**问题**: redownloadArtworkData (lines 153-182) downloads artwork and atomically writes it to `paths.artworkCacheURL(for: trackID)` — the same behavior as DownloadArtworkProcessor.cachedArtworkData (Backend/Downloads/DownloadArtworkProcessor.swift:71-86), which AudioFileImporter already reuses (AudioFileImporter.swift:426). The two copies have already drifted: the repair version validates HTTP status (lines 162-166) while cachedArtworkData caches whatever bytes arrive, including error bodies. The name `redownloadArtworkData` also hides the persistent cache-write side effect at lines 174-180.

**建议**: Add a cache-bypass/forceRefresh parameter (plus the HTTP-status validation) to DownloadArtworkProcessor.cachedArtworkData and call it from the repair service; if a local method must remain, rename it to name the side effect, e.g. downloadAndCacheArtworkData.

<details><summary>验证记录</summary>

Cited code confirmed: redownloadArtworkData (TrackArtworkRepairService.swift:153-182) downloads and atomically writes to paths.artworkCacheURL(for:), overlapping DownloadArtworkProcessor.cachedArtworkData (DownloadArtworkProcessor.swift:71-86), which every other caller (AudioFileImporter.swift:426, SyncPreparedTrackBuilder+Export.swift:117/171) reuses — so the repo's dominant convention is reuse, not per-service copies, and AGENTS.md does not endorse the duplication. The divergence is also confirmed: the repair copy validates HTTP status and non-empty data while cachedArtworkData caches even error bodies, meaning two policies populate the same cache path and a future cache fix would likely miss one site. However, severity is overstated: most differences are deliberate repair semantics (must bypass cache, supports file URLs, repair-specific errors), the true overlap is ~5 lines, the cache write is plainly visible inside a 30-line private helper, and the suggested forceRefresh-flag consolidation would change behavior at three other call sites and introduce a boolean-flag smell. The cheap legitimate fix is the rename (e.g., downloadAndCacheArtworkData) and/or sharing the cache-write seam. Real, but cosmetic-leaning: low.

</details>

## [clarity] backend-downloads (22)

### [HIGH] intentionallyPaused set silently diverges from task state

`MuseAmp/Backend/Downloads/DownloadManager.swift:83` · state-modeling

**问题**: The download lifecycle is tracked in two places at once: ActiveDownloadTask.state and the parallel `intentionallyPaused: Set<String>`. Inserts happen in pauseAll (DownloadManager.swift:252) and in handleNetworkChange cellular/none branches (DownloadManager+Network.swift:66, 83), but removals only happen in resumeAll (:268, and only for .paused tasks), cancelTask (:316), and the Digger success path (DownloadManager+Digger.swift:126). The two resume paths for network-deferred tasks — the .wifi branch of handleNetworkChange (DownloadManager+Network.swift:47-51) and allowCellularDownload (DownloadManager.swift:331-344) — flip state back to .waiting but never remove the trackID from intentionallyPaused. A task that was once network-deferred keeps stale membership forever, so a later genuine NSURLErrorCancelled from Digger hits the early return at DownloadManager+Digger.swift:130 and is silently swallowed, leaving the task stuck in .downloading. This is the classic hidden-state-machine smell: one lifecycle spread over a flag set plus an enum, with no single point keeping them consistent.

**建议**: Either derive the 'this cancel was ours' check from the task's current state (state == .paused || state == .waitingForNetwork at completion time) and delete the set, or centralize every state transition through one mutator that updates state and intentionallyPaused together so the two can never disagree.

<details><summary>验证记录</summary>

Every factual claim verified against source. Inserts into intentionallyPaused occur in pauseAll (DownloadManager.swift:252) and the cellular/none branches of handleNetworkChange (DownloadManager+Network.swift:66, :83). Removals occur only in resumeAll (:268, gated on state == .paused so .waitingForNetwork tasks are skipped), cancelTask (:316), and the Digger success path (DownloadManager+Digger.swift:126). The two network-resume paths — the .wifi branch (Network.swift:46-52) and allowCellularDownload (DownloadManager.swift:335-341) — flip state back to .waiting without removing the entry, so a once-deferred task keeps stale membership through its restarted download (startResolving at Queue.swift:50-59 restarts Digger with the entry still present). A subsequent genuine NSURLErrorCancelled then hits the early return at Digger.swift:130-132, bypassing the unexpected-cancel retry/fail recovery at :133-156 (which exists precisely because genuine cancels occur), leaving the task stuck in .downloading and permanently occupying an activeCount concurrency slot. This is a real hidden-state-machine divergence, not a stylistic nitpick. AGENTS.md does not endorse the pattern; its Property Rules ('Do not introduce stored properties to track state that is already available from an existing source of truth') actively support the suggested fix of deriving the our-cancel check from task.state (.paused/.waitingForNetwork) at completion time, which is feasible since state is mutated before stopTask and completions arrive async on main. The fix matches the module's dominant enum-state-guard style. Severity stays high: the inconsistency has already bred a dormant silent-failure bug and constitutes a hidden invariant that blocks safe modification of pause/resume logic.

</details>

### [MEDIUM] Dead apiClient parameter threaded through artwork pipeline

`MuseAmp/Backend/Downloads/DownloadArtworkProcessor.swift:74` · function-design

**问题**: `cachedArtworkData(trackID:artworkURL:apiClient:locations:session:)` declares `apiClient _: APIClient?` and never uses it, yet three external call sites thread a real client into it (MuseAmp/Backend/Library/AudioFileImporter.swift:426, MuseAmp/Backend/Sync/SyncPreparedTrackBuilder+Export.swift:117 and :171), and `prepareDownloadedTrack` (line 19) accepts `apiClient: APIClient?` solely to forward it into the ignored slot. Readers must trace the whole chain to learn the dependency is fictional.

**建议**: Remove the apiClient parameter from cachedArtworkData and prepareDownloadedTrack, and drop the argument at the four call sites (including DownloadManager+Digger.swift:226-232).

<details><summary>验证记录</summary>

Confirmed: cachedArtworkData declares `apiClient _: APIClient?` (line 74) and never uses it (body uses only locations + raw URLSession); prepareDownloadedTrack (line 19) accepts apiClient solely to forward it into the ignored slot (line 31). All four external call sites verified threading a real client in (AudioFileImporter.swift:426, SyncPreparedTrackBuilder+Export.swift:117 and :171, DownloadManager+Digger.swift:226-232), two of them even adding explicit `let apiClient = apiClient` capture bindings just to feed the dead parameter. Git history shows the parameter was dead from the initial commit. AGENTS.md nowhere endorses unused threaded dependencies; its Dependency Rules ("APIClient is the only app-level network orchestration entry point") make the fictional dependency actively misleading — readers would assume the artwork fetch goes through APIClient when it actually uses bare URLSession.shared. No protocol/override constraint requires the signature. The fix is local, conventional, and improves clarity. Medium severity stands: it misleads readers about the network path for artwork fetches.

</details>

### [MEDIUM] DownloadArtworkProcessor doubles as a generic AV export utility under an artwork-only name

`MuseAmp/Backend/Downloads/DownloadArtworkProcessor.swift:125` · class-design

**问题**: Beyond artwork, this enum hosts the project's generic AV export plumbing: `withOverallTimeout` (line 125), `export(_:timeout:)` (line 219), `resolveOutputFileType` (line 267), `temporaryOutputURL` (line 285), and a pure pass-through `collectMetadataItems` (lines 211-213) that just forwards to AVMetadataHelper. ExportMetadataProcessor depends on it at seven sites (ExportMetadataProcessor.swift:55, 145, 151, 167, 170, 186, 204) for behavior that has nothing to do with downloads or artwork, and even uses AVMetadataHelper directly at :95 while going through the pass-through at :151. The type name misstates its actual responsibility, so readers looking for the shared export/timeout helpers will not find them under 'DownloadArtworkProcessor'.

**建议**: Move withOverallTimeout, export(_:timeout:), resolveOutputFileType, and temporaryOutputURL into a neutral helper in Backend/Supplement (e.g. AVExportHelper, beside the existing AVMetadataHelper), delete the collectMetadataItems pass-through in favor of calling AVMetadataHelper directly, and leave DownloadArtworkProcessor artwork-only.

<details><summary>验证记录</summary>

All cited code verified: DownloadArtworkProcessor.swift hosts generic helpers withOverallTimeout (l.125), export(_:timeout:) (l.219), resolveOutputFileType (l.267), temporaryOutputURL (l.285), and a one-line pass-through collectMetadataItems (l.211-213) that forwards to AVMetadataHelper. ExportMetadataProcessor depends on it at exactly the seven cited lines and inconsistently calls AVMetadataHelper directly at :95 while using the pass-through at :151. Cross-domain reach is even wider than claimed: Backend/Library/TrackArtworkRepairService, Backend/Library/AudioFileImporter, Backend/Sync/SyncPreparedTrackBuilder+Export, and tests all reach into this Downloads-folder artwork enum, including for the generic timeout helper. AGENTS.md does not endorse this; it designates Backend/Supplement for cross-cutting utilities and AVMetadataHelper/ConcurrencyHelpers already live there, so the suggested AVExportHelper fix matches the repo's existing convention. Minor caveat: two of the seven dependency sites (artworkMetadataItems, matchesArtwork) are legitimately artwork-related, but the core claim stands — shared export/timeout plumbing is hidden under an artwork-only download name, which misleads readers and has already produced inconsistent call patterns and duplicated export bodies between the two processors.

</details>

### [MEDIUM] Digger URL bookkeeping cleanup duplicated at four call sites

`MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:122` · seams-duplication

**问题**: The two-line pair `hasMarkedDownloading.remove(url); diggerStartedURLs.remove(url)` is repeated verbatim at DownloadManager+Digger.swift:123-124, :145-146, :161-162, and DownloadManager.swift:286-287 (retryFailed). Each site re-implements the same 'forget everything Digger knew about this URL' behavior inline; a future fix (e.g. also clearing intentionallyPaused or Digger's cache) must be applied four times.

**建议**: Extract one helper on DownloadManager, e.g. `func clearDiggerBookkeeping(for url: URL)`, and call it from all four sites.

<details><summary>验证记录</summary>

Confirmed verbatim: the `if let url = task.url { hasMarkedDownloading.remove(url); diggerStartedURLs.remove(url) }` block appears at DownloadManager+Digger.swift:122-125, 144-147, 160-163 and DownloadManager.swift:285-288. The refutation attempt backfired: cancelTask (DownloadManager.swift:309) is a fifth site that should clear this bookkeeping but does not, leaving stale diggerStartedURLs entries that steer startResolving (DownloadManager+Queue.swift:54) into the resume branch instead of a fresh startDiggerDownload on re-download of the same URL — exactly the missed-site bug class the finding predicts. AGENTS.md does not endorse inline repetition; it favors shared helpers and the module already uses small helper methods, so the suggested clearDiggerBookkeeping(for:) extraction fits local style. Medium severity is justified: the duplication has plausibly already bred an inconsistency.

</details>

### [MEDIUM] startFinalizing mixes staging I/O, state transition, and the whole finalization pipeline

`MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:171` · function-design

**问题**: startFinalizing (lines 171-281) is a 110-line function that (1) performs FileManager staging moves with its own error path, (2) mutates task state and persists, (3) manually captures eight properties into locals (lines 216-224) to feed (4) a 56-line Task closure that orchestrates artwork, lyrics, metadata embedding, and library ingestion. The detached pipeline body also drops to the string-literal logger (`AppLog.info("DownloadManager", ...)` at lines 249-252) unlike the rest of the type. Raw file moves and a multi-step async pipeline sit at very different abstraction levels in one scope.

**建议**: Split into `stageForFinalization(trackID:fileURL:) -> URL?` (the moves + failure handling) and a named method like `runFinalizationPipeline(for task: ActiveDownloadTask, ingestURL: URL)` containing the Task body, so each piece does one thing and the captures become parameters.

<details><summary>验证记录</summary>

Verified against the file: startFinalizing (lines 171-281) is ~110 lines mixing a conditional FileManager staging move with its own complete failure path (duplicating handleCompletion's markFailed/persist/publish/processNext sequence), state transition + persistence, a manual eight-property capture block (216-224), and a 56-line Task closure running the artwork/lyrics/metadata/ingestion pipeline. The logger inconsistency is real: lines 249-253 are the only string-literal AppLog calls in Backend/Downloads (forced by weak self in the closure, but still divergent from the type's AppLog.x(self, ...) convention). AGENTS.md (identical to CLAUDE.md) does not endorse this pattern; it explicitly favors responsibility-based splitting, and the module's own convention (DownloadManager split into +Digger/+Queue/+Network/+Persistence plus standalone processor types) supports the suggested decomposition. ActiveDownloadTask is a nonisolated value struct, so the proposed runFinalizationPipeline(for:ingestURL:) is directly implementable and would replace the ad-hoc captures with parameters without violating any repo rule. Severity stays medium: the duplicated staging-failure path and buried, asymmetric pipeline error handling (embed failure only warns; ingest failure routes to completeFinalization) genuinely complicate safe modification, though no existing bug was found.

</details>

### [MEDIUM] Unnamed -1 sentinel encodes indeterminate progress across modules

`MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:51` · named-constants

**问题**: handleProgress assigns `-1` to task.progress when totalUnitCount is unknown (line 51), then clamps with `max(fraction, 0)` for persistence (line 58). The UI relies on this implicit contract: MuseAmp/Interface/Browse/Downloads/DownloadsViewController.swift:523 renders `task.progress >= 0 ? "...%" : ""`. Nothing on ActiveDownloadTask documents that progress can be negative, so any new consumer of `progress` (formatting, sorting, persistence) can silently mishandle the sentinel.

**建议**: Define `static let indeterminateProgress: Double = -1` on ActiveDownloadTask plus a computed `var isProgressIndeterminate: Bool { progress < 0 }`, and use them at both the producer (handleProgress) and the UI consumer.

<details><summary>验证记录</summary>

Verified: DownloadManager+Digger.swift:47-52 assigns -1 as an undocumented indeterminate-progress sentinel on ActiveDownloadTask.progress, clamped ad hoc at line 58 (max(fraction, 0)) for persistence. The sentinel crosses the Backend->Interface boundary and is independently re-handled at DownloadsViewController.swift:523 (>= 0 check before formatting "%") and a third site the finding missed, DownloadProgressCell.layoutSubviews (max(currentProgress, 0)) — three scattered defenses against an implicit contract that ActiveDownloadTask (DownloadManager.swift:23, plain `var progress: Double`) never documents. All other writes in the module use plain 0/1 fractions, so a new consumer could plausibly render -100% or mis-sort. AGENTS.md (identical to CLAUDE.md) does not endorse sentinel literals; its Property Rules favor computed derived state, so the suggested named constant + isProgressIndeterminate computed property is repo-idiomatic and a genuine clarity improvement. No existing bug found (all current consumers clamp correctly), so severity stays medium rather than high.

</details>

### [MEDIUM] Three near-identical ActiveDownloadTask rehydration constructors

`MuseAmp/Backend/Downloads/DownloadManager+Queue.swift:145` · seams-duplication

**问题**: rehydrateQueuedRecord (lines 145-160), rehydrateFailedRecord (lines 169-185), and rehydrateFinalizingRecord (lines 223-238) each build an ActiveDownloadTask from a DownloadJob with the same 13 arguments — including the repeated `apiClient.mediaURL(from: record.artworkURL, width: 600, height: 600)` — differing only in state, progress, and lastError. Any change to the record-to-task mapping (a new field, different artwork sizing) must be edited in three places.

**建议**: Extract a private helper, e.g. `func makeTask(from record: DownloadJob, destPath: String, state: ActiveDownloadTask.State, progress: Double = 0, lastError: String? = nil) -> ActiveDownloadTask`, and have the three rehydrate methods pass only the varying fields.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Backend/Downloads/DownloadManager+Queue.swift: rehydrateQueuedRecord (lines 145-160), rehydrateFailedRecord (lines 169-185), and rehydrateFinalizingRecord (lines 223-237) each construct an ActiveDownloadTask from a DownloadJob with the identical 10-field record-to-task mapping, including the triplicated `apiClient.mediaURL(from: record.artworkURL, width: 600, height: 600)` call and `queueOrder: allocateQueueOrder()`. They differ only in state (.waiting/.waitingForNetwork vs .failed vs .finalizing), progress (0/0/1), and lastError (only the failed path passes it). Refutation attempts failed: (1) the fourth ActiveDownloadTask construction at DownloadManager.swift:220 builds from a SubmitRequest, not a DownloadJob, so it does not generalize the helper away but also does not excuse the three record-based copies; (2) AGENTS.md (byte-identical to project CLAUDE.md) nowhere endorses repeated construction — it actually concentrates the risk by mandating 600x600 artwork via apiClient.mediaURL, meaning a sizing or resolution change must be hand-edited in three places; (3) a private `makeTask(from:destPath:state:progress:lastError:)` helper is fully consistent with the module's style (responsibility-split extensions, small helper funcs like allocateQueueOrder/finalizingURL) and violates no rule. Drift risk is concrete: a new ActiveDownloadTask field with a default value would compile silently while leaving one or two rehydrate paths unmapped (lastError already shows this asymmetry). Severity medium is fair — this is a live shotgun-surgery seam in persistence rehydration, not mere cosmetics, though no bug has demonstrably shipped from it yet.

</details>

### [MEDIUM] submitRequests re-implements LibraryPaths.inferredRelativePath inline

`MuseAmp/Backend/Downloads/DownloadManager.swift:202` · seams-duplication

**问题**: Lines 202-204 build the destination path by hand: `sanitizePathComponent(request.albumID)` + `sanitizePathComponent(request.trackID) + ".m4a"` joined with "/". This is byte-for-byte the logic of `LibraryPaths.inferredRelativePath(for:albumID:)` (MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Storage/LibraryPaths.swift:94-98), which this same type already calls in rehydrateQueuedRecord (DownloadManager+Queue.swift:120). Two implementations of the canonical path layout can drift (e.g. if sanitization or extension handling changes in LibraryPaths).

**建议**: Replace the three inline lines with `let destPath = paths.inferredRelativePath(for: request.trackID, albumID: request.albumID)`.

<details><summary>验证记录</summary>

Confirmed: DownloadManager.swift:202-204 inlines exactly the logic of LibraryPaths.inferredRelativePath (LibraryPaths.swift:94-98); output is byte-identical with the default "m4a" extension since both use the shared sanitizePathComponent. The same type already has `paths: LibraryPaths` (line 62) and already calls paths.inferredRelativePath in DownloadManager+Queue.swift:120, so the inline version is inconsistent even within DownloadManager itself and the suggested fix is a drop-in equivalent. AGENTS.md does not endorse inline path construction; other inline occurrences (AudioFileImporter, DownloadCoordinator, LibraryFileManager) are further duplication, not a deliberate convention, and one already shows mild drift in extension fallback. Minor correction to the finding: sanitization itself is shared and cannot drift — only the join format and extension handling can — but since targetRelativePath is persisted in DownloadJob records, format drift would orphan files, so the risk is real. Medium severity holds: mixed usage within one type misleads readers about which path construction is canonical.

</details>

### [MEDIUM] Full 14-field DownloadJob re-inits just to change status

`MuseAmp/Backend/Downloads/DownloadManager.swift:130` · seams-duplication

**问题**: Because DownloadJob is all-let, requeueing a record requires re-listing every field. This 14-argument copy-with-one-change appears three times: reconcileOnLaunch (DownloadManager.swift:130-145, status -> .queued), rehydrateQueuedRecord (DownloadManager+Queue.swift:125-142, new targetRelativePath), and rehydrateFinalizingRecord (DownloadManager+Queue.swift:201-216, status -> .queued, progress -> 0). The intent (one field changed) is buried under 13 lines of pass-through, and a newly added DownloadJob field with a default would silently be dropped at these sites.

**建议**: Add a copy helper in the Downloads scope, e.g. `extension DownloadJob { func updating(status:..., targetRelativePath:..., progress:...) -> DownloadJob }` (or make DownloadJob conform to Then and use `.with {}` after switching fields to var), and use it at all three sites.

<details><summary>验证记录</summary>

All three cited copy sites verified (DownloadManager.swift:130-145, DownloadManager+Queue.swift:125-141 and 201-216). DownloadJob is an all-let 15-field struct with 10 defaulted init params, and each site re-lists every field to change 1-2 values. The predicted field-drop hazard has already materialized: two of the three copies silently reset sourceURL to nil via the init default while the third explicitly preserves it, leaving the intent ambiguous. AGENTS.md does not endorse full memberwise re-inits; it favors value types, helper extensions, and Then's .with {} for value-type copy-modify, so an updating(...) copy helper fits repo conventions while preserving immutability. The fourth DownloadJob init (persistRecord) is a genuine type conversion and unaffected. Medium severity is appropriate: the pattern actively misleads readers (inconsistent sourceURL handling) and breeds bugs on field addition, but no confirmed runtime bug since requeued tasks re-resolve URLs anyway.

</details>

### [MEDIUM] storageSize takes an audioDirectory parameter it ignores

`MuseAmp/Backend/Downloads/DownloadStore.swift:81` · function-design

**问题**: `storageSize(forTrackIDs:audioDirectory:)` declares `audioDirectory _: URL` — the wildcard discards it; the body resolves paths via the stored `paths` property instead. The only app caller (MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift:197-200) dutifully passes `environment.paths.audioDirectory` for nothing. The signature lies about what influences the result.

**建议**: Delete the parameter (`func storageSize(forTrackIDs trackIDs: Set<String>) -> Int64`) and update the call site and DownloadStoreFacadeTests accordingly.

<details><summary>验证记录</summary>

Confirmed at DownloadStore.swift:81 — `audioDirectory _: URL` is discarded; the body uses the stored `paths` property, same as siblings `isDownloaded` and `localLibraryStorageSize` which take no directory. No protocol/delegate contract forces the signature (the class conforms to nothing). The app caller (AlbumDetailViewController.swift:197-200) and both DownloadStoreFacadeTests tests pass `paths.audioDirectory` pointlessly; a caller passing a different directory would silently get results computed against the store's own paths. AGENTS.md does not endorse the pattern, and the dominant local convention (parameterless siblings using stored paths) supports the fix, which makes the method read like the rest of the file.

</details>

### [MEDIUM] ExportError is file-private but thrown across feature boundaries

`MuseAmp/Backend/Downloads/ExportMetadataProcessor.swift:214` · error-boundaries

**问题**: `enum ExportError` is declared inside `private extension ExportMetadataProcessor` (line 121/214), yet it escapes through internal API: `validateExportInfo` throws .invalidTrackID/.invalidAlbumID/.missingTitle/.missingArtist and is called from Backend/Sync/SyncPreparedTrackBuilder+Export.swift:112,166 and Backend/Lyrics/LyricsReloadService.swift:166; `verifyEmbeddedMetadata` throws .verificationFailed and is called from tests. Those callers (and tests) receive errors whose type they cannot name, so they cannot pattern-match specific failures and tests cannot assert which case was thrown — the error boundary is invisible at the API surface.

**建议**: Move ExportError out of the private extension into the main `enum ExportMetadataProcessor` body (internal access), keeping the cases as the documented failure contract of validateExportInfo/embedExportMetadata/verifyEmbeddedMetadata.

<details><summary>验证记录</summary>

Confirmed: ExportError (line 214) sits in a private extension (fileprivate) yet is thrown across feature boundaries by internal API validateExportInfo/verifyEmbeddedMetadata, consumed from Backend/Sync/SyncPreparedTrackBuilder+Export.swift:112,166, Backend/Lyrics/LyricsReloadService.swift:166, and tests. Concrete harm already exists: ExportMetadataProcessorTests.swift:281 ('throws fileUnreadable for nonexistent file') can only assert (any Error).self, so it cannot verify the case it is named after and would pass on any error. The fix matches the dominant module convention — sibling DownloadArtworkProcessor declares ProcessingError in a non-private extension (internal), as do SyncTransferError, RepairError, etc. AGENTS.md neither mandates nor endorses private error enums; no rule conflicts with the suggestion. Severity stays medium: no production bug (callers only log/propagate), but the invisible error contract has already weakened tests and misleads readers about the API surface.

</details>

### [MEDIUM] ConnectionType.wifi actually means any non-cellular connection

`MuseAmp/Backend/Downloads/NetworkMonitor.swift:36` · naming

**问题**: The path mapping treats wiredEthernet as `.wifi` (line 36) and any other satisfied interface also falls through to `.wifi` (line 41). Downstream code reads `networkMonitor.isWiFi` (e.g. DownloadManager.resumeAll, DownloadManager.swift:274) and the deferral logic keys off `.wifi`/`.cellular` — on Mac Catalyst (a first-class destination in this repo) 'WiFi' is routinely Ethernet. The case name misleads readers into thinking the check is literally about WiFi when the real semantic is 'unmetered/non-cellular'.

**建议**: Rename the case to `.unmetered` (and `isWiFi` to `isUnmetered`), or keep three honest cases (.wifi, .wiredEthernet, .cellular, .none) with an `isUnmetered` computed property used by the deferral logic.

<details><summary>验证记录</summary>

Verified: NetworkMonitor.swift line 36 maps wiredEthernet to .wifi and line 41 maps any other satisfied interface to .wifi, so the case truly means "satisfied non-cellular". Consumers read the literal name (DownloadManager.swift:274 isWiFi; DownloadManager+Network.swift:42/99 case .wifi) and the log at DownloadManager+Network.swift:53 says "WiFi available" — false on a wired Catalyst Mac, and Catalyst is a first-class destination per AGENTS.md. User-facing strings frame the feature as cellular-vs-not, confirming the honest semantic is unmetered. AGENTS.md contains no convention endorsing this naming. The suggested rename is small, local, and consistent with repo style. Behavior is correct, so this is clarity-only, but the name actively misleads readers and diagnostics, justifying medium.

</details>

### [LOW] 30-second export timeout duplicated across files

`MuseAmp/Backend/Downloads/DownloadArtworkProcessor.swift:89` · named-constants

**问题**: The same default AV export timeout appears as `withOverallTimeout(seconds: 30)` (DownloadArtworkProcessor.swift:89), `timeout: TimeInterval = 30` (DownloadArtworkProcessor.swift:111), and `timeout: TimeInterval = 30` (ExportMetadataProcessor.swift:53). Three unrelated-looking literals encode one policy; tuning it requires finding all three.

**建议**: Define a single `static let defaultExportTimeout: TimeInterval = 30` (in the shared export helper, see the class-design finding) and reference it from all three signatures.

<details><summary>验证记录</summary>

All three cited literals exist (DownloadArtworkProcessor.swift:89 hardcoded `withOverallTimeout(seconds: 30)`, :111 `timeout: TimeInterval = 30`, ExportMetadataProcessor.swift:53 `timeout: TimeInterval = 30`) and they encode a single policy: ExportMetadataProcessor delegates to DownloadArtworkProcessor's withOverallTimeout/export(_:timeout:) machinery, so all three govern the same AV export timeout, and the line-89 site is not parameterized at all. The repo's own convention favors the fix — named `static let ...: TimeInterval` constants are used for timing policies elsewhere (PlaybackController.periodicPlaybackStatusLogInterval, LyricTimelineView cooldowns). Nothing in CLAUDE.md/AGENTS.md endorses duplicated inline literals. Severity stays low: cosmetic clarity/tunability issue confined to two coupled files.

</details>

### [LOW] cacheLyrics takes an unnecessarily optional APIClient with a silent bail-out

`MuseAmp/Backend/Downloads/DownloadLyricsProcessor.swift:16` · function-design

**问题**: `cacheLyrics(trackID:apiClient:lyricsStore:)` accepts `apiClient: APIClient?` and silently returns on nil (lines 19-21), but its only caller (DownloadManager+Digger.swift:233-237) passes DownloadManager's non-optional `apiClient` property. The optional creates a do-nothing code path that can never execute and contradicts the repo's 'avoid unnecessary optionals' property rule.

**建议**: Make the parameter non-optional (`apiClient: APIClient`) and delete the guard.

<details><summary>验证记录</summary>

Verified: cacheLyrics (DownloadLyricsProcessor.swift:14-21) takes apiClient: APIClient? with a silent guard-return on nil. Its sole caller (DownloadManager+Digger.swift:233-237) passes DownloadManager's non-optional `let apiClient: APIClient` property, so the nil path is unreachable dead code. AGENTS.md (line 227, Property Rules) explicitly says "Avoid unnecessary optionals" — the pattern contradicts, not follows, repo convention. The sibling DownloadArtworkProcessor shares the same optional parameter, but there it is literally unused (declared `apiClient _: APIClient?`), so this is vestigial cruft in the module rather than a deliberate convention; other APIClient? uses elsewhere in the repo (SyncPreparedTrackBuilder, PlaylistCell, SongExportPresenter) have genuine nil semantics with `= nil` defaults, unlike here. Making the parameter non-optional and deleting the guard improves clarity and aligns with repo rules. Severity is low: cosmetic dead-path removal, no evidence of bugs bred.

</details>

### [LOW] Progress publish throttle interval 0.2 repeated inline

`MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:77` · named-constants

**问题**: scheduleProgressPublish compares `elapsed >= 0.2` (line 77) and computes `let delay = 0.2 - elapsed` (line 81) — the same throttle interval as two separate literals in one function. Changing the coalescing window requires editing both and knowing they are the same value.

**建议**: Hoist `private static let progressPublishInterval: TimeInterval = 0.2` (or a file-scope constant) and use it in both expressions.

<details><summary>验证记录</summary>

Confirmed: scheduleProgressPublish() in MuseAmp/Backend/Downloads/DownloadManager+Digger.swift uses the literal 0.2 at line 77 (`elapsed >= 0.2`) and line 81 (`let delay = 0.2 - elapsed`). The two literals are arithmetically coupled — editing one without the other desynchronizes the throttle window from the deferred-publish delay — so this is a genuine named-constants issue, not incidental repetition. AGENTS.md does not endorse inline duplicated literals (its only endorsed hardcoded value is the 200 pt lyric/queue spacer, unrelated), and the surrounding Backend modules already use `private static let` named constants for magic values (e.g., LikedSongsPlaylistArtwork.canvasSize, SyncBonjourIdentity.tokenLength), so the suggested hoist matches repo style. Severity remains low: two occurrences in one short function, visible at a glance, no evidence of an existing bug.

</details>

### [LOW] Auto-requeue retry cap 3 is a magic number echoed in log strings

`MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:135` · named-constants

**问题**: The unexpected-cancellation requeue path checks `currentRetry < 3` (line 135) and bakes the same value into the log text `"(retry \(currentRetry + 1)/3)"` (line 138). If the cap changes, the condition and the human-readable log will silently disagree.

**建议**: Introduce `private static let maxCancelledRetryCount = 3` on DownloadManager and interpolate it into both the condition and the log messages.

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/Downloads/DownloadManager+Digger.swift: line 135 has `if currentRetry < 3` and line 138 bakes the same cap into the log string `(retry \(currentRetry + 1)/3)`. The two literals can silently diverge if the cap changes. AGENTS.md does not endorse inline magic numbers (its only hardcoded-value mandate is the unrelated 200 pt lyrics/queue spacers), and the module's existing convention names its limits (maxConcurrent via AppPreferences), so the suggested private constant matches local style. Severity stays low: the duplication is confined to two adjacent lines in one function and only affects log accuracy, not behavior.

</details>

### [LOW] Cellular and none branches of handleNetworkChange are near-duplicates

`MuseAmp/Backend/Downloads/DownloadManager+Network.swift:57` · seams-duplication

**问题**: The .cellular branch (lines 57-75) and .none branch (lines 77-93) both: set isPausedForNetwork, guard !isPausedAll, loop downloading tasks inserting into intentionallyPaused, stop the Digger task, set .waitingForNetwork, zero speed, persistRecord, count, call updateDeferredStatesForPendingTasks, log, publishSnapshot. The only real differences (cellular skips cellularAllowedTrackIDs and silently skips tasks without a url, while none defers even url-less tasks) are buried inside ~16 duplicated lines, making the intentional asymmetry hard to spot.

**建议**: Extract `func deferDownloadingTasks(skippingCellularAllowed: Bool)` (or pass a `(String) -> Bool` exemption) so the shared mechanics live once and the branch-specific exemption is the only visible difference.

<details><summary>验证记录</summary>

Confirmed in MuseAmp/Backend/Downloads/DownloadManager+Network.swift lines 57-93: the .cellular and .none branches duplicate ~10 lines of defer mechanics (intentionallyPaused.insert, DiggerManager.stopTask, .waitingForNetwork, speed=0, persistRecord, count, updateDeferredStatesForPendingTasks, log, publishSnapshot), with two real differences: cellular exempts cellularAllowedTrackIDs and skips url-less tasks via guard/continue, while .none defers url-less tasks too via an inner if-let. The differing loop structures (guard-continue vs where + if-let) disguise the url-less asymmetry, so the finding's substance holds and an extracted helper parameterized on the exemption would be repo-consistent (AGENTS.md neither mandates nor endorses the duplication; helper extraction matches existing split-by-responsibility style). However, the branches are adjacent within one short function, the cellular exemption is plainly visible on its own guard line, and the only genuinely buried difference concerns downloading tasks without a url — a narrow edge case unlikely to occur for an actively downloading Digger task. So this is a legitimate but mild duplication/clarity issue, not one that actively misleads or has bred a bug; severity adjusted from medium to low.

</details>

### [LOW] persistRecord default arguments have inconsistent fallback semantics

`MuseAmp/Backend/Downloads/DownloadManager+Persistence.swift:23` · function-design

**问题**: In persistRecord, `sourceURL`, `localRelativePath`, and `retryCount` default to nil and fall back to the live task's values (`sourceURL ?? task.url?.absoluteString`, `retryCount ?? task.retryCount`), but `progress: Double = 0` and `lastError: String? = nil` are written through raw — so any call that omits them silently resets persisted progress to 0 and wipes errorMessage. For example handleNetworkChange persists .waitingForNetwork (DownloadManager+Network.swift:70) zeroing the record's mid-flight progress even though task.progress is intact. A caller cannot tell from the signature which omitted parameters mean 'keep the task's value' and which mean 'reset'.

**建议**: Make `progress: Double? = nil` and fall back to `task.progress` (clamped) like the other parameters, and document/normalize lastError the same way; sites that genuinely want a reset should pass it explicitly.

<details><summary>验证记录</summary>

The cited code exists exactly as described: persistRecord mixes 'omitted = inherit from live task' defaults (sourceURL, localRelativePath, retryCount) with 'omitted = literal reset' defaults (progress: Double = 0, lastError: String? = nil), and DownloadManager+Network.swift:70/88 do persist progress 0 for mid-flight downloads. The signature ambiguity is a genuine clarity hazard across 20+ call sites. However, the finding's concrete consequence is refuted: persisted DownloadJob.progress is never read back into behavior — rehydrateQueuedRecord/rehydrateFailedRecord hardcode in-memory progress 0 and rehydrateFinalizingRecord hardcodes 1 (DownloadManager+Queue.swift:154/178/232), and UI observes only the in-memory tasksPublisher. So zeroing persisted progress is harmless today. Additionally, lastError's raw-nil write is correct by design (non-failed transitions must clear errorMessage; retryFailed depends on it since it never clears task.lastError), so the suggestion's 'normalize lastError the same way' would introduce a real bug if applied as fallback-to-task. Only the progress half of the suggestion is safe. AGENTS.md neither mandates nor endorses the mixed-default pattern. Net: real clarity issue (the ambiguity forced a three-file trace to prove safety), but cosmetic rather than bug-breeding — severity downgraded from medium to low.

</details>

### [LOW] cleanupTmpFile is dead code shadowed by cleanupLocalAudioArtifacts

`MuseAmp/Backend/Downloads/DownloadManager+Persistence.swift:106` · seams-duplication

**问题**: `cleanupTmpFile(for:)` (lines 106-119) has zero callers anywhere in the repo (grep finds only its definition and its own log strings). `cleanupLocalAudioArtifacts(for:)` directly below already removes the same tmp URL as part of its cleanupTargets (line 123). Keeping both invites a maintainer to call the narrower, stale one.

**建议**: Delete cleanupTmpFile; cleanupLocalAudioArtifacts is the single canonical cleanup.

<details><summary>验证记录</summary>

Confirmed: cleanupTmpFile(for:) at MuseAmp/Backend/Downloads/DownloadManager+Persistence.swift:106-119 has zero callers anywhere in the repo (grep finds only the definition and its own log strings, across all targets including MuseAmpTV and tests). cleanupLocalAudioArtifacts(for:) directly below (lines 121-139) removes the same tmp URL via Self.finalizingURL(for: finalURL) as the first cleanupTargets entry, plus the final URL, and is the function actually invoked (4 call sites in DownloadManager.swift and DownloadManager+Digger.swift). AGENTS.md does not endorse retaining unused helpers, and no local convention keeps parallel narrow/wide cleanup variants. The suggested deletion is a safe, convention-compatible clarity improvement. Severity remains low: dead code that could mislead a future maintainer into calling the stale narrower helper, but no current bug.

</details>

### [LOW] completeFinalization tests ingestionError twice instead of one if-let

`MuseAmp/Backend/Downloads/DownloadManager+Persistence.swift:60` · early-return

**问题**: The branch reads `if ingestionError == nil { ... } else if let ingestionError { ... }` (lines 60 and 66) — a nil-check followed by a redundant optional unwrap of the same value, leaving an invisible (unreachable) third path. The natural form puts the failure unwrap first and the success path in else, matching the repo's guard/early-exit style.

**建议**: Rewrite as `if let ingestionError { ...failure handling... } else { ...success handling... }` (or unwrap with guard and early-return the success path).

<details><summary>验证记录</summary>

Confirmed at lines 60-66 of MuseAmp/Backend/Downloads/DownloadManager+Persistence.swift: `if ingestionError == nil { ... } else if let ingestionError { ... }` tests the same optional twice and leaves a compiler-visible (though logically unreachable) third path that silently falls through to publishSnapshot(). This is the only such occurrence in the Downloads module, so it is not a deliberate local convention, and AGENTS.md's "Use early returns and guard to reduce nesting" style guidance favors the suggested exhaustive `if let ... else` form. The fix is a strict clarity improvement with no behavior change and no AGENTS.md conflict. Code is functionally correct today, so severity stays low (cosmetic clarity).

</details>

### [LOW] reconcileOnLaunch dispatches on DownloadJobStatus with an if/else-if chain

`MuseAmp/Backend/Downloads/DownloadManager.swift:125` · state-modeling

**问题**: Lines 125-157 branch on `record.status` via four chained `if/else if` equality checks (.downloading||.resolving, .waitingForNetwork, .finalizing, .queued). DownloadJobStatus is a six-case enum; a switch would be compiler-checked, so adding a future status could not be silently skipped during launch reconciliation (today a record in an unhandled status would just be dropped from rehydration with no log). The repo otherwise uses switch (including switch expressions) for enum dispatch, e.g. handleNetworkChange.

**建议**: Replace the chain with `switch record.status { case .downloading, .resolving: ... case .waitingForNetwork: ... case .finalizing: ... case .queued: ... case .failed: break }` so exhaustiveness is enforced.

<details><summary>验证记录</summary>

Confirmed: reconcileOnLaunch (DownloadManager.swift lines 119-167) dispatches on record.status with a four-branch if/else-if chain and no terminal else. DownloadJobStatus is a six-case enum; activeRecords() returns only the five isActive cases, so today all returned statuses are handled (the finding's "today...dropped" wording is slightly overstated), but a future case added to the enum would be compiler-caught in the package's isActive switch yet silently skipped here during launch reconciliation. The surrounding module's dominant convention is switch-based enum dispatch (ActiveDownloadTask.State.sortOrder in the same file, DownloadJobStatus.isActive, handleNetworkChange in DownloadManager+Network.swift), so the suggested switch rewrite matches, not violates, repo style. AGENTS.md/CLAUDE.md does not endorse the if/else chain pattern. Genuine but cosmetic exhaustiveness/clarity improvement; no current bug.

</details>

### [LOW] hasMarkedDownloading reads as a Bool but is a Set of URLs

`MuseAmp/Backend/Downloads/DownloadManager.swift:80` · naming

**问题**: `var hasMarkedDownloading: Set<URL> = []` uses a has-prefixed boolean name for a collection, and the name doesn't say what was 'marked': it actually tracks URLs whose first Digger progress callback has already persisted the .downloading status (DownloadManager+Digger.swift:56-59). Call sites like `!hasMarkedDownloading.contains(url)` force the reader to reverse-engineer the meaning.

**建议**: Rename to a noun-phrase that states the contents, e.g. `urlsWithPersistedDownloadingState` or `downloadingStatePersistedURLs`.

<details><summary>验证记录</summary>

Confirmed: DownloadManager.swift:80 has `var hasMarkedDownloading: Set<URL> = []` — a has-prefixed boolean-sounding name on a collection, and the name omits what was marked (first-progress persistence of .downloading status, per DownloadManager+Digger.swift:56-59). The adjacent sibling property `diggerStartedURLs: Set<URL>` (line 81) shows the file's own noun-phrase `...URLs` convention for URL sets, while is/has prefixes are used for genuine Bools (`isPausedAll`, `isKeepingScreenAwake`). The suggested rename aligns with, rather than violates, local convention. AGENTS.md contains no rule endorsing the flagged pattern. Severity is low: misleading name but localized usage (7 sites) whose Set operations quickly disambiguate; no evidence of induced bugs.

</details>

## [clarity] backend-playback-models (19)

### [MEDIUM] Snapshot commit sequence duplicated between full and lightweight refresh

`MuseAmp/Backend/Playback/PlaybackController+Snapshot.swift:68` · seams-duplication

**问题**: Lines 68-76 (refreshSnapshot full path) and lines 121-129 (publishLightweightSnapshot) repeat the identical five-step commit verbatim: `latestSnapshot = nextSnapshot`; `if !isUIPublishingSuspended { snapshot = nextSnapshot }`; `updatePlaybackStatusLogTimer()`; `player.setCurrentItemLiked(nextSnapshot.isCurrentTrackLiked)`; `if persistState { persistPlaybackState() }`. Any future step added to the commit (a notification, an analytics hook, a new side effect) must be remembered in both places; missing one produces a divergence that only manifests on whichever refresh path was forgotten.

**建议**: Extract a single `commitSnapshot(_ nextSnapshot: PlaybackSnapshot, persistState: Bool)` private method containing the five steps, called from both refreshSnapshot and publishLightweightSnapshot.

<details><summary>验证记录</summary>

Verified: lines 68-76 (refreshSnapshot full path) and 121-129 (publishLightweightSnapshot) in MuseAmp/Backend/Playback/PlaybackController+Snapshot.swift repeat the identical five-step commit verbatim (latestSnapshot assignment, isUIPublishingSuspended-gated snapshot publish, updatePlaybackStatusLogTimer, setCurrentItemLiked, persistState-gated persistPlaybackState). This is the controller's core state-publication seam; a step added to one path but not the other would diverge silently and surface only on whichever refresh path was forgotten. AGENTS.md (identical to CLAUDE.md) contains no endorsement of inlining this sequence, and the file itself already uses small focused helpers (canPerformLightweightSnapshotRefresh, resolvedSnapshotCurrentTime), so extracting commitSnapshot(_:persistState:) matches local convention. Medium severity is fair: the duplication breeds subtle path-divergence bugs but none has demonstrably occurred yet.

</details>

### [MEDIUM] Designated init requires an APIClient it never uses

`MuseAmp/Backend/Playback/PlaybackController.swift:69` · seams-duplication

**问题**: The designated initializer declares `apiClient _: APIClient` — the parameter is anonymous and never stored or read anywhere in PlaybackController or its extensions. The convenience init (line 119) also demands it just to forward it into the discard. Both real call sites (MuseAmp/Application/AppEnvironment.swift:84 and MuseAmpTV/Application/TVAppContext.swift:77) pass a live client that is thrown away. Readers and AGENTS.md ('PlaybackController is responsible for local-vs-remote playback URL resolution') are led to believe the controller depends on networking, but resolution (+Resolution.swift) is local-file-only and throws PlaybackResolutionError.localFileUnavailable with no remote fallback. This is a phantom dependency that misstates the type's seams.

**建议**: Remove the `apiClient` parameter from both the designated and convenience initializers and from the two call sites (the file is symlinked into MuseAmpTV/Backend/Playback, so one edit covers both targets). If remote resolution is genuinely planned, instead store it with a name and a TODO so the dependency is honest.

<details><summary>验证记录</summary>

Verified: PlaybackController.swift:69 declares `apiClient _: APIClient` — discarded, never stored or read in the controller or any of its +extension files. Convenience init (line 118) forwards it into the discard. Both production call sites (AppEnvironment.swift:83, TVAppContext.swift:77) pass a live client that is thrown away, and every PlaybackController test must build a dummy APIClient(baseURL: "https://example.com") purely to satisfy the phantom parameter. Resolution (+Resolution.swift resolvePlayerItem) is strictly local-file with no remote fallback, throwing PlaybackResolutionError.localFileUnavailable, so the network dependency truly has no role; AGENTS.md's claim that the controller handles "local-vs-remote playback URL resolution" makes the unused parameter actively misleading rather than endorsed. Only one other `_: APIClient` discard exists in the repo (DownloadArtworkProcessor), so this is not a deliberate convention. The symlink claim is accurate, so the suggested fix is a single-file edit plus call-site cleanups and aligns with the repo's dependency-injection style. Medium severity stands: misstates the type's seams, contradicts AGENTS.md expectations, and imposes test ceremony, but no concrete bug yet.

</details>

### [MEDIUM] Magic 3-second previous-restart threshold duplicates MuseAmpPlayerKit internals

`MuseAmp/Backend/Playback/PlaybackController.swift:259` · seams-duplication

**问题**: `let willRestart = player.currentTime > 3` re-implements the decision MuseAmpPlayerKit makes internally in PlaybackQueue.rewind (MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:152: `if currentTime > 3.0`). The controller predicts the kit's behavior with an inline unnamed literal; if the kit ever changes its threshold, this prediction silently diverges and the snapshot reset (lines 262-265) fires for the wrong branch. There is no constant or comment tying the two together.

**建议**: Expose the threshold from MuseAmpPlayerKit (e.g. `MusicPlayer.previousRestartThreshold` public static let consumed here), or have `previous()` return/report whether it restarted. At minimum hoist `3` into a named constant (`static let previousRestartThreshold: TimeInterval = 3`) with a comment that it must mirror PlaybackQueue.rewind.

<details><summary>验证记录</summary>

Verified: PlaybackController.swift:259 uses inline `player.currentTime > 3` to predict the restart decision that PlaybackQueue.rewind makes internally (PlaybackQueue.swift:152, `currentTime > 3.0`), and MusicPlayer.previous() does not report which branch it took. The finding understates the problem: a third copy of the literal exists in NowPlayingContentMapper.swift:72, and the controller's prediction is already wrong for rewind's non-time-based .restart branches (nil currentIndex, or empty history with repeat off and currentTime <= 3), where the kit restarts but willRestart=false skips the snapshot reset and logs misleadingly. Attempted refutation: AGENTS.md:358 does document `previous() // restarts if currentTime > 3s` as API contract, making the threshold semi-public rather than purely internal, but AGENTS.md nowhere endorses re-deriving the decision inline with an unnamed literal, and the documented one-liner omits the other restart branches that already cause divergence. The suggested fixes (kit-exposed constant, previous() reporting restart, or at minimum a named constant with a linking comment) are consistent with repo style and AGENTS.md. Medium severity holds: the duplicated prediction drives a state reset and has already bred a subtle behavioral/logging inconsistency.

</details>

### [MEDIUM] Two divergent implementations of removing the currently playing track

`MuseAmp/Backend/Playback/PlaybackController.swift:306` · seams-duplication

**问题**: removeTracksFromQueue (lines 302-313) handles a current-track match by calling `player.next()` (or `player.stop()`) and incrementing `removedCount`, but never calls `player.removeFromQueue(id:)` — so the item survives in the queue's history while being reported as removed. The sibling removeFromQueue(at:) (lines 334-336) handles the same situation by `player.next()` followed by `player.removeFromQueue(id: currentItem.id)`, actually removing it. The same user intent ('remove the playing track from the queue') therefore has two inconsistent semantics depending on entry point, and the inline duplication is exactly the kind of per-call-site reimplementation principle 13 flags.

**建议**: Extract one canonical `removeCurrentItemFromQueue()` helper that advances (or stops) and then removes the item by id, and call it from both removeTracksFromQueue and removeFromQueue(at:). If keeping the track in history is intentional for the batch path, state that in the log message and do not count it in removedCount.

<details><summary>验证记录</summary>

Verified against PlaybackController.swift and MuseAmpPlayerKit. removeTracksFromQueue (lines 302-313) advances/stops past a matching current track and counts it as removed without calling player.removeFromQueue(id:); since PlaybackQueue.remove(id:) can remove history items and next() moves the current item into history, the track survives in the queue snapshot (history + nowPlaying + upcoming) and remains reachable via previous()/skipToQueueTrack. The sibling removeFromQueue(at:) (lines 324-337) handles the identical situation with next() + removeFromQueue(id:), actually deleting it. The batch path is invoked from library-deletion call sites, so a deleted track lingering replayable in history is a plausible latent bug, and the log message 'skipping current track' contradicts the removedCount accounting. The advance-or-stop logic is duplicated inline in both methods. Nothing in AGENTS.md endorses this duplication; extracting a shared helper matches the file's existing small-method style. Not refutable; the divergence is substantive, the suggestion improves clarity without violating repo conventions.

</details>

### [LOW] File named after AMNowPlayingQueueSnapshot but never extends or mentions it

`MuseAmp/Backend/Models/AMNowPlayingQueueSnapshot+AppModels.swift:11` · file-organization

**问题**: The file contains `extension PlaybackTrack: AMNowPlayingQueueTrackPresenting` (line 11) and `extension AMPlaybackRepeatMode` (line 33). The token AMNowPlayingQueueSnapshot appears nowhere in the file body — that type lives in MuseAmp/Interface/NowPlaying/ViewModel/Queue/AMNowPlayingQueueSnapshot.swift. Under the folder's TargetType+AppModels.swift convention the filename should name the extended type; bundling two unrelated extended types (PlaybackTrack and AMPlaybackRepeatMode) under a third type's name makes both conformances undiscoverable by filename search.

**建议**: Rename to PlaybackTrack+AppModels.swift and either keep the small AMPlaybackRepeatMode init there with a clear MARK, or split it into AMPlaybackRepeatMode+AppModels.swift if it grows.

<details><summary>验证记录</summary>

Verified: the file extends only PlaybackTrack and AMPlaybackRepeatMode; the token AMNowPlayingQueueSnapshot never appears in the body (that type lives in Interface/NowPlaying/ViewModel/Queue/AMNowPlayingQueueSnapshot.swift). Folder convention check: SongRowContent+AppModels.swift, AlbumTrackCellContent+AppModels.swift, and CatalogSong+AppModels.swift all extend exactly the type in the filename (PlaylistSong+AppModels.swift is a minor near-miss extending PlaylistEntry), so filename-names-extended-type is the dominant deliberate convention, and this file is the sole full outlier. AGENTS.md (identical to CLAUDE.md) has no rule endorsing the flagged pattern; its Extension+ClassName.swift rule actually reinforces filename-names-extended-type. The rename suggestion (PlaybackTrack+AppModels.swift, optionally splitting the AMPlaybackRepeatMode init) aligns with sibling files and violates no repo rule. Impact is limited to filename-based discoverability with no correctness risk, so severity stays low.

</details>

### [LOW] Only CatalogSong→cell conversion that skips sanitizedTrackTitle

`MuseAmp/Backend/Models/AlbumTrackCellContent+AppModels.swift:21` · mechanical-consistency

**问题**: This init passes `title: catalogSong.attributes.name` raw, while every sibling conversion of the same kind of title field applies `.sanitizedTrackTitle`: SongRowContent+AppModels.swift lines 15, 25, 47, 63 (including the conversion from the very same `catalogSong.attributes.name` at line 15) and AMNowPlayingQueueSnapshot+AppModels.swift line 17. If the album-detail screen intentionally shows the unsanitized full title, nothing in the file says so; as written it reads as an omission, and the same song renders with a different title in album detail versus search/song rows.

**建议**: Apply `.sanitizedTrackTitle` to match the siblings, or if the raw title is deliberate in album-detail context, add the one clarifying comment AGENTS.md permits for real ambiguity.

<details><summary>验证记录</summary>

Confirmed: AlbumTrackCellContent+AppModels.swift line 21 passes catalogSong.attributes.name raw while every sibling display conversion sanitizes — SongRowContent+AppModels.swift lines 15/25/47/63 (line 15 converts the identical field from the identical type), AMNowPlayingQueueSnapshot+AppModels.swift, and SearchViewController.swift:170. Sanitization is gated by the user-facing isCleanSongTitleEnabled preference, so the omission means album-detail track rows silently ignore a user setting that every other list surface honors, and the same CatalogSong renders with different titles in search vs album detail. Raw attributes.name uses elsewhere in AlbumDetailViewController are copy/export/delete-confirm/metadata paths where exact titles are correct, so they do not establish a deliberate raw-display convention; at the Backend/Models display-conversion layer sanitizing is unanimous except this init. AGENTS.md neither mandates nor endorses the raw pattern (it only mentions string sanitization as a Supplement placement note), and the suggested one-token fix matches repo style without violating any rule. No comment or history (single squash init commit) indicates intent. Severity stays low: cosmetic display inconsistency conditional on an optional setting.

</details>

### [LOW] Speculative artworkWidth/artworkHeight parameters never used non-default

`MuseAmp/Backend/Models/CatalogSong+AppModels.swift:32` · function-design

**问题**: downloadRequest(albumID:apiClient:artworkWidth:artworkHeight:) exposes `artworkWidth: Int = 600, artworkHeight: Int = 600`, but the only call sites in the repo (MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift:225 and :270) use the defaults. AGENTS.md fixes the standard artwork size at 600×600 for downloads, so the parameters invite divergence from a documented invariant while buying nothing; the sibling conversion PlaylistEntry.downloadRequest (PlaylistSong+AppModels.swift:19) hardcodes 600×600 with no such knobs, so the two adapters also disagree on shape.

**建议**: Delete the artworkWidth/artworkHeight parameters and call apiClient.mediaURL(from:width: 600, height: 600) directly, matching the PlaylistEntry adapter and the AGENTS.md standard size.

<details><summary>验证记录</summary>

Verified against the source: CatalogSong.downloadRequest (MuseAmp/Backend/Models/CatalogSong+AppModels.swift:29-34) declares artworkWidth/artworkHeight with 600 defaults, and a repo-wide grep shows these identifiers exist nowhere else — the only two call sites (AlbumDetailViewController.swift:225, :270) pass no explicit values. AGENTS.md:260 mandates 600×600 as the standard artwork size for downloads, so the parameters' only possible non-default use would breach a documented invariant. The sibling PlaylistEntry.downloadRequest (PlaylistSong+AppModels.swift:19) hardcodes width: 600, height: 600, so the dominant module convention favors the suggested fix, not the flagged pattern. AGENTS.md endorses only routing through apiClient.mediaURL/resolveMediaURL, which the suggestion preserves. The fix is a genuine clarity improvement with no convention conflict. Severity stays low: defaults match the standard, so nothing is currently broken — this is unused API surface, not a latent bug.

</details>

### [LOW] Filename names a type that does not exist in the repo

`MuseAmp/Backend/Models/PlaylistSong+AppModels.swift:11` · file-organization

**问题**: The file is named PlaylistSong+AppModels.swift but its sole content is `extension PlaylistEntry`. A repo-wide grep finds no type named PlaylistSong anywhere — the only matches for 'PlaylistSong' are this filename and unrelated method names like refreshPlaylistSongs(). The Models-folder convention is TargetType+AppModels.swift named for the extended type (CatalogSong+AppModels.swift extends CatalogSong, SongRowContent+AppModels.swift extends SongRowContent), so anyone searching for PlaylistEntry adapters by filename will miss this file.

**建议**: Rename the file to PlaylistEntry+AppModels.swift (updating the Xcode group to match on-disk naming per AGENTS.md), or fold the single downloadRequest extension into an existing PlaylistEntry-named file.

<details><summary>验证记录</summary>

Verified: PlaylistSong+AppModels.swift contains only `extension PlaylistEntry`, and no PlaylistSong type exists anywhere in the repo (only this filename and unrelated method names like refreshPlaylistSongs). The dominant Models-folder convention names files after the real extended/adapted type (CatalogSong, AlbumTrackCellContent, SongRowContent, AMNowPlayingQueueSnapshot — all real types). AGENTS.md does not endorse the mismatch; its naming guidance (Extension+ClassName.swift, on-disk/group alignment) supports the suggested rename to PlaylistEntry+AppModels.swift, which would read exactly like the rest of the folder. Severity lowered to low: the misleading name is corrected the moment the 22-line file is opened, the harm is limited to filename-based discoverability, and there is no plausible bug-breeding path.

</details>

### [LOW] Static factory not make-prefixed and shadows the stored property name

`MuseAmp/Backend/Models/SongExportItem.swift:48` · naming

**问题**: `static func preferredFileBaseName(artistName:title:fallbackBaseName:)` has exactly the same name as the stored property it initializes (`preferredFileBaseName = Self.preferredFileBaseName(...)` at line 39), forcing the `Self.` disambiguation and making 'preferredFileBaseName' refer to two different things within one init. The Playback/Models scope's established factory convention is a make- prefix (makePlayerItem, makeQueuedPlayerItem, makeQueueItemID, makePersistedSession, makePersistedTrack), which this helper ignores.

**建议**: Rename the static helper to `makePreferredFileBaseName(artistName:title:fallbackBaseName:)`, removing the property/function name collision and matching the local make- factory convention.

<details><summary>验证记录</summary>

Verified: in MuseAmp/Backend/Models/SongExportItem.swift the stored property `preferredFileBaseName` (line 13) is assigned at line 39 from a private static func of the exact same name (line 48), forcing `Self.` disambiguation and making one identifier denote two things within the init. The repo's dominant factory convention is the make- prefix (21 `static func make...` helpers across Backend: makeAPIClient, makePlayerItem, makeQueuedPlayerItem, makePersistedSession, makePersistedTrack, makePlayAtMenu, makeDiscoveredDevice), with only one other loosely similar same-name case (SyncServer.preferredEndpoints, which initializes a property on a different nested type, so not a same-type shadow). AGENTS.md/CLAUDE.md contain no rule endorsing the shadowing pattern, and renaming to makePreferredFileBaseName would make the code read MORE like the rest of the repo, not less. The fix is a trivial private rename with one call site. However, the issue is purely cosmetic — the Self. call compiles unambiguously and is a recognizable Swift idiom in a 68-line file — so severity remains low.

</details>

### [LOW] Three hand-rolled variants of the artist–album subtitle join in one file

`MuseAmp/Backend/Models/SongRowContent+AppModels.swift:26` · seams-duplication

**问题**: The same 'join non-empty artist and album with " · "' composition is implemented three different ways in three sibling inits: line 26 uses `[artistName, albumTitle].filter { !$0.isEmpty }.joined(separator: " · ")`, lines 37-44 use a manual if-let with string interpolation `"\(artistName) · \(albumName)"`, and lines 55-60 use a compactMap-with-guard variant. The " · " literal is repeated three times and the empty/optional handling rules differ subtly per copy, so a fourth conversion author has three competing templates to pick from.

**建议**: Add one private helper in this file, e.g. `private func songSubtitle(artist: String, album: String?) -> String`, that filters empty components and joins with a single named " · " separator constant, and use it from all three inits.

<details><summary>验证记录</summary>

Confirmed: the file implements the identical 'join non-empty artist and album with " · "' composition three different ways within 69 lines (line 26 filter+joined, lines 37-44 if-let+interpolation, lines 55-60 compactMap+guard+joined), with the " · " literal repeated three times and subtly divergent empty-handling (variant 3 would show an empty artist alone; variants 1/2 filter it). AGENTS.md does not endorse this pattern, and other inline " · " joins elsewhere in the repo compose heterogeneous parts once per site, so they don't make per-file template drift a deliberate convention. The suggested private/free helper matches this file's existing style, which already delegates the analogous duration-formatting concern to shared free functions (formattedDuration in PlaybackTimeFormatting.swift). The fix is small, local, and would not make the code read unlike the rest of the module. Severity remains low: cosmetic clarity drift, no evidence it has misled readers or bred a bug yet.

</details>

### [LOW] +Resolution file is a self-confessed two-responsibility file

`MuseAmp/Backend/Playback/PlaybackController+Resolution.swift:12` · file-organization

**问题**: The file's own header MARK reads '// MARK: - Item Resolution & Session Persistence' — an 'and' that names two responsibilities. Lines 14-188 are URL/PlayerItem resolution; lines 190-335 (makePersistedSession, makePersistedTrack, persistedArtworkURLString, restoredArtworkURL, rebuildLocalArtworkIfNeeded, localRelativePath, relativeAudioPath) are session persistence and artwork restoration, which have nothing to do with the 'Resolution' filename. AGENTS.md mandates responsibility-based splits for large controllers, and the sibling files (+Delegate, +Snapshot, +Logging) follow that; persistence helpers hidden in +Resolution break the navigation contract.

**建议**: Move the session-persistence half (lines 190-335) into a new PlaybackController+Persistence.swift, and create the matching relative symlink in MuseAmpTV/Backend/Playback/ in the same change (the directory mirrors every Playback file via symlinks, so the TV target will not compile otherwise).

<details><summary>验证记录</summary>

Verified: the file header MARK literally names two responsibilities ('Item Resolution & Session Persistence'), and lines ~190-335 (makePersistedSession, makePersistedTrack, persistedArtworkURLString, restoredArtworkURL, rebuildLocalArtworkIfNeeded, localRelativePath, relativeAudioPath) are session persistence/restoration, unrelated to the 'Resolution' filename. AGENTS.md mandates responsibility-based extension splits and sibling files (+Delegate, +Snapshot, +Logging) follow it, so the suggested PlaybackController+Persistence.swift split (plus the required MuseAmpTV/Backend/Playback symlink, which the directory factually mirrors for every file) reads like the rest of the repo. However, severity is downgraded to low: the internal 'MARK: - Session Persistence' section header makes the second half discoverable on open, the only callers are PlaybackController.swift's persist/restore paths found trivially by symbol search, and the mismatch neither breeds bugs nor blocks safe modification — it is a navigation/cosmetic clarity issue.

</details>

### [LOW] Logging helpers live in +Snapshot while +Logging exists

`MuseAmp/Backend/Playback/PlaybackController+Snapshot.swift:234` · file-organization

**问题**: PlaybackController+Snapshot.swift devotes roughly a third of its 297 lines to pure logging concerns: updatePlaybackStatusLogTimer/shouldEmitPeriodicPlaybackStatusLog/logPeriodicPlaybackStatus (lines 141-184) and the four `string(for:)` log-text formatters (lines 234-296). Meanwhile PlaybackController+Logging.swift exists as the responsibility-named home for logging and contains only the 29-line MusicPlayerLogger bridge. A maintainer looking for the periodic status log or the state-name formatter will open +Logging first and find nothing; the +Snapshot file no longer matches its name.

**建议**: Move updatePlaybackStatusLogTimer, shouldEmitPeriodicPlaybackStatusLog, logPeriodicPlaybackStatus, and the four string(for:) overloads into PlaybackController+Logging.swift (already symlinked into MuseAmpTV/Backend/Playback, so no symlink change needed), leaving +Snapshot with snapshot construction/publishing only.

<details><summary>验证记录</summary>

All cited facts verified: PlaybackController+Snapshot.swift (297 lines) contains the periodic playback-status logging timer/emitter (lines 141-184) and four string(for:) log formatters (lines 234-296), while PlaybackController+Logging.swift is the responsibility-named logging file containing only a 29-line MusicPlayerLogger bridge. The formatters are even consumed by PlaybackController.swift and +Delegate.swift, so shared log helpers are defined in a file whose name promises snapshot construction. AGENTS.md mandates responsibility-based splitting and does not endorse the flagged pattern; the Playback module's existing +Delegate/+Logging/+Resolution split endorses the fix. Both files are relative symlinks in MuseAmpTV/Backend/Playback, so the suggested move needs no symlink changes and compiles for both targets. Severity adjusted to low: it is a genuine file-organization mismatch, but purely cosmetic — jump-to-definition/grep negate the navigation cost and there is no bug-breeding mechanism.

</details>

### [LOW] QueueState.reset() performs a partial reset

`MuseAmp/Backend/Playback/PlaybackController.swift:31` · naming

**问题**: `mutating func reset()` clears `currentSource` and `trackLookup` but deliberately leaves `itemCache` populated (the resolution cache must survive queue teardown — PlaybackControllerTests asserts cachedItem(for:) after restore). The name `reset()` promises a return to initial state for the whole struct; a reader at the call site (PlaybackController+Snapshot.swift:22, fired whenever queue.totalCount == 0) will reasonably assume all three stored properties are wiped. The retained-cache subtlety is invisible without opening the struct.

**建议**: Rename to something that scopes the effect, e.g. `clearActiveQueueAssociations()` or `resetSourceAndLookup()`, or split itemCache out of QueueState into its own `resolutionCache` property so reset() can honestly reset everything in QueueState.

<details><summary>验证记录</summary>

Verified: QueueState (PlaybackController.swift:26-35) has three stored properties and reset() clears only currentSource and trackLookup, leaving itemCache. The retention is deliberate and load-bearing — itemCache is the resolution cache read in PlaybackController+Resolution.swift:64-74 and PlaybackControllerTests.swift:278 asserts cachedItem(for:) survives restore — so the name reset() genuinely under-describes its behavior. The sole call site (PlaybackController+Snapshot.swift:22, fired when queue.totalCount == 0) is in a different file with no comment, so the partial-reset subtlety is invisible there. AGENTS.md does not endorse the pattern; the controller's existing style of small responsibility-scoped state structs (RestoreState, SeekState) means the suggested rename or splitting itemCache out would match, not violate, local conventions. Severity stays low: the struct is tiny and inline, the cache self-validates via fileExists at use time, and no bug has resulted — this is a cosmetic-but-real naming clarity issue.

</details>

### [LOW] PlayNextResult associated Ints are unlabeled counts

`MuseAmp/Backend/Playback/PlaybackController.swift:16` · naming

**问题**: `case played(Int)` and `case queued(Int)` carry a track count, but nothing in the declaration says so. Consumers must infer it: PlaybackFeedbackPresenter.swift:28 binds `case let .played(count)` and then uses it for a `count == 1` heuristic. Production sites construct `.played(tracks.count)` / `.queued(resolvedItems.count)` — note the two cases are even fed from different collections (requested tracks vs resolved items), which an unlabeled Int does nothing to disambiguate.

**建议**: Label the associated values: `case played(count: Int)` and `case queued(count: Int)`, updating the handful of construction/match sites.

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/Playback/PlaybackController.swift:15-22: `case played(Int)` and `case queued(Int)` carry unlabeled Ints. Construction sites (lines 186, 212) feed them from different collections (`tracks.count` vs `resolvedItems.count`), and the consumer (PlaybackFeedbackPresenter.swift:28) must bind and interpret the value via a `count == 1` heuristic — the finding's substance is accurate. AGENTS.md does not endorse unlabeled associated values, and the repo's dominant convention labels ambiguous numeric payloads (e.g. `preparing(current:total:)`, `skeleton(index:)`, `track(position:id:number:)`, `error(statusCode:body:)`), reserving unlabeled payloads for cases whose name already explains the value (`invalidHTTPStatus(Int)`, ID strings). Adding `count:` labels therefore aligns with local style rather than violating it, and the fix touches only ~3 sites. It is a genuine clarity improvement, but cosmetic: the lone consumer already names the binding `count` and no bug has resulted, so severity remains low.

</details>

### [LOW] Repeated `.adHoc(name: "Queue")` empty-queue fallback in playNext and addToQueue

`MuseAmp/Backend/Playback/PlaybackController.swift:185` · named-constants

**问题**: Lines 184-187 (playNext) and 218-221 (addToQueue) repeat the same fallback: `if player.queue.totalCount == 0 { let started = await play(tracks: tracks, source: .adHoc(name: "Queue")) ... }`, including the bare string literal "Queue" twice. The literal is internal-only (grep confirms the adHoc name is never rendered in UI, only Codable round-tripped), but it is still an uncentralized repeated literal plus a duplicated branch that must stay in sync across both queue-mutation entry points.

**建议**: Hoist the literal to a named constant (e.g. `static let adHocQueueSourceName = "Queue"` next to queueItemIDPrefix) and/or extract a `startAdHocQueuePlayback(_ tracks:) async -> Bool` helper used by both methods.

<details><summary>验证记录</summary>

Confirmed: PlaybackController.swift lines 184-187 and 218-221 duplicate the identical empty-queue fallback branch, including the bare literal .adHoc(name: "Queue") twice — the only two uses of that literal in the repo. The two branches are queue-mutation entry points that must stay semantically in sync (same persisted source identity). The suggested fix matches existing local style: the same file already hoists literals to static constants (queueItemIDPrefix at line 46) and splits logic into small helpers (resolvePlayableItems, preferredStartIndex), so a shared startAdHocQueuePlayback(_:) -> Bool helper would not read alien. AGENTS.md does not endorse the duplicated-literal pattern. Severity stays low: two occurrences in one file, the name is internal-only (Codable round-trip, never rendered), so drift would cause inconsistency, not a bug.

</details>

### [LOW] `_ = await player.seek(to: 0)` discards a Void result

`MuseAmp/Backend/Playback/PlaybackController.swift:276` · mechanical-consistency

**问题**: MusicPlayer.seek is declared `func seek(to seconds: TimeInterval) async` with no return value (MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Playback.swift:82). The `_ =` in restartCurrentTrack falsely signals to readers that a meaningful result (e.g. a success Bool) is being deliberately ignored. The other call site in this same file (line 370, inside seek(to:)) calls it bare, so the two sites are also inconsistent with each other.

**建议**: Drop the `_ =` and call `await player.seek(to: 0)` to match line 370.

<details><summary>验证记录</summary>

Verified: PlaybackController.swift:276 has `_ = await player.seek(to: 0)` while MusicPlayer.seek (MusicPlayer+Playback.swift:82) returns Void, and line 370 in the same file calls it bare (`await player.seek(to: targetTime)`). All other `_ = await` sites in the repo (restorePersistedPlaybackIfNeeded -> Bool, playNext -> PlayNextResult, resolveService -> DiscoveredDevice?) discard real results, so `_ =` on a Void call breaks the codebase's own signal that a meaningful result is being ignored. AGENTS.md does not endorse the pattern. The suggested fix (drop `_ =`) matches both the sibling call site and repo convention. Cosmetic-only impact, so severity remains low.

</details>

### [LOW] seek(to:) uses Task + MainActor.run instead of the established Task { @MainActor } pattern

`MuseAmp/Backend/Playback/PlaybackController.swift:368` · repository-conventions

**问题**: seek(to:) spawns `Task { [weak self] in ... await MainActor.run { self.refreshSnapshot(...) } }` (lines 368-374). PlaybackController is @MainActor, so the unstructured Task already inherits main-actor isolation, making the inner `await MainActor.run` a redundant no-op hop; the established pattern everywhere else in this class (init at lines 100 and 111, restartCurrentTrack at line 273, the snapshot timer at +Snapshot.swift:156) is `Task { @MainActor [weak self] in }` with direct calls. The divergent shape suggests a threading subtlety that does not exist.

**建议**: Rewrite as `Task { @MainActor [weak self] in guard let self else { return }; await player.seek(to: targetTime); refreshSnapshot(currentTime: targetTime, duration: player.duration, persistState: true) }`, matching restartCurrentTrack.

<details><summary>验证记录</summary>

Verified at PlaybackController.swift:362-375. The class is @MainActor (line 24-25), Task closures inherit the enclosing actor context, so the `await MainActor.run` wrapper around refreshSnapshot is a redundant no-op that falsely signals a threading concern. All four other unstructured tasks in the class (lines 100, 111, 273, +Snapshot.swift:156) use the `Task { @MainActor [weak self] in }` shape with direct calls; restartCurrentTrack (line 273) performs a nearly identical seek+refreshSnapshot sequence in exactly the suggested form, so the fix matches local convention rather than violating it. AGENTS.md does not endorse the flagged pattern; its only related rule (line 269) endorses `Task { @MainActor in }`. Cosmetic clarity issue only — severity low.

</details>

### [LOW] Inline magic string "HDMI" in port-type mapping

`MuseAmp/Backend/Playback/PlaybackOutputDevice.swift:61` · named-constants

**问题**: The default branch of `kind(for:)` reads `portType.rawValue == "HDMI" ? .television : .unknown`. Every other port in the switch is matched via the typed `AVAudioSession.Port` constants, so dropping to a raw-string comparison for one case is jarring and unexplained — a reader cannot tell whether `.HDMI` was unavailable on a deployment target, deprecated, or simply forgotten, and the bare literal is invisible to symbol search.

**建议**: Match `AVAudioSession.Port.HDMI` directly if it is available on all build targets; otherwise hoist the literal into a named private constant (e.g. `private static let hdmiPortRawValue = "HDMI"`) with a one-line comment stating why the typed constant cannot be used.

<details><summary>验证记录</summary>

Confirmed at MuseAmp/Backend/Playback/PlaybackOutputDevice.swift:61 — the default branch compares portType.rawValue == "HDMI" while every other port in kind(for:) uses typed AVAudioSession.Port constants. I attempted to refute it on availability grounds: the SDK header marks AVAudioSessionPortHDMI API_UNAVAILABLE(macos), which could have justified the raw string for the Catalyst build. However, Catalyst inherits iOS availability, and typecheck compiles of `.HDMI` against iOS, Mac Catalyst (arm64-apple-ios16.0-macabi), and tvOS (the file is shared into MuseAmpTV/Backend/Playback/) all succeed with no diagnostics. So the typed constant works on every target this project builds, and the suggestion to match .HDMI directly compiles and aligns with the dominant convention of the surrounding switch. AGENTS.md does not endorse raw-string port comparisons; the rest of the file is the convention and the literal is the outlier. Behavior is functionally correct (the constant's rawValue is "HDMI"), so this is a cosmetic clarity issue: low severity.

</details>

### [LOW] formattedDuration reimplements formattedPlaybackTime with divergent edge behavior

`MuseAmp/Backend/Playback/PlaybackTimeFormatting.swift:22` · seams-duplication

**问题**: `formattedDuration(millis:)` and `formattedDuration(seconds:)` (lines 22-28) hand-roll minute:second formatting that formattedPlaybackTime (lines 10-20) already implements, and the copies diverge at the edges: formattedPlaybackTime clamps negatives to 0 and rolls hours (3700s → "1:01:40"), while formattedDuration(seconds: 3700) yields "61:40" and formattedDuration(seconds: -5) yields "0:-5". So the same duration can render differently in a list trailing-text versus the player transport, and negative/garbage input is only defended in one of the three functions.

**建议**: Implement both formattedDuration overloads in terms of formattedPlaybackTime (e.g. `formattedDuration(seconds:) = formattedPlaybackTime(TimeInterval(seconds))` and the millis overload dividing by 1000), or extract one shared core; if list cells must never show hour-rollover, encode that as an explicit option rather than a silent divergence.

<details><summary>验证记录</summary>

Verified in MuseAmp/Backend/Playback/PlaybackTimeFormatting.swift: formattedDuration(millis:) and formattedDuration(seconds:) (lines 22-28) duplicate the minute:second formatting that formattedPlaybackTime (lines 10-20) implements, minus the negative clamp and hour rollover. formattedDuration(seconds: 3700) -> "61:40" vs formattedPlaybackTime(3700) -> "1:01:40"; formattedDuration(seconds: -5) -> "0:-5". Call sites confirm the user-visible split: formattedDuration feeds list trailing text (SongRowContent+AppModels, AlbumTrackCellContent+AppModels, SearchViewController) while formattedPlaybackTime feeds transport/popup/TV, so a >1h track renders inconsistently between list and player. AGENTS.md does not endorse the duplication, and nothing (naming, comments) suggests the divergence is deliberate. The suggested unification is local and style-consistent. Severity stays low: the divergence only manifests for >1h tracks, and negative input is largely theoretical (one call site guards seconds > 0, millis come from catalog data).

</details>

## [clarity] backend-playlist-lyrics (19)

### [MEDIUM] extractEmbeddedLyrics swallows AVFoundation errors via try? without logging

`MuseAmp/Backend/Lyrics/LyricsReloadService.swift:127` · error-boundaries

**问题**: Three try? expressions discard errors silently: `try? await AVMetadataHelper.collectMetadataItems(from: asset)` (line 127) and the two `try? await item.load(...)` calls (lines 134, 140). A metadata read failure makes the whole embedded-lyrics path return nil, which forces a network fetch in reloadLyrics — a consequential fallback with zero log trace. AGENTS.md Logging Rules require every error-swallowing try? to log via AppLog.error or AppLog.warning.

**建议**: Convert at least the collectMetadataItems call to do/catch and AppLog.warning with the file URL's last path component before returning nil; the per-item load failures can share one warning.

<details><summary>验证记录</summary>

Confirmed: LyricsReloadService.swift line 127 swallows the collectMetadataItems error via try? with no logging, directly violating AGENTS.md Logging Rules line 203 ("Every catch block or try? that silently swallows an error must log via AppLog.error or AppLog.warning"). A silent failure here forces a network fetch plus a disk re-embed with zero trace. Crucially, every other production call site of collectMetadataItems in the repo (ExportMetadataProcessor, AudioFileImporter, TrackArtworkRepairService, EmbeddedMetadataReader, SyncPreparedTrackBuilder, DownloadArtworkProcessor) uses try await and propagates the error, so the fix aligns with—rather than diverges from—repo convention; the same file already uses do/catch + AppLog.warning in embedLyricsIfPossible. Caveat: the per-item try? await item.load(...) calls (lines 134/140) ARE the pervasive unlogged convention across 6+ files, so only the collect-level swallow is the strong violation; the suggestion appropriately makes the per-item logging optional/shared. Not convention-endorsed: AGENTS.md explicitly prohibits the flagged pattern.

</details>

### [MEDIUM] shuffled boolean flag silently flips three behaviors of image(for:)

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:41` · function-design

**问题**: The `shuffled: Bool = false` parameter does far more than shuffle tile order: it bypasses both memory and disk cache reads (line 47), randomizes song order (line 60), and suppresses the `.playlistArtworkDidUpdate` notification (line 90). A call site reading `image(for: playlist, ..., shuffled: true)` cannot know it also skips caching and notification. This is a classic boolean behavior flag (principle 3).

**建议**: Split into two intent-named entry points, e.g. `image(for:...)` and `rerolledImage(for:...)` (or an explicit `enum CoverVariant { case cached, shuffledPreview }`), sharing a private render core.

<details><summary>验证记录</summary>

Confirmed in PlaylistCoverArtworkCache.swift: the single `shuffled` flag bypasses memory/disk cache reads (line 47), randomizes song order (line 60), and suppresses .playlistArtworkDidUpdate (line 90), while still unconditionally persisting the shuffled render to cache (lines 88-89) — a hidden write-without-notify asymmetry the name does not convey. The test had to be named 'Shuffled flag skips disk cache and regenerates' to document the hidden meaning, and the flag leaks through generatedCoverImage(for:sideLength:shuffled:) to a call site whose real intent is 'regenerate' (which redundantly invalidates the cache first). AGENTS.md does not endorse multi-behavior boolean parameters; its only `shuffled: Bool` reference is MusicPlayer's single-meaning queue-shuffle property. Splitting into intent-named entry points sharing a private render core fits the repo's responsibility-based splitting convention.

</details>

### [MEDIUM] Sentinel strings 'unknown'/'unknown album' duplicate scattered fallback knowledge and miss localized values

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:133` · seams-duplication

**问题**: coverIdentity hardcodes `albumID != "unknown"` (line 129) and `albumTitle != "unknown album"` (line 133). The albumID check re-implements the existing `String.isKnownAlbumID` helper (MuseAmp/Backend/Supplement/StringUtilities.swift:13). The album-title sentinel is compared against a lowercased English literal, but the value actually written by importers is `String(localized: "Unknown Album")` (EmbeddedMetadataReader.swift:61, AudioFileImporter.swift:216) — under zh-Hans the stored fallback is the Chinese translation, so the check never matches and all unknown-album songs collapse into one mosaic tile. The sentinel contract lives in three modules with no shared name.

**建议**: Use the existing `isKnownAlbumID` for the albumID branch and add a sibling helper (e.g. `isKnownAlbumTitle`) in StringUtilities that compares against the actual `String(localized: "Unknown Album")` fallback, so the sentinel is defined once next to its producer.

<details><summary>验证记录</summary>

Verified all factual claims. (1) PlaylistCoverArtworkCache.swift:129/133 hardcode the sentinels as described. (2) The albumID check duplicates the existing String.isKnownAlbumID helper (StringUtilities.swift:12), which is the established idiom with 6 other call sites. (3) The localization mismatch is real: importers (EmbeddedMetadataReader.swift:61/74, AudioFileImporter.swift:216, DownloadManager+Digger.swift:262, SyncPreparedTrackBuilder+Export.swift:205) store String(localized: "Unknown Album"), translated to 未知专辑 in zh-Hans per Localizable.xcstrings; AudioTrackRecord.playlistEntry passes albumTitle through with nil artworkURL and albumID "unknown", so the lowercased English comparison "unknown album" never matches under zh-Hans, collapsing all unknown-album songs into one cover identity instead of falling through to per-song keys as the en path does. (4) No AGENTS.md exists; project CLAUDE.md does not endorse inline sentinel literals, and the shared StringUtilities helper shows centralization is the dominant convention, so the suggested fix matches repo style. Medium severity is apt: a locale-dependent behavior divergence already exists, but its impact is cosmetic (mosaic tile dedup in generated playlist covers).

</details>

### [MEDIUM] Canonical playlist creation goes through a command named importLegacyPlaylists

`MuseAmp/Backend/Playlist/PlaylistStore.swift:39` · naming

**问题**: Both createPlaylist (line 39) and importPlaylist (line 63) persist brand-new playlists via `send(.importLegacyPlaylists([candidate]))`. The command name (declared in MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/LibraryCommand.swift:31) tells a reader this is one-time migration code, when it is in fact the only creation path in the app. The name actively misleads about intent.

**建议**: Rename the LibraryCommand case to something honest such as `.upsertPlaylists` (updating DatabaseManager+Commands.swift and StateStore.swift), or at minimum wrap the send in a store-private helper named for intent, e.g. `persist(_ playlist: Playlist)`.

<details><summary>验证记录</summary>

Confirmed: PlaylistStore.swift:39 and :63 persist all brand-new playlists via .importLegacyPlaylists, which StateStore.swift:209 implements as a general upsert (insertOrReplace + entry rewrite) also used by duplicatePlaylist. The misleading effect is compounded by LibraryCommand.createPlaylist(name:) existing but being sent only from tests, so a reader would misidentify both the real and the apparent creation path. AGENTS.md does not endorse the name; the enum's own convention (.upsertDownloadJob) supports the suggested .upsertPlaylists rename, so the fix aligns with repo style rather than violating it. No evidence it has already bred a bug, so medium (actively misleads) stands.

</details>

### [MEDIUM] Mutation-finish pattern fragmented across three variants

`MuseAmp/Backend/Playlist/PlaylistStore.swift:162` · seams-duplication

**问题**: performMutation (PlaylistStore+Support.swift:130) is the canonical snapshot/do-catch-log/reload/notify seam, yet updateSong (lines 162-182) hand-rolls exactly that sequence inline; removeSong (149-160) and clearSongs (297-308) hand-roll the do/catch+log then call finishMutation; addSong (124-137) is a third inline variant. Additionally, finishMutation's `pruneLikedPlaylistIfNeededFor: UUID? = nil` default is dead — both call sites (lines 159 and 307) pass a value. A reader must compare four near-identical code shapes to confirm they behave the same.

**建议**: Add the `pruneLikedPlaylistIfNeededFor: UUID? = nil` parameter to performMutation (absorbing finishMutation), then route updateSong, removeSong, and clearSongs through it; drop the never-used nil default if no caller needs it.

<details><summary>验证记录</summary>

Every factual claim checks out: performMutation (PlaylistStore+Support.swift:130) is the canonical do/catch+log/reload/notify seam used by 6 methods; updateSong (PlaylistStore.swift:162-182) hand-rolls the identical sequence inline despite having no return value or other constraint preventing use of the seam; removeSong (149-160) and clearSongs (297-308) hand-roll do/catch+log then call finishMutation, a second helper differing from performMutation only by the liked-playlist prune step; and finishMutation's `pruneLikedPlaylistIfNeededFor = nil` default is dead (grep confirms only two call sites, both passing a value). addSong is a weaker example since it legitimately needs a Bool return and onSongAdded callback (like createPlaylist/importPlaylist/duplicatePlaylist), but the finding acknowledges it as merely a variant. AGENTS.md does not endorse the fragmentation; the module's own dominant convention is the performMutation seam, so the suggested consolidation aligns with local style rather than fighting it. The performMutation-vs-finishMutation split plus inline copies obscures whether updateSong's lack of pruning is intentional and invites a future mutation to silently miss the prune step, justifying medium severity.

</details>

### [MEDIUM] Field-by-field entry rewrap hides the intent of regenerating entryID

`MuseAmp/Backend/Playlist/PlaylistStore.swift:113` · naming

**问题**: addSong rebuilds the incoming PlaylistEntry by copying nine fields verbatim (lines 113-123). The only effect is that the omitted `entryID:` argument falls back to `UUID().uuidString` (PlaylistEntry.swift:27), giving the row a fresh identity so the same track can be added twice. Nothing at the call site names or explains this; a maintainer could 'simplify' it to `send(.addPlaylistEntry(song, ...))` and silently break entry-ID uniqueness.

**建议**: Extract the rewrap into a named helper, e.g. `private func entryWithFreshEntryID(from song: PlaylistEntry) -> PlaylistEntry`, or add a PlaylistEntry factory `regeneratingEntryID()` in the app-side Playlist.swift extension, so the intent is carried by the name.

<details><summary>验证记录</summary>

Verified: addSong (PlaylistStore.swift:113-123) rebuilds PlaylistEntry copying all nine fields verbatim, omitting only entryID, which defaults to UUID().uuidString (PlaylistEntry.swift:27). The fresh entryID is load-bearing: entryID is the unique primary key in PlaylistEntryRow (isPrimary/isUnique constraint), and callers mergeSongs and toggleLiked pass already-persisted entries — reusing their entryID would collide on the unique key and silently move/clobber the source row. Nothing at the call site names this intent; the copy reads as a removable no-op, so a simplifying refactor would corrupt playlist data. Other field-by-field constructions in the same file (refreshSongs) visibly transform or merge data, so this verbatim copy is not a deliberate local convention, and AGENTS.md neither mandates nor endorses the pattern. The suggested named helper (or factory method) fits repo style and removes real ambiguity. Severity medium is appropriate: actively misleads and invites a data-integrity bug, though none has shipped.

</details>

### [LOW] Dead .none switch branch handled with fatalError

`MuseAmp/Backend/Lyrics/LyricsChineseScriptConverter.swift:39` · state-modeling

**问题**: convertToSystemScript guards `script != .none` (line 34) and then must still write `case .none: fatalError()` (line 39) because the switch over the same enum cannot see the guard. The enum shape (mixing 'no Chinese script' into the script-direction type) forces a crash placeholder into a pure text utility; any future refactor that reorders the guard turns it into a real crash.

**建议**: Model the transform on the enum: `var transformName: CFString? { switch self { case .simplified: "Hant-Hans" as CFString; case .traditional: "Hans-Hant" as CFString; case .none: nil } }` and write `guard let transform = systemChineseScript.transformName else { return text }`, eliminating both the guard/switch split and the fatalError.

<details><summary>验证记录</summary>

Verified: convertToSystemScript guards `script != .none` then immediately switches over the same enum and must write `case .none: fatalError()` for exhaustiveness — the .none case is handled twice, once correctly and once as a crash placeholder whose safety depends on the guard above it. Repo-wide grep shows no precedent for switch-branch fatalError placeholders (all other bare fatalError() calls are init(coder:) boilerplate or deliberate bootstrap aborts), so conventionEndorsed=false. The suggested fix (derive the transform name from the enum as an optional and consume via guard-let, or simply `case .none: return text`) matches AGENTS.md Code Style guidance on early returns/guard and derived values, and reads like the rest of the codebase. Severity stays low: the fatalError is currently unreachable and the harm is speculative, making this a cosmetic clarity/state-modeling issue rather than an active bug source.

</details>

### [LOW] Downloaded-file state spread across three correlated locals

`MuseAmp/Backend/Lyrics/LyricsReloadService.swift:42` · state-modeling

**问题**: Lines 42-44 derive `track` (optional), `fileURL` (optional), and `fileExists` (Bool) — three variables describing the single condition 'this track has a readable downloaded file'. The combination is then re-unwrapped twice: `fileExists, let fileURL` plus embedded check (lines 47-49) and `fileExists, let fileURL, let track` (line 66). This is the hidden-state-machine pattern: related optionals/flags standing in for one value.

**建议**: Compute once: `let localFile: (track: AudioTrackRecord, url: URL)? = ...` (nil unless the track exists and FileManager.default.isReadableFile passes), then `if let localFile` at both use sites.

<details><summary>验证记录</summary>

Confirmed at MuseAmp/Backend/Lyrics/LyricsReloadService.swift:42-44: three correlated locals (optional track, optional fileURL derived from track, Bool fileExists derived from fileURL) encode the single condition "track has a readable downloaded file", and the invariant is re-proven at both use sites ('fileExists, let fileURL' at 47-48; 'fileExists, let fileURL, let track' at 66). AGENTS.md does not endorse this pattern; the repo's dominant convention collapses existence checks into the optional itself (e.g. Backend/Library/AudioTrackRecord+AppModels.swift:49 uses 'fileExists ? url : nil') or inline guards, so the suggested single optional tuple matches local style. Severity stays low: the function is short and readable, no bug has resulted — purely cosmetic clarity.

</details>

### [LOW] Cache-key version literal 'v3' duplicated between cacheKey and invalidateCache

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:250` · named-constants

**问题**: cacheKey builds "v3-\(playlist.id.uuidString)-..." (line 250) while invalidateCache independently rebuilds the prefix "v3-\(playlist.id.uuidString)-" (line 25). If the version is bumped to v4 in one place but not the other, invalidation silently stops matching files and stale v3 PNGs accumulate forever. A repeated magic string encoding a versioning contract.

**建议**: Hoist `private static let cacheKeyVersion = "v3"` and derive both the key and the invalidation prefix from one helper, e.g. `cacheKeyPrefix(for: playlist)`.

<details><summary>验证记录</summary>

Verified: the "v3" version literal is duplicated at lines 25 (invalidateCache prefix) and 250 (cacheKey) of PlaylistCoverArtworkCache.swift, and invalidation correctness depends on the two staying format-compatible. AGENTS.md does not endorse the pattern, and the suggested fix (single constant/prefix helper beside the existing cacheKey method) is repo-consistent. However, the blast radius of a divergent bump is small: keys already embed updatedAt timestamp and song count, so stale entries are never served as wrong images; the failure mode is only orphaned PNGs in the OS-purgeable caches directory, plus the memory cache is cleared wholesale. Real clarity/duplication issue, but closer to cosmetic maintenance hygiene than a bug-breeding hazard, so severity is adjusted to low.

</details>

### [LOW] invalidateCache swallows file I/O errors with try? and no log

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:28` · error-boundaries

**问题**: Both `try? fileManager.contentsOfDirectory(...)` (line 28) and `try? fileManager.removeItem(at:)` (line 30) silently discard errors. AGENTS.md Logging Rules require every error-swallowing try? to log via AppLog.error/AppLog.warning, and file deletes in persistence stores must log failures. The function then logs 'cache invalidated' at .info even when nothing was actually removed, which is misleading during diagnosis.

**建议**: Use do/catch around contentsOfDirectory and removeItem and emit AppLog.warning/AppLog.error with the failing path, so the .info success line is trustworthy.

<details><summary>验证记录</summary>

Confirmed: lines 28 and 30 of PlaylistCoverArtworkCache.swift use try? to silently swallow contentsOfDirectory and removeItem errors, then line 33 logs an unconditional .info "cache invalidated" success message. Project Logging Rules explicitly require every error-swallowing try? to log via AppLog.error/warning and require file-delete failures to be logged, so the pattern is a rule violation, not an endorsed convention. The fix also matches the dominant local style — write(image:to:) in the same file (lines 253-260) already uses do/catch with AppLog.error for file I/O. Severity downgraded to low: cacheKey includes playlist.updatedAt and song count, so failed disk cleanup never serves stale artwork (new renders get new keys); the only harm is a misleading diagnostic log and orphaned cache files, and the contentsOfDirectory try? failure is even expected before the directory first exists. The finding is real but its impact is diagnostic-only, not bug-breeding.

</details>

### [LOW] Kingfisher retrieval failure dropped without a trace

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:241` · error-boundaries

**问题**: retrieveImage's `case .failure:` (lines 241-242) resumes with nil and discards the KingfisherError entirely. Downstream, only an aggregate count is logged (warning when ALL tiles fail, verbose success ratio otherwise), so a single persistently-failing artwork URL renders as a gray tile with no log line identifying the URL or error. AGENTS.md requires swallowed errors to leave a log trace.

**建议**: In the failure case, log `AppLog.warning(self, "cover tile load failed url=... error=...")` (redacting auth params per logging rules) before resuming with nil.

<details><summary>验证记录</summary>

Cited code confirmed at PlaylistCoverArtworkCache.swift:241-242 — KingfisherError discarded, only aggregate counts logged (warning only when ALL tiles fail; verbose ratio otherwise), so individual failing URLs leave no trace. AGENTS.md line 203 mandates logging swallowed errors via AppLog.error/warning. Decisively, three sibling app-target call sites of the identical retrieveImage+continuation pattern (NowPlayingArtworkBackgroundCoordinator.swift:161, TabBarController+Popup.swift:245, MainController+Popup.swift:270) all AppLog.warning the failure with URL and error before resuming nil — the suggested fix matches the dominant repo convention rather than violating it. Severity stays low: it is a diagnostics gap in a cosmetic collage feature, not misleading code.

</details>

### [LOW] NSCache used where AGENTS.md mandates LRUCache for bounded in-memory caches

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:14` · repository-conventions

**问题**: `private let memoryCache = NSCache<NSString, UIImage>()` with `countLimit = 512` (line 21) is exactly the 'bounded in-memory cache' case for which AGENTS.md Preferred Libraries says 'Use LRUCache for bounded in-memory caches' (LRUCache is already a project dependency and auto-clears on memory warnings with predictable eviction). NSCache's opaque key model is also what forces the over-broad removeAllObjects in invalidateCache.

**建议**: Replace NSCache with `LRUCache<String, UIImage>(countLimit: 512)`, which also removes the NSString key bridging at lines 48, 54, and 88.

<details><summary>验证记录</summary>

Confirmed: PlaylistCoverArtworkCache.swift line 14 uses NSCache<NSString, UIImage> with countLimit = 512 (line 21) — exactly the 'bounded in-memory cache' case AGENTS.md line 274 mandates LRUCache for ('Use LRUCache for bounded in-memory caches'; the AGENTS.md LRUCache section even bills it as 'replacing NSCache'). LRUCache is already a dependency and is the dominant convention (3 LRUCache usages vs 2 NSCache in app code). The NSString bridging at lines 48/54/88 and the removeAllObjects in invalidateCache (line 26, despite computing a per-playlist prefix used for targeted disk deletion) are accurately described. The suggested fix aligns the file with both AGENTS.md and surrounding code. Severity adjusted to low: the only behavioral consequence is over-broad memory invalidation that falls back to disk-cache reads — no bug, no reader actively misled.

</details>

### [LOW] invalidateCache(for: playlist) wipes the memory cache for every playlist

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:26` · naming

**问题**: The method name promises per-playlist invalidation, and the disk branch does filter by the playlist's key prefix (line 29), but line 26 calls `memoryCache.removeAllObjects()`, evicting cached covers of all other playlists too. The asymmetry between name, disk behavior, and memory behavior is invisible at call sites (PlaylistDetailViewController+Menu.swift:179).

**建议**: Track the memory keys inserted per playlist ID (the actor already constructs every key) and remove only those; if switching to LRUCache per the convention finding, filter its keys by the shared prefix helper instead of flushing everything.

<details><summary>验证记录</summary>

Confirmed at PlaylistCoverArtworkCache.swift lines 24-33: invalidateCache(for:) names a per-playlist operation and its disk branch filters by the playlist key prefix, but line 26 calls memoryCache.removeAllObjects(), evicting every playlist's covers. The asymmetry is invisible at the only call site (PlaylistDetailViewController+Menu.swift:179) and contradicted by the per-playlist log message. The best refutation — NSCache cannot enumerate keys, so a full flush is the only option — actually supports the fix: repo conventions mandate LRUCache for bounded in-memory caches, and LRUCache exposes allKeys, making prefix-scoped removal trivial and convention-aligned. No AGENTS.md rule endorses blanket flushes. Impact is behavior-safe over-invalidation (covers regenerate from disk; keys embed updatedAt), so severity stays low/cosmetic.

</details>

### [LOW] Unnamed magic numbers and repeated placeholder color in cover rendering

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:106` · named-constants

**问题**: Line 21 sets `memoryCache.countLimit = 512`, line 106 caps the mosaic at `8` (i.e. 8x8 = 64 tiles) — both bare literals with no name explaining the bound. `UIColor.systemGray5` is bound to a local `placeholderColor` in render (line 158) but hardcoded again inside drawAspectFill (line 192), so changing the placeholder requires finding both.

**建议**: Hoist `private static let memoryCacheCountLimit = 512`, `private static let maxGridDimension = 8`, and `private static let placeholderFillColor = UIColor.systemGray5` to type scope and use them in all sites.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift: line 21 has `memoryCache.countLimit = 512` (bare literal), line 106 has `min(max(Int(floor(sqrt(Double(songCount)))), 1), 8)` where the 8-tile grid cap is unexplained, and `UIColor.systemGray5` appears both as the local `placeholderColor` in render (line 158) and hardcoded again in drawAspectFill's degenerate-image branch (line 192) — changing the placeholder color requires editing two sites. Attempted refutation via convention: the suggestion actually MATCHES the dominant local convention rather than violating it — the sibling file in the same folder, Backend/Playlist/LikedSongsPlaylistArtwork.swift, declares `private static let canvasSize = CGSize(width: 1024, height: 1024)` and `private static let symbolSideLength: CGFloat = 512`, and Backend/Sync/SyncBonjourIdentity.swift uses `private static let tokenLength = 6` / `maxServiceNameUTF8Bytes = 63`. AGENTS.md does not endorse bare literals here; its only hardcoded-value mandate (200 pt spacers) is specific to lyrics/queue list headers and irrelevant to this file. The finding is accurate, the fix aligns with repo style, and the duplicated systemGray5 is a genuine (if minor) maintenance hazard. Severity stays low: purely cosmetic clarity, no misleading behavior, and the drawAspectFill fallback branch is rarely executed.

</details>

### [LOW] Empty extension file with only imports

`MuseAmp/Backend/Playlist/PlaylistStore+Bridge.swift:9` · file-organization

**问题**: The file contains a header comment and two imports (Foundation, MuseAmpDatabaseKit) but zero declarations. The filename promises a 'Bridge' responsibility of PlaylistStore that does not exist, so a reader searching for bridging code lands on an empty file. This violates 'filename = export': the file exports nothing.

**建议**: Delete PlaylistStore+Bridge.swift (and its Xcode group entry) until there is actual bridge code to host; re-create it when needed.

<details><summary>验证记录</summary>

Verified: MuseAmp/Backend/Playlist/PlaylistStore+Bridge.swift contains only a header comment, `import Foundation`, and `import MuseAmpDatabaseKit` — zero declarations — and git history shows it has been empty since the init commit (4c3d9c9). No PlaylistStore bridge code exists elsewhere, so the filename promises a responsibility that does not exist. A second identical empty file exists (Backend/Library/MusicLibraryDatabase+Bridge.swift) and both are symlinked into MuseAmpTV/Backend/, but two leftover empties are not a deliberate convention, and AGENTS.md endorses responsibility-based +Extension splits only when they host code — it never endorses empty placeholder files. Deleting the file (plus its MuseAmpTV symlink and Xcode group entry) cannot break compilation since it exports nothing, and matches repo style. Severity remains low: it misleads a reader searching for bridging code but is cosmetic.

</details>

### [LOW] createPlaylist duplicates importPlaylist body

`MuseAmp/Backend/Playlist/PlaylistStore.swift:35` · seams-duplication

**问题**: createPlaylist (lines 34-46) and importPlaylist (lines 48-70) have identical structure: snapshot previousPlaylists, build a Playlist candidate, send(.importLegacyPlaylists([candidate])), catch+AppLog.error, reload(), notifyIfNeeded, return playlist(for: id) ?? candidate. The only difference is that importPlaylist passes entries. Two copies of the same persistence sequence must now be kept in sync (they already drifted only in the log tag).

**建议**: Have createPlaylist delegate: `return importPlaylist(id: id, name: name, coverImageData: coverImageData, entries: [])` (Playlist.init already defaults entries to []), keeping one canonical insert path.

<details><summary>验证记录</summary>

Confirmed: createPlaylist and importPlaylist in PlaylistStore.swift share an identical persistence sequence (snapshot, Playlist candidate, send(.importLegacyPlaylists), catch+AppLog.error, reload, notifyIfNeeded, return playlist(for:) ?? candidate), differing only in the entries parameter and log tag. The suggested delegation is behavior-equivalent since Playlist.init defaults entries to []. The module's own convention (performMutation in PlaylistStore+Support.swift centralizing this exact try/log/reload/notify sequence for other mutations) supports consolidation, so the fix matches surrounding style; AGENTS.md does not endorse the duplication. However, the only drift cited is the log tag, which is intentional entry-point labeling, not a latent bug; the functions are adjacent, small, and easy to compare. Real but closer to cosmetic clarity than active bug-breeding, so severity adjusted to low.

</details>

### [LOW] Seven hand-written change flags re-implement PlaylistEntry equality

`MuseAmp/Backend/Playlist/PlaylistStore.swift:242` · seams-duplication

**问题**: refreshSongs builds `merged` preserving existing.entryID, existing.trackID, and existing.lyrics, then compares the seven remaining fields one by one (nameChanged/artistChanged/artworkChanged/albumIDChanged/albumNameChanged/durationChanged/trackNumChanged, lines 242-254). Since PlaylistEntry is Hashable/Equatable (MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Models/PlaylistEntry.swift:10), the disjunction is exactly `merged != existing`. Worse, if a field is ever added to PlaylistEntry, this flag list silently stops detecting changes to it.

**建议**: Replace lines 242-254 with `guard merged != existing else { continue }`, relying on the synthesized Equatable.

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/Playlist/PlaylistStore.swift:230-254: merged copies entryID/trackID/lyrics from existing, so the seven flag comparisons cover exactly the remaining fields of PlaylistEntry, and the disjunction is provably equivalent to `merged != existing` via the synthesized Equatable (PlaylistEntry is Hashable with no custom ==). The flags are used only in the guard, never logged. AGENTS.md does not endorse the pattern and no similar multi-flag diff pattern exists elsewhere in the repo; the suggested one-line guard matches the repo's early-return/guard style. Severity adjusted to low: the flags are accurately named and don't mislead, the duplication is verbose but local, and the future-field hazard is speculative (and only partially fixed by != since the merged memberwise init has defaults).

</details>

### [LOW] Store state `playlists` is externally settable

`MuseAmp/Backend/Playlist/PlaylistStore.swift:21` · class-design

**问题**: `var playlists: [Playlist] = []` is internal and mutable, but every external use is read-only (menus, sidebar, view controllers); only reload() in this file writes it. The store is the single owner of this state per the repo's 'state ownership in Backend' rule, yet the declaration permits any caller to overwrite the cache and skip the notify/diff machinery.

**建议**: Declare it `private(set) var playlists: [Playlist] = []` (the only writer, reload(), lives in the same file, so file-scoped setter access suffices).

<details><summary>验证记录</summary>

Verified at PlaylistStore.swift:21. The only writer of `playlists` is reload() in the same file; the PlaylistStore+Support.swift extension and all ~40 external call sites (menu providers, sidebar, playlist/search/sync view controllers) are read-only, confirmed by grep across MuseAmp and MuseAmpTV. `private(set)` would compile (setter access is file-scoped and the extension only reads) and is a zero-risk tightening. AGENTS.md does not endorse openly mutable store state — its "keep state ownership in Backend/" rule points the other way — and `private(set) var` is already the dominant convention in the codebase (23 occurrences, including Backend stores SyncTransferSession and SyncBonjourBrowser), so the fix matches local style. Severity remains low: no caller currently abuses the open setter, so this is preventive encapsulation/clarity, not an active defect.

</details>

### [LOW] onSongAdded callback seam has no production consumer

`MuseAmp/Backend/Playlist/PlaylistStore.swift:23` · seams-duplication

**问题**: `var onSongAdded: (PlaylistEntry) -> Void = { _ in }` is invoked at line 134 but is assigned only in tests (MuseAmpTests/Downloads/DownloadSyncTests.swift:107,130). No production code observes it, so a reader tracing addSong assumes a downstream reaction that does not exist. Per the seams principle, seams should exist where behavior actually varies.

**建议**: Remove the callback and have the tests assert on the existing `.playlistsDidChange` notification / addSong's returned Bool, or keep it only if a production consumer is imminent and document the test seam at the declaration.

<details><summary>验证记录</summary>

Verified: onSongAdded is declared at PlaylistStore.swift:23 and invoked at line 134, but repo-wide grep confirms it is assigned only in MuseAmpTests/Downloads/DownloadSyncTests.swift (lines 107, 130). No production or tvOS consumer exists. The tests are circular — they exist solely to verify the callback fires, while the same behavior is already observable via addSong's returned Bool, the playlists state (both already asserted in those tests), and the .playlistsDidChange notification posted in the same branch. AGENTS.md's Property Rules endorse the non-optional-with-empty-default callback style only for closures "always assigned before use," which does not apply to a never-assigned-in-production seam, and the Testing Rules ("prefer asserting observable side effects or state changes") align with the suggested fix. Removing the callback would not make the code read unlike the repo. Severity stays low: it mildly misleads a reader tracing addSong but does not breed bugs.

</details>

## [clarity] backend-sync-support (20)

### [MEDIUM] Convoluted addedIDs compactMap duplicated in two action handlers

`MuseAmp/Backend/MenuProviders/AddToPlaylistMenuProvider.swift:85` · seams-duplication

**问题**: Lines 85-90 and 105-110 duplicate the same block: `let addedIDs = songsProvider().compactMap { song -> UUID? in self?.playlistStore.addSong(song, to: id) == true ? id : nil }; if let first = addedIDs.first { onAdd?(first) }`. Besides being duplicated, the logic is misleading: `addedIDs` is the SAME playlist ID repeated once per successfully added song, and only `.first` is consumed — the array exists solely to test "did at least one add succeed", which takes real effort to decode.

**建议**: Extract a private func addSongs(_ songs: [PlaylistEntry], to playlistID: UUID, onAdd: ((UUID) -> Void)?) that does `let didAddAny = songs.contains { playlistStore.addSong($0, to: playlistID) }` (or reduce over all songs if every add must run) and calls onAdd?(playlistID) when didAddAny, then call it from both handlers.

<details><summary>验证记录</summary>

Confirmed at MuseAmp/Backend/MenuProviders/AddToPlaylistMenuProvider.swift lines 85-90 and 105-110: two verbatim-duplicated blocks where a side-effecting compactMap (each closure call mutates playlistStore via addSong) builds `addedIDs`, an array that is just the SAME playlist UUID repeated once per successful add, and only `.first` is consumed to decide whether to fire onAdd. The name `addedIDs` falsely implies song IDs or distinct IDs; the array exists solely to encode 'did at least one add succeed'. This is genuinely misleading and bug-prone: a naive cleanup to `songs.contains { store.addSong(...) }` would short-circuit and stop adding remaining songs after the first success, which the suggestion itself correctly flags ('reduce over all songs if every add must run'). The repo shows no convention of side-effecting compactMap (other compactMap uses are pure transforms), AGENTS.md does not endorse the pattern, and extracting a private helper matches the file's existing style (cf. presentCreatePlaylistAlert) without violating any rule. Severity medium is fair: it actively misleads readers and the obvious refactor breeds a behavior bug.

</details>

### [MEDIUM] init parameter totalTrackCount is silently ignored

`MuseAmp/Backend/Sync/SyncPlaylistTransferPlan.swift:20` · function-design

**问题**: `init(transferableTracks: [AudioTrackRecord], totalTrackCount _: Int)` discards its second argument (note the `_` internal name). The caller SyncPlaylistAppleTVSenderViewController.swift:318-321 dutifully passes `totalTrackCount: tracks.count`, reasonably believing it affects the plan. A labeled, required parameter that does nothing is actively misleading API surface.

**建议**: Remove the totalTrackCount parameter from the init and update the single call site, or actually use it (e.g. to populate skippedTrackIDs / expected counts) if the value is meant to matter.

<details><summary>验证记录</summary>

Verified: SyncPlaylistTransferPlan.swift:20 declares init(transferableTracks:totalTrackCount _:) and the body never uses the second argument. Both call sites (SyncPlaylistAppleTVSenderViewController.swift:318-321 and SyncPlaylistTransferPlanTests.swift:56-58) pass totalTrackCount: tracks.count, so the parameter is pure dead weight today. It is actively misleading because SyncPlaylistSession has an expectedTrackCount init parameter (SyncProtocol.swift:203) that this value plausibly should feed but does not — a caller passing a different total expecting it to affect expected counts or skippedTrackIDs would get a silent no-op. No AGENTS.md rule or local module convention endorses discarded parameters; the file is symlinked into MuseAmpTV but both targets compile the same source, so removing the parameter and updating the two call sites is safe and consistent with repo style.

</details>

### [MEDIUM] prepareItemWithMetadata duplicates the entire embed pipeline in both branches

`MuseAmp/Backend/Sync/SyncPreparedTrackBuilder+Export.swift:97` · seams-duplication

**问题**: The includeLyrics branch (lines 97-140) and the else/not-metadataPresent branch (lines 148-195) contain near-verbatim copies of the same ~45-line pipeline: ExportMetadataProcessor.ExportInfo construction (103-111 vs 157-165), validateExportInfo (112 vs 166), the identical artwork-fetch block with the same try? DownloadArtworkProcessor.cachedArtworkData call and verbose log (114-128 vs 168-182), and the identical embed do/catch with cleanupPreparedFile + rethrow (130-140 vs 184-194). The only real difference is the lyrics source: fetchOrCachedLyrics(for:) vs lyricsCacheStore?.lyrics(for:). Any future change to the embed flow must be made twice and the copies can silently drift.

**建议**: Extract a single private helper, e.g. func embedExportMetadata(for item: SongExportItem, lyrics: String?, into destinationURL: URL) async throws, containing ExportInfo build + validate + artwork fetch + embed do/catch. The two branches then reduce to choosing the lyrics value (await fetchOrCachedLyrics vs cached-only) and calling the helper, with the metadata-present skip kept as an early path.

<details><summary>验证记录</summary>

Confirmed by direct read of MuseAmp/Backend/Sync/SyncPreparedTrackBuilder+Export.swift: lines 103-140 and 157-194 are near-verbatim copies of the same ExportInfo build + validateExportInfo + artwork-fetch + embed do/catch pipeline (the artwork block and embed do/catch are byte-for-byte identical, including log strings and cleanupPreparedFile+rethrow). The only real differences are the lyrics source (fetchOrCachedLyrics vs lyricsCacheStore-only) and the metadataPresent early-skip, which the suggested helper extraction preserves cleanly. AGENTS.md does not endorse this duplication; its style rules (early returns, shared helpers, responsibility-based extensions) and the file's own existing helper fetchOrCachedLyrics(for:) make the suggested private helper fit the local convention. Severity lowered from high to medium: the copies have not yet drifted (no bug bred so far), but duplicated error-handling/cleanup logic of this size is a real drift risk where a one-sided future fix would silently diverge.

</details>

### [MEDIUM] Identical user-facing validation messages duplicated three times each

`MuseAmp/Backend/Sync/TVPlaylistSessionStore.swift:143` · named-constants

**问题**: The literal String(localized: "The transferred playlist data on Apple TV is incomplete. Send it again from iPhone.") appears verbatim at lines 143, 151, and 160, and String(localized: "Apple TV cleaned part of the transferred playlist. Send it again from iPhone.") appears verbatim at lines 176, 183, and 192. Six repetitions of two user-facing strings invite copy drift between the duplicates (and between their xcstrings entries) when the wording is edited.

**建议**: Hoist each message into a private static let (e.g. incompleteSessionMessage / cleanedSessionMessage) or a small private func invalid(_ reason:) helper that wraps AppLog + .invalid(message), and reuse it at all six return sites.

<details><summary>验证记录</summary>

Verified: in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Backend/Sync/TVPlaylistSessionStore.swift the literal "The transferred playlist data on Apple TV is incomplete. Send it again from iPhone." appears verbatim at lines 143, 151, and 160, and "Apple TV cleaned part of the transferred playlist. Send it again from iPhone." appears verbatim at lines 176, 183, and 192 (a near-identical third variant "unavailable" also sits at line 168, increasing the confusability). Because String(localized:) uses the literal as the xcstrings key, editing one of the three copies silently forks the key: the new wording becomes an untranslated key while the stale copies keep the old one, and users see divergent error text depending on which validation guard fired — a failure mode that `make validate-xcstrings` only partially catches (it flags the missing translation, not the wording divergence between the remaining duplicates). The fix is endorsed by, not contrary to, local convention: SyncServer.swift in the same directory (lines 32-33) already hoists repeated user-facing messages into `nonisolated static let` constants (oversizedRequestMessage, invalidRequestMessage). AGENTS.md's localization rules require String(localized:) for user-facing strings, which a hoisted static let still satisfies, and nothing in AGENTS.md mandates inline repetition. The finding is real; severity stays medium per the rubric's "breeds bugs" criterion, though at the mild end since all six sites live within one 65-line function and are likely to be edited together.

</details>

### [LOW] bootstrap swallows directory/Dog init failures and still marks logging configured

`MuseAmp/Backend/Logging/AppLog.swift:26` · error-boundaries

**问题**: `try? locations.ensureDirectoriesExist()` (line 26) and `try? Dog.shared.initialization(writableDir:)` (line 27) silently discard errors, then `configured = true` is set unconditionally (line 28). AGENTS.md requires every swallowed try? to log via AppLog.error/AppLog.warning; here a failed logging bootstrap leaves zero trace anywhere and the guard flag claims success, so no later bootstrap call will retry — all diagnostics for the whole session are silently dead.

**建议**: Replace both try? with do/catch: on ensureDirectoriesExist failure, still attempt Dog init and emit AppLog.error afterwards (best-effort); on Dog initialization failure, leave configured = false so a subsequent bootstrap can retry, and record the error once Dog is available (or via a one-shot stored error logged on next successful bootstrap).

<details><summary>验证记录</summary>

Confirmed: AppLog.swift:26-28 swallows both ensureDirectoriesExist() and Dog.shared.initialization() errors via try? with zero logging, then sets configured = true unconditionally, blocking any retry. This directly violates the repo's own Logging Rule (AGENTS.md:203: every swallowed try? must log via AppLog.error/AppLog.warning) — in the very file that implements that mechanism. The chicken-and-egg defense fails: Dog.join still emits to the os Logger when the file handler is absent, and bootstrap itself already calls AppLog.info on line 30, so a best-effort AppLog.error after the failures is implementable, consistent with local style, and non-trivially useful (visible in Console.app, and persisted when Dog init succeeded but directory setup failed). The suggested fix (do/catch + leave configured=false on Dog failure) does not violate any AGENTS.md rule. Severity adjusted down from medium to low: the practical blast radius is narrow — DatabaseBootstrapper.swift:22 re-runs ensureDirectoriesExist with a throwing try so directory failures surface through boot failure anyway; Dog.initialization also creates its own directory; and the only unrecovered scenario (Dog file-handler init failing while the database boots fine) is a rare sandbox-FS edge case that still leaves an os_log trace ("failed/didn't open the file handler"). So this is a real convention violation and a debugging dead-end in principle, but unlikely to have already bred a bug.

</details>

### [LOW] Vestigial var + unconditional append in albumMenu

`MuseAmp/Backend/MenuProviders/CopyMenuProvider.swift:45` · mechanical-consistency

**问题**: `var children: [UIMenuElement] = [copyAlbumName, copyArtistName]` followed immediately by an unconditional `children.append(copySongNames)` (lines 45-46) is a leftover conditional-append shape with the condition removed. It also means an empty `songNames: [String] = []` default still yields a "Copy All Song Names" action that copies an empty string. The mutation sequence makes a reader hunt for a branch that does not exist.

**建议**: Use a single literal `return menu(children: [copyAlbumName, copyArtistName, copySongNames])`, or restore the intent by appending copySongNames only when !songNames.isEmpty.

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/MenuProviders/CopyMenuProvider.swift:45-47. The var + unconditional append is exactly as described and is genuinely vestigial: the file has only one commit (init), and both appends are unconditional, so a single literal array is strictly clearer. The surrounding-module convention actually supports the fix — elsewhere in MenuProviders/callers (e.g. AlbumDetailViewController+Menu.swift, SongLibraryViewController+Table.swift), `var x: [UIMenuElement] = []` + append is used only when appends are CONDITIONAL; an unconditional append here falsely signals a branch, so the literal-array rewrite makes the code read MORE like the rest of the repo, not less. Caveats that temper severity: (1) the second half of the suggestion ("append copySongNames only when !songNames.isEmpty") would VIOLATE AGENTS.md, which mandates the album Copy menu always include Copy Album Name, Copy Artist Name, and Copy All Song Names — only the single-literal fix is compliant; (2) the empty-string-copy concern is mostly theoretical: both call sites (AlbumDetailViewController+Menu.swift:17, SongLibraryViewController+Table.swift:139) always pass songNames explicitly; the `= []` default is exercised only via the tracks-query-failure fallback, and showing the action then is arguably the AGENTS.md-mandated behavior anyway. Net: a real but purely cosmetic clarity issue; correct fix is `return menu(children: [copyAlbumName, copyArtistName, copySongNames])`. Severity stays low.

</details>

### [LOW] Play Next / Add to Queue actions duplicated verbatim between song and list menus

`MuseAmp/Backend/MenuProviders/PlaybackMenuProvider.swift:33` · seams-duplication

**问题**: songPrimaryActions builds playNextAction and addToQueueAction (lines 33-52) and listPrimaryActions rebuilds the same two UIActions (lines 118-137) with identical titles, SF symbols, Task { @MainActor } bodies, and PlaybackFeedbackPresenter calls — the only difference is `[track]` vs `tracks`. The Play action shells (lines 54-72 vs 140-156) are similarly near-identical. Behavior changes (e.g. a new toast rule) must be applied in two places.

**建议**: Extract private helpers taking a tracks provider, e.g. makePlayNextAction(_ tracks: @escaping () -> [PlaybackTrack]) and makeAddToQueueAction(...), and call them from both menu builders with { [track] } and tracksProvider respectively.

<details><summary>验证记录</summary>

Confirmed: Play Next (lines 33-42 vs 118-127) and Add to Queue (43-52 vs 128-137) UIActions are duplicated verbatim between songPrimaryActions and listPrimaryActions in PlaybackMenuProvider.swift, differing only in [track] vs tracks; the Play shells (54-72 vs 140-156) are near-identical apart from calling different play() overloads. AGENTS.md does not endorse this duplication — the module's dominant convention is extracted make* helpers (makePlayAtMenu in this same file, makeExportAction/makeCopyMenu in SongContextMenuProvider and PlaylistContextMenuProvider), so the suggested makePlayNextAction/makeAddToQueueAction extraction matches repo style and stays compatible with the deferred-menu action-time-fetch rule. Severity downgraded from medium to low: the finding's drift argument ("a new toast rule must be applied in two places") is overstated because toast logic is already centralized in PlaybackFeedbackPresenter per the repo's Feedback Presenter Rules, the duplicated bodies are mostly title/image/one-line controller calls, and both copies are adjacent in one 172-line file where divergence would be easy to spot. Real but cosmetic-leaning clarity issue.

</details>

### [LOW] ASCII "..." in Play At... diverges from the ellipsis character used by sibling menus

`MuseAmp/Backend/MenuProviders/PlaybackMenuProvider.swift:167` · mechanical-consistency

**问题**: makePlayAtMenu uses String(localized: "Play At...") with three ASCII periods (line 167), while peer menu titles in the same folder use the typographic ellipsis: "Merge Into…" (PlaylistContextMenuProvider.swift:107) and "New Playlist…" (AddToPlaylistMenuProvider.swift:24). The inconsistency is user-visible and creates two punctuation styles in Localizable.xcstrings keys.

**建议**: Rename the key to "Play At…" (single U+2026 ellipsis) and update both en/zh-Hans entries in MuseAmp/Resources/Localizable.xcstrings in the same change, per the Localization Rules.

<details><summary>验证记录</summary>

Verified: PlaybackMenuProvider.swift:167 uses ASCII "Play At..." while every other ellipsized menu title in Backend/MenuProviders/ uses U+2026 ("Merge Into…" at PlaylistContextMenuProvider.swift:107, "New Playlist…" at AddToPlaylistMenuProvider.swift:24 and 72), and the ASCII key is mirrored in MuseAmp/Resources/Localizable.xcstrings:4070. The repo at large mixes both styles, but the ASCII form appears almost exclusively in progress/status messages, not menu titles; for menu titles the typographic ellipsis is the dominant local convention, and AGENTS.md itself writes "New Playlist…" with U+2026 (line 87), implicitly endorsing that style. The suggested fix is small, matches surrounding code, complies with Localization Rules (update xcstrings in same change), and matches Apple HIG for menus. Purely cosmetic, so severity stays low.

</details>

### [LOW] asyncMapLatest doc comment is attached to the wrong declaration

`MuseAmp/Backend/Supplement/ConcurrencyHelpers.swift:32` · file-organization

**问题**: The doc comment beginning "Maps each upstream value through an async closure..." (lines 32-41) describes the asyncMapLatest publisher operator, but it is attached to `private enum AsyncMapLatestState` (line 42). Quick Help / jump-to-definition on asyncMapLatest (line 48) shows no documentation, while the private state enum shows the operator's docs.

**建议**: Move the /// block to immediately precede `func asyncMapLatest` inside the Publisher extension, leaving at most a one-line comment on AsyncMapLatestState if needed.

<details><summary>验证记录</summary>

Verified in ConcurrencyHelpers.swift: the doc block at lines 32-41 describes the asyncMapLatest operator (map + switchToLatest, cancel-in-flight semantics) but is attached to `private enum AsyncMapLatestState` at line 42; `func asyncMapLatest` at line 48 carries no documentation. Every other doc comment in the file is correctly attached to its declaration, so the misplacement violates rather than follows local convention. AGENTS.md does not endorse the pattern ("keep comments rare" is the only comment rule). The suggested fix is minimal, matches file style, and genuinely improves Quick Help/jump-to-definition clarity. Severity remains low — cosmetic, since the text is still visually adjacent to the implementation in source.

</details>

### [LOW] Optional Bool forceEnabled is a hidden tri-state behavior flag

`MuseAmp/Backend/Supplement/TrackTitleSanitizer.swift:41` · function-design

**问题**: `sanitize(_ title: String, forceEnabled: Bool? = nil)` encodes three behaviors in one parameter: nil = consult AppPreferences.isCleanSongTitleEnabled, true = always sanitize, false = never sanitize (line 42: `guard forceEnabled ?? AppPreferences.isCleanSongTitleEnabled`). Only one call site uses it (NowPlayingContentMapper.swift:34 with `forceEnabled: true`); `forceEnabled: false` reads like "force-disable" but actually just returns the title untouched. Boolean behavior flags — and especially Optional ones — push the branch decision into every caller's head.

**建议**: Split into two entry points: keep `sanitize(_ title: String)` honoring the preference, and add `sanitizeIgnoringPreference(_ title: String)` (or `sanitize(_:enabled: Bool)` with the preference read at the call site) for the single forced caller; drop the Bool? parameter.

<details><summary>验证记录</summary>

Verified: TrackTitleSanitizer.swift:41-44 has `sanitize(_:forceEnabled: Bool? = nil)` guarding on `forceEnabled ?? AppPreferences.isCleanSongTitleEnabled` — a real tri-state Optional Bool behavior flag. Only two call sites exist: Extension+String.swift:12 (nil) and NowPlayingContentMapper.swift:34 (`forceEnabled: true`); the mapper already resolves enablement via an injected `cleanTitleEnabled` and writes `cleanTitleEnabled ? sanitize(track.title, forceEnabled: true) : track.title`, which the suggested `sanitize(_:enabled:)` shape would collapse into one clearer call. AGENTS.md does not endorse Optional Bool parameters and its Property Rules ("avoid unnecessary optionals; prefer meaningful defaults") point the same direction as the fix. A similar `animatingDifferences: Bool? = nil` idiom exists 8x in Interface/Browse, but that is a different module with different semantics and is not the convention of Backend/Supplement, where this is the sole occurrence — so no convention endorsement. Minor flaw in the finding: its claim that `forceEnabled: false` "reads like force-disable but actually just returns the title untouched" is muddled (returning untouched IS force-disabling), but the core complaint stands. Severity stays low: no caller passes `false` today, so this is cosmetic clarity/testability, not an active bug breeder.

</details>

### [LOW] try? saveLyrics swallows the cache-write error without logging

`MuseAmp/Backend/Sync/SyncPreparedTrackBuilder+Export.swift:229` · error-boundaries

**问题**: `try? lyricsCacheStore?.saveLyrics(normalized, for: trackID)` (line 229) discards any persistence failure with no AppLog trace, violating the AGENTS.md rule that every swallowed try? must log via AppLog.error or AppLog.warning. The neighboring `try? await DownloadArtworkProcessor.cachedArtworkData` calls (lines 117, 171) have the same shape — the following verbose log records bytes=0 but never the failure reason.

**建议**: Wrap the save in do/catch and AppLog.warning the error (file I/O failure in a persistence store), and add an error-path log for the artwork try? sites, e.g. capture the thrown error and include it in the existing verbose log line.

<details><summary>验证记录</summary>

Confirmed: line 229 `try? lyricsCacheStore?.saveLyrics(...)` swallows a throwing file-I/O call from LyricsCacheStore with no AppLog.error/warning; AGENTS.md line 203 explicitly forbids this ("Every catch block or try? that silently swallows an error must log via AppLog.error or AppLog.warning"), and the Logging Rules separately require persistence-store file I/O failures to log via AppLog.error. The surrounding file already follows the logging convention (AppLog.warning/error in its other catch blocks), so the suggested do/catch fix matches local style rather than deviating from it. The artwork try? sites (lines 117/171) likewise log only bytes=0 at verbose with no failure reason. Severity remains low: a failed lyrics cache write merely causes a refetch later and does not mislead readers about control flow.

</details>

### [LOW] copyExportSource: no-op catch-rethrow wrapper and unlogged link fallback

`MuseAmp/Backend/Sync/SyncPreparedTrackBuilder.swift:162` · error-boundaries

**问题**: The inner `do { try fileManager.copyItem(at:to:) } catch { throw error }` (lines 165-169) is a no-op wrapper equivalent to a bare `try`. Additionally, the linkItem failure that triggers the copy fallback (line 164) is swallowed with no AppLog trace, while AGENTS.md requires every silently swallowed error to log before continuing; when hard-linking degrades to copying (slower, doubles disk usage for big batches) there is no diagnostic record of why.

**建议**: Log the link failure at verbose/warning (e.g. AppLog.verbose(self, "copyExportSource link failed, falling back to copy error=...")) and replace the inner do/catch with a direct `try fileManager.copyItem(at: sourceURL, to: destinationURL)`.

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/Sync/SyncPreparedTrackBuilder.swift:160-171. The inner `do { try fileManager.copyItem } catch { throw error }` is a literal no-op wrapper, and the outer catch swallows the linkItem failure with no AppLog trace before falling back to copy. AGENTS.md Logging Rules explicitly require every silently swallowed catch to log via AppLog before continuing, so the flagged pattern violates the documented convention rather than following it. The dominant local convention also contradicts the pattern: every other catch in this very file (lines 154, 179, 190) logs via AppLog. The suggested fix (log link failure at verbose/warning, use a direct `try copyItem`) improves clarity and aligns the code with both AGENTS.md and the surrounding module. Severity remains low: no active bug, just a missing diagnostic breadcrumb and dead ceremony.

</details>

### [LOW] orderedUnique() duplicated across files plus three inline hand-rolled copies of the same dedup pattern

`MuseAmp/Backend/Sync/SyncProtocol.swift:359` · seams-duplication

**问题**: The identical `private nonisolated extension Array where Element: Hashable { func orderedUnique() }` exists in SyncProtocol.swift (lines 359-364) and TVPlaylistSessionStore.swift (lines 200-205). The same order-preserving dedup is additionally hand-rolled inline with a `seen` Set + append loop in SyncServer.preferredEndpoints (lines 691-748), SyncTransferSession.resolveEndpoints (lines 222-240), and SyncBonjourBrowser.makeEndpoints (lines 144-167) — five implementations of one behavior inside one subdomain.

**建议**: Hoist a single internal `orderedUnique()` (or use SwifterSwift's withoutDuplicates() if available to both targets) into one shared Sync support file, add the matching MuseAmpTV/Backend/Sync symlink per AGENTS.md, delete the two private copies, and replace the three inline seen-set loops with `(candidates).orderedUnique()`.

<details><summary>验证记录</summary>

Verified: identical private orderedUnique() extensions exist in both SyncProtocol.swift (359-364) and TVPlaylistSessionStore.swift (200-205), and three inline seen-set dedup loops exist at the cited locations in SyncServer.swift, SyncTransferSession.swift, and SyncBonjourBrowser.swift — five implementations of order-preserving dedup in one subdomain. AGENTS.md does not endorse this; it explicitly prefers shared helpers over per-file ad-hoc copies (ConcurrencyHelpers rule) and lists SwifterSwift withoutDuplicates(). All five files are already symlinked into MuseAmpTV/Backend/Sync, so the proposed fix (internal helper in a shared/symlinked Sync file) is consistent with repo conventions. Severity lowered to low: copies have not drifted, the function is trivial and stable, and two of the three inline loops interleave dedup with incremental candidate generation from C APIs where an inline seen-set is a defensible idiom — this is real but cosmetic-clarity duplication, not actively misleading.

</details>

### [LOW] Error discrimination via equality on a localized user-facing string

`MuseAmp/Backend/Sync/SyncServer.swift:246` · state-modeling

**问题**: ReceiveOutcome.error carries an untyped (statusCode: Int, body: String) pair. The receive loop then detects the oversized-request case by string-comparing the localized message: `if statusCode == HTTPStatus.badRequest.rawValue, body == Self.oversizedRequestMessage` (lines 246-248), and re-derives the enum it already had with `HTTPStatus(rawValue: statusCode) ?? .internalServerError` (line 252). The failure reason is a hidden state machine encoded in a localized String(localized:) value (line 32) — stringly-typed control flow that breaks silently if the copy or its localization pipeline ever changes the value identity.

**建议**: Change the case to carry typed state, e.g. `case rejected(status: HTTPStatus, reason: RequestFailure)` with `enum RequestFailure { case oversized, malformed }`. Derive the response body text from the reason at send time and branch the warning log on `reason == .oversized` instead of comparing message strings.

<details><summary>验证记录</summary>

The cited code exists as described: ReceiveOutcome.error carries (Int, String) at SyncServer.swift:28, the receive loop at lines 245-250 discriminates the oversized case by string-comparing the localized constant, and line 252 reconstructs HTTPStatus from a rawValue that originated as HTTPStatus.badRequest.rawValue in _receiveOutcome (lines 270-275). Tests (MuseAmpTests/Sync/SyncServerTests.swift:14) also match on the string. This is genuine stringly-typed control flow, and the suggested typed-reason case fits repo style (AGENTS.md favors typed value modeling; HTTPStatus is only private-extension-scoped, easily moved). However, the claimed failure mode is overstated: both producer and consumer compare the SAME static constant, so copy/localization changes move both sides together and cannot silently break value identity; the only gated behavior is one warning log line, with the response path identical either way. So the finding is real as a clarity/state-modeling smell, but severity is low (cosmetic confusion for readers, no realistic bug path), not medium. AGENTS.md does not endorse the pattern.

</details>

### [LOW] Unauthorized-guard block duplicated across /manifest and /track routes

`MuseAmp/Backend/Sync/SyncServer.swift:344` · seams-duplication

**问题**: Lines 344-351 and 364-371 are identical eight-line blocks: `guard let token = authorizedToken(for: request) else { sendPlainResponse(status: .unauthorized, body: String(localized: "Unauthorized."), on: connection); return }`. Two protected routes already exist; each future protected route will clone the block again, including the localized string literal.

**建议**: Extract a helper, e.g. `func requireAuthorizedToken(for request: HTTPRequest, on connection: NWConnection) -> String?` that sends the 401 itself and returns nil, then `guard let token = requireAuthorizedToken(...) else { return }` at both call sites.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Backend/Sync/SyncServer.swift inside `process(_:on:)` (lines ~344-351 for the GET /manifest case and ~364-371 for the GET /track/ case): both blocks are byte-identical eight-line guards calling `authorizedToken(for:)` then `sendPlainResponse(status: .unauthorized, body: String(localized: "Unauthorized."), on: connection)` and returning. The duplication described by the finding genuinely exists, including the repeated localized string literal. AGENTS.md (CLAUDE.md is a symlink to it) contains nothing endorsing this duplication; on the contrary the file itself already follows a small-helper convention (`authorizedToken(for:)`, `sendPlainResponse`, `sendJSONResponse`, `responseHeader`), so extracting a `requireAuthorizedToken(for:on:) -> String?` helper that sends the 401 and returns nil would read exactly like the surrounding code and would not violate any repo rule. Mitigating factors keeping severity low: only two occurrences exist today, both are within one 50-line switch and trivially scannable, and the duplication cannot drift into a bug easily since both call the same shared `authorizedToken` and `sendPlainResponse` primitives — only the literal and status line are cloned. This is a cosmetic clarity/duplication issue, accurately categorized, with a fix that fits local style; real but low severity.

</details>

### [LOW] Pass-through receiveOutcome wrapper over underscore-named _receiveOutcome

`MuseAmp/Backend/Sync/SyncServer.swift:35` · naming

**问题**: The public static `receiveOutcome(buffer:chunk:isComplete:)` (lines 35-41) does nothing but forward to `_receiveOutcome` (line 260), which lives in the private extension. The underscore prefix is not a Swift naming convention used elsewhere in this repo, and the indirection exists only because the implementation was placed in the private extension while tests (MuseAmpTests/Sync/SyncServerTests.swift:11,34) need access. Readers hit two symbols for one behavior and must check whether the wrapper adds anything.

**建议**: Move the implementation into the main type body under the single name receiveOutcome (internal access is sufficient for the test target) and delete the _receiveOutcome duplicate; update the one internal caller at line 238.

<details><summary>验证记录</summary>

Confirmed: SyncServer.receiveOutcome (lines 35-41) forwards verbatim to _receiveOutcome (line 260) with identical signature and no added behavior; the internal caller at line 238 even bypasses the wrapper and calls _receiveOutcome directly, so the file has two symbols for one behavior. The wrapper exists only because the implementation sits in a private extension while tests (which use @testable import MuseAmp) need access — internal access in the main type body would suffice. Attempted refutation via repo convention failed: the only other underscore-prefixed functions (DownloadArtworkProcessor._withOverallTimeout/_export) are a different, justified pattern where the public wrapper bridges a completion-handler core to async and genuinely adds behavior; they do not endorse signature-identical pass-throughs. AGENTS.md contains no endorsement of underscore naming or pass-through wrappers, and the suggested fix (move implementation into the type body as internal receiveOutcome, delete the duplicate, update the line-238 caller) is feasible — private-extension helpers like parseRequest remain file-visible — and reads consistently with the rest of the module. Severity stays low: cosmetic clarity issue, not actively misleading.

</details>

### [LOW] connectionIDs names the keys, not the values it stores

`MuseAmp/Backend/Sync/SyncServer.swift:52` · naming

**问题**: `private var connectionIDs: [ObjectIdentifier: NWConnection]` stores live connections keyed by identifier, but the name says it stores IDs. The same file and subdomain consistently use value-by-key naming: receiverNamesByToken (line 140), servicesByName / devicesByName (SyncBonjourBrowser.swift lines 16-17), filesByTrackID (PreparedTransferBatch). Iterations like `for connection in connectionIDs.values` (line 129) read wrong.

**建议**: Rename to connectionsByID to match the established valueByKey convention.

<details><summary>验证记录</summary>

Confirmed: SyncServer.swift line 52 declares `private var connectionIDs: [ObjectIdentifier: NWConnection]`, whose values are live NWConnection objects, not IDs; usages like `for connection in connectionIDs.values` (line 129) and `connectionIDs[identifier] = connection` (line 202) read inconsistently with the name. The Backend/Sync subdomain uses valueByKey naming in five other places (receiverNamesByToken in the same file line 140, servicesByName/devicesByName in SyncBonjourBrowser.swift lines 16-17, filesByTrackID/companionFilesByTrackID in SyncPreparedTrackBuilder.swift lines 14-15), making connectionIDs the lone outlier. AGENTS.md contains no rule endorsing the flagged pattern; renaming to connectionsByID moves the code toward the dominant local convention rather than away from it. The issue is real but cosmetic: it is a private property with few, co-located usage sites and the type annotation disambiguates immediately, so severity remains low.

</details>

### [LOW] sendResponse captures self strongly, diverging from the file's [weak self] completion convention

`MuseAmp/Backend/Sync/SyncServer.swift:663` · mechanical-consistency

**问题**: Every other Network.framework completion in this file uses [weak self] (receive at line 226, header send at line 468, chunk send at line 540, state handler at line 204), but sendResponse's nested send completions (lines 663-676) capture self implicitly and strongly just to call AppLog.error. The inconsistency makes a reader stop to work out whether the strong capture is intentional lifetime extension or an oversight.

**建议**: Use `[weak self]` with the existing `AppLog.error(self ?? "SyncServer", ...)` fallback pattern already used at lines 470 and 542.

<details><summary>验证记录</summary>

Confirmed in SyncServer.swift: sendResponse (lines 658-677) strongly captures self in both nested NWConnection send completions solely for AppLog.error, while every other Network.framework completion in the file uses [weak self] (lines 80, 86, 204, 226, 468, 540), and the exact suggested fallback `AppLog.error(self ?? "SyncServer", ...)` already appears at lines 110, 470, and 542 in functionally identical send completions. AGENTS.md only mandates [weak self] for Combine .sink closures and does not endorse the strong capture; the dominant local convention is the weak pattern, so the fix aligns the code with the rest of the repo rather than diverging from it. The strong capture is functionally benign (long-lived server, one-shot completion, no retain cycle), so this is a cosmetic consistency issue: severity stays low.

</details>

### [LOW] Route dispatch mixes exact-match switch with nested prefix matching buried in default

`MuseAmp/Backend/Sync/SyncServer.swift:360` · abstraction-levels

**问题**: process(_:on:) (lines 336-385) routes POST /auth and GET /manifest via switch cases, but the GET /track/{id} route lives inside the `default:` branch as a nested if (lines 361-377) with the 404 fallback as its else. One of three routes plus the not-found path are at a different abstraction level and indentation than the others, so the route table cannot be read at a glance.

**建议**: Parse the request into a small Route enum first (`case auth, manifest, track(String), notFound`) — the /track prefix extraction moves into the parser — then dispatch with one flat switch over Route.

<details><summary>验证记录</summary>

Verified at MuseAmp/Backend/Sync/SyncServer.swift lines 336-385: POST /auth and GET /manifest are flat switch cases, but GET /track/{id} is a nested if inside default: with the 404 as its else, exactly as the finding describes. No repository convention endorses this — it is the only HTTP route dispatch in the codebase, and AGENTS.md's style rules ('early returns and guard to reduce nesting') favor flattening. The asymmetry is not forced by Swift: a `case ("GET", let path) where path.hasPrefix("/track/"):` (or the suggested Route enum) keeps all routes at one level and leaves default: as the pure not-found path, genuinely improving scanability of the route table without violating any repo rule. The function is short and not misleading, so impact is cosmetic — severity stays low. The Route enum suggestion is slightly heavier than necessary for three routes, but the underlying abstraction-level complaint is accurate and cheaply fixable.

</details>

### [LOW] FileManager injected and stored as a property against explicit repo rule

`MuseAmp/Backend/Sync/SyncTransferSession.swift:28` · repository-conventions

**问题**: AGENTS.md Dependency Rules state: "Use FileManager.default directly for standard file operations. Do not pass FileManager as a parameter or store it as a property." SyncTransferSession stores `private let fileManager: FileManager` (line 28), takes `fileManager: FileManager = .default` in init (line 48), and forwards it into SyncPreparedTrackBuilder (line 60), which also stores it (`let fileManager: FileManager`, SyncPreparedTrackBuilder.swift lines 34/40) and uses it in makeCleanupDirectory/copyExportSource/cleanup. No call site in the app, TV target, or MuseAmpTests ever passes a non-default instance, so the seam is pure speculative variability that directly violates the convention.

**建议**: Delete the fileManager stored properties and init parameters from SyncTransferSession and SyncPreparedTrackBuilder and call FileManager.default directly at the usage sites (prepareReceiverDirectoryURL, cleanupReceiverDownloads, makeCleanupDirectory, copyExportSource, cleanupPreparedFile, cleanup).

<details><summary>验证记录</summary>

Verified: SyncTransferSession.swift stores `private let fileManager: FileManager` (line 28), accepts `fileManager: FileManager = .default` in init (line 48), and forwards it to SyncPreparedTrackBuilder (line 60), which also stores and uses it. AGENTS.md line 111 explicitly forbids exactly this: "Use FileManager.default directly for standard file operations. Do not pass FileManager as a parameter or store it as a property." No call site in the app target (AppEnvironment+Transfer.swift), TV target (TVAppContext.swift), or tests (SyncTransferSessionTests.swift, SyncPreparedTrackBuilderTests.swift) ever passes a non-default instance, so the injection seam is dead weight. The dominant repo convention matches the rule (e.g., PlaylistCoverArtworkCache uses FileManager.default directly); the suggested fix would make the code MORE consistent with the repo, not less. Severity adjusted to low: the seam cannot alter behavior (default always used) and is a cosmetic convention violation rather than something that has bred or will breed bugs.

</details>

## [clarity] interface-browse (24)

### [HIGH] "Sort by Recently Modified" actually sorts albums by title

`MuseAmp/Interface/Browse/Albums/SongLibraryViewController.swift:395` · naming

**问题**: SortOption.recentlyModified is titled "Sort by Recently Modified" (line 42), but its applySort branch (lines 395-398) sorts by `albumTitle.localizedCaseInsensitiveCompare` — byte-identical to the `.album` sort minus the artist tiebreak. AlbumGroup (MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Models/AlbumGroup.swift) carries no modification date, so the case silently degrades to an alphabetical sort while the menu still shows the option as a distinct, selectable state. SongsViewController honors the same option name with a real `fileModifiedAt` sort (SongsViewController.swift:382), so the two screens disagree on what the identically-named option means.

**建议**: Either surface a real recency value on AlbumGroup (e.g. max track fileModifiedAt aggregated in the DB query) and sort by it, or remove `.recentlyModified` from SongLibraryViewController.SortOption until the data exists. At minimum add a comment-free honest implementation; do not keep a menu option whose behavior contradicts its name.

<details><summary>验证记录</summary>

Verified directly in source. SongLibraryViewController.swift declares SortOption.recentlyModified titled "Sort by Recently Modified" (lines 31/41-42, clock icon at line 56), but applySort() at line 395 sorts by albumTitle.localizedCaseInsensitiveCompare — a plain alphabetical sort identical to .album minus the artist tiebreak. AlbumGroup (MuseAmpDatabaseKit/Models/AlbumGroup.swift) confirmed to carry no date field of any kind, so the degradation is silent and structural. SongsViewController.swift line 381-382 implements the same-named option honestly via fileModifiedAt descending, so the two screens contradict each other for an identically labeled menu item, and the chosen option is persisted via AppPreferences (libraryAlbumSortOptionKey), making it a durable user-visible state that does not do what it says. AGENTS.md contains no endorsement of this pattern; the dominant convention across SongsViewController and PlaylistViewController is a genuine recency sort, making this case the deviation. The suggested fixes (aggregate max fileModifiedAt in the DB query, or drop the case) are consistent with repo placement rules. Severity stays high: the mismatch is not merely a misleading name in code — it is an already-shipped behavioral bug where a selectable menu option silently duplicates another sort.

</details>

### [MEDIUM] loadTracks repeats the failure path four times and force-unwraps after a boolean check

`MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift:531` · function-design

**问题**: Inside `loadTracks()` the block `if !hasExistingTracks { isLoadingTracks = false; applySnapshot() }` appears four times (lines 552-556, 562-565, 576-580, 591-594). Line 532 computes `hasExistingTracks` as `album.relationships?.tracks?.data.isEmpty == false` and line 536 then force-unwraps `album.relationships!.tracks!.data` — the optional chain is checked via a Bool and re-unwrapped with `!` instead of being bound once. The function also interleaves three phases (local-tracks fast path, song->album resolution, album fetch) at ~70 lines.

**建议**: Bind the optional once (`if let existing = album.relationships?.tracks?.data, !existing.isEmpty { ... setTracks(existing) }`) eliminating both force unwraps, and extract a `finishLoadingWithoutTracks()` helper for the repeated failure block; optionally split the async body into `resolveAlbumFromPendingSong()` and `fetchFullAlbum()`.

<details><summary>验证记录</summary>

All three claims verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift: line 532 computes hasExistingTracks via optional-chain Bool, line 536 force-unwraps album.relationships!.tracks!.data (the only such force-unwrap in the Browse module — not a convention); the failure block `if !hasExistingTracks { isLoadingTracks = false; applySnapshot() }` is duplicated verbatim at lines 552-555, 562-565, 576-579, 591-594; the function spans ~67 lines mixing fast path, song->album resolution, and album fetch. AGENTS.md endorses the opposite pattern ('Use early returns and guard', 'Avoid unnecessary optionals'), so the suggested if-let binding plus a finishLoadingWithoutTracks() helper matches repo style. The unwrap is genuinely fragile because `album` is reassigned later in the same function, and the 4x duplication already shows slight divergence (log ordering differs across sites).

</details>

### [MEDIUM] Artwork URL resolved via Artwork.imageURL instead of apiClient.mediaURL

`MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift:285` · repository-conventions

**问题**: `exportItem(for:)` builds the artwork URL with `track.attributes.artwork?.imageURL(width: 600, height: 600)` (line 285). This is the only place in the app target that calls `imageURL(width:height:)` directly; every other site, including line 376 of this same file, resolves template URLs through `apiClient.mediaURL(from:width:height:)` as the AGENTS Artwork URL Rules require ("Always resolve via apiClient.mediaURL(from:width:height:)").

**建议**: Replace with `environment.apiClient.mediaURL(from: track.attributes.artwork?.url, width: 600, height: 600)` to keep one canonical resolution path.

<details><summary>验证记录</summary>

Verified: line 285 of AlbumDetailViewController.swift calls track.attributes.artwork?.imageURL(width:600,height:600), the only such direct call in the MuseAmp/MuseAmpTV app targets; line 376 of the same file uses environment.apiClient.mediaURL(from:width:height:). AGENTS.md Artwork URL Rules (lines 257-261) explicitly require resolving via apiClient.mediaURL and forbid constructing artwork URLs without going through APIClient.resolveMediaURL, so the flagged pattern violates the documented convention. The divergence is also behavioral: Artwork.imageURL only substitutes {w}/{h} and does URL(string:), while APIClient.mediaURL additionally handles protocol-relative "//" URLs and resolves scheme-less URLs against baseURL — so exported song artwork can break for URL forms the rest of the app handles. environment.apiClient is already in scope in this controller, so the suggested fix matches surrounding style exactly.

</details>

### [MEDIUM] ShineBarView.swift contains no ShineBarView — only a dead duplicate badge factory

`MuseAmp/Interface/Browse/AlbumDetail/ShineBarView.swift:12` · file-organization

**问题**: The file declares a single global free function `makeAlbumBadgeView(text:icon:)` and no `ShineBarView` type (the real shimmer view lives in Interface/Collections/SkeletonShineBarView.swift). A repo-wide grep finds zero callers of `makeAlbumBadgeView`, and its body is a copy of the private `makeAudioTraitBadge` in Interface/Common/DetailFooterCell.swift:90-115 (same 12pt icon, 11pt semibold label, 3/8 layout margins, 0.1-alpha tint background, radius 10). Dead code under a misleading filename.

**建议**: Delete ShineBarView.swift entirely (the function is unused). If album badges are needed later, reuse/expose the existing makeAudioTraitBadge from DetailFooterCell instead of resurrecting a copy.

<details><summary>验证记录</summary>

Verified directly: ShineBarView.swift declares no ShineBarView type, only the global free function makeAlbumBadgeView(text:icon:). Repo-wide grep across Swift sources, the pbxproj, and interface files finds zero callers — the function is dead code present since the initial commit. Its body duplicates the private makeAudioTraitBadge in Interface/Common/DetailFooterCell.swift (identical 12pt icon, 11pt semibold label, spacing 3, 3/8 margins, 0.1-alpha tint background, radius 10), differing only in Then syntax. The filename is actively misleading because the real shimmer component is SkeletonShineBarView in Interface/Collections/, so a maintainer searching for the shine bar lands on an unrelated dead badge factory. AGENTS.md does not endorse this pattern; its file-naming and placement rules point toward deletion. The suggested fix (delete the file) is safe and convention-consistent. Severity medium is justified: misleading filename plus silent duplicate invites divergent edits (someone could modify one badge factory and not the other, or resurrect the dead copy).

</details>

### [MEDIUM] Search-highlight font literals silently coupled to AmSongCell's fonts

`MuseAmp/Interface/Browse/Albums/SongLibraryViewController.swift:360` · named-constants

**问题**: `configureLibrarySearchResultCell` passes `.systemFont(ofSize: 16)` / `.systemFont(ofSize: 13)` to SearchHighlightHelper (lines 360, 366) so the attributed strings match AmSongCell's private titleLabel/subtitleLabel fonts (AmSongCell.swift lines 25, 32). The same 16/13 literals are re-typed in Interface/Playlist/PlaylistSearchCell.swift (lines 37, 48) and Interface/Search/SearchViewController.swift. If the cell font changes, every highlight call site drifts and the bold-highlight rendering subtly mismatches the plain text.

**建议**: Expose the fonts where they are owned, e.g. `static let titleFont` / `static let subtitleFont` on AmSongCell (or in InterfaceStyle), and reference those constants from all SearchHighlightHelper call sites.

<details><summary>验证记录</summary>

Verified: SongLibraryViewController.swift lines 357-368 pass .systemFont(ofSize: 16)/.systemFont(ofSize: 13) to SearchHighlightHelper so attributed text matches AmSongCell's private titleLabel/subtitleLabel fonts (AmSongCell.swift lines 25/32, exactly 16 and 13). The same literals are re-typed in PlaylistSearchCell.swift (lines 37, 47, 52) and SearchViewController.swift (lines 183, 192, 216-224) — 7+ call sites across 3 files coupled to private label fonts with no named link between them. AGENTS.md does not endorse the pattern; the repo already uses static style namespaces (InterfaceStyle.Insets/Spacing, AmSongCell's private Layout enum), so the suggested static titleFont/subtitleFont constants fit existing conventions rather than violating them. Inline fonts inside a cell's own label setup are normal repo style, but cross-file duplication that must silently stay in sync with another type's private properties is not an endorsed convention. Severity medium: the invariant is invisible per-file, and a future cell font change would silently mismatch highlighted vs plain rows.

</details>

### [MEDIUM] Optional-environment dependency lattice is dead generality

`MuseAmp/Interface/Browse/Downloads/DownloadsViewController.swift:69` · state-modeling

**问题**: The init accepts `playlistStore: PlaylistStore? = nil` AND `environment: AppEnvironment? = nil`, resolving `playlistStore ?? environment?.playlistStore` (line 76), and the optional environment cascades into five more optionals: `playlistMenuProvider`, `availablePlaylists` closure (lines 52-53), `albumNavigationHelper` (line 56), `lyricsReloadPresenter` (line 60) and `showInAlbum: environment == nil ? nil : ...` (line 419). Both real call sites pass a non-nil environment (Interface/Root/MainController.swift:373 and Interface/Settings/SettingsViewController+Actions.swift:55-59, the latter also redundantly passing playlistStore), so every nil branch is unreachable speculative wiring.

**建议**: Make `environment: AppEnvironment` required, derive playlistStore from it, drop the separate parameter, and make the five derived dependencies non-optional lazy properties — matching how SongsViewController/SongLibraryViewController wire the same providers.

<details><summary>验证记录</summary>

All factual claims verified. Init (lines 69-88) takes both `playlistStore: PlaylistStore? = nil` and `environment: AppEnvironment? = nil`; the optional environment cascades into five derived optionals (playlistMenuProvider, availablePlaylists at 52-53/77-86, albumNavigationHelper at 56, lyricsReloadPresenter at 60, showInAlbum nil-ternary at 419) plus optional chaining at 367/485. Only two call sites exist (MainController.swift:373, SettingsViewController+Actions.swift:55-59) and both pass a non-nil environment — the Settings one also redundantly passes playlistStore, showing the dual-parameter design has already confused a caller. No tvOS or other usage; all nil branches are unreachable dead generality. AGENTS.md explicitly says to avoid unnecessary optionals and to thread shared dependencies through AppEnvironment, and every sibling browse controller (SongsViewController:145, SongLibraryViewController:137, AlbumDetailViewController:63/72/88) requires a non-optional `environment: AppEnvironment`. DownloadsViewController is the lone outlier, so the suggested fix matches both AGENTS.md and the dominant module convention. conventionEndorsed=false. Severity medium is honest: the pattern actively misleads readers into preserving dead branches and already bred a redundant call site, but does not block safe modification.

</details>

### [MEDIUM] createPlaylistFromSelection and buildEditingMenu duplicated across Songs and Albums controllers

`MuseAmp/Interface/Browse/Songs/SongsViewController+Actions.swift:73` · seams-duplication

**问题**: `createPlaylistFromSelection` (lines 73-94) duplicates SongLibraryViewController+Actions.swift lines 221-242 except for the prefilled text: same AlertInputViewController titles/placeholder, same trim+guard+AppLog.warning, same createPlaylist+addSong loop. `buildEditingMenu` (lines 100-162) likewise mirrors SongLibraryViewController+Actions.swift lines 252-329 (same add-to-playlist gating, New Playlist / Export Selected / Copy submenu / Delete Selected structure and section assembly).

**建议**: Move the name-prompt-then-create-playlist flow into a shared presenter or into AddToPlaylistMenuProvider (which already owns playlist UI), parameterized by an entries provider and optional default name; build the shared editing-menu skeleton in one menu-builder helper that takes the per-screen copy actions.

<details><summary>验证记录</summary>

Confirmed. createPlaylistFromSelection in SongsViewController+Actions.swift:73-94 is verbatim-identical to SongLibraryViewController+Actions.swift:221-242 except the prefilled text, and a third near-copy exists at PlaylistViewController+Editing.swift:85-107 that has already diverged (it calls reloadPlaylists() after the add loop; the other two do not) — concrete evidence the duplication breeds inconsistency. buildEditingMenu's skeleton (addToPlaylist nil-gating, New Playlist / Export / Copy submenu / Delete actions, identical sections-assembly with insert-at-0) is repeated in all three controllers with only per-screen copy/export actions differing. AGENTS.md does not endorse this duplication; it actively supports the suggested fix: shared UI used by multiple features belongs in Interface/Common, menu providers belong in Backend/MenuProviders injected via AppEnvironment (an AddToPlaylistMenuProvider already exists and is injected), and the presenter-enum pattern (ConfirmationAlertPresenter, SongExportPresenter) is established repo convention. The fix would read consistently with the surrounding codebase.

</details>

### [MEDIUM] Song-tap playback policy reimplemented inline in two controllers

`MuseAmp/Interface/Browse/Songs/SongsViewController+Table.swift:100` · seams-duplication

**问题**: `playTrack(_:)` (lines 100-126) and AlbumDetailViewController+Table.swift `playTrack(at:)` (lines 84-105) both hand-roll the AGENTS "Playback Interaction Rules" policy: check `latestSnapshot.state == .playing || .buffering`, rewind via `seek(to: 0)` when the tapped track is current, otherwise `playNext` and switch on `.alreadyQueued` -> `next()` / `.queued` -> toast. The policy is duplicated logic-for-logic at two call sites (the only two that switch on `alreadyQueued` outside PlaybackFeedbackPresenter), so a future rule change must be found and edited in both.

**建议**: Add one canonical entry point, e.g. `PlaybackController.handleTrackTap(track:in:source:)` (Backend/Playback owns playback state per AGENTS) that encodes the tap policy and returns/presents the feedback; both table delegates call it.

<details><summary>验证记录</summary>

Verified: SongsViewController+Table.swift:100-126 and AlbumDetailViewController+Table.swift:75-106 contain line-for-line equivalent implementations of the AGENTS "Playback Interaction Rules" song-tap policy (playing/buffering check, seek(to:0) rewind for current track, playNext + switch on .alreadyQueued -> next() / .queued -> PlaybackFeedbackPresenter toast). Grep confirms these are the only two UI sites switching on alreadyQueued and the only UI sites checking latestSnapshot.state == .playing || .buffering. AGENTS.md documents the tap policy but does not endorse per-controller inline copies; the repo's dominant convention is centralization (PlaybackController owns state, PlaybackMenuProvider centralizes menu playback actions with injected track/queue/source closures, PlaybackFeedbackPresenter centralizes toasts), so the suggested canonical entry point matches local style. A third tap site (PlaylistDetailViewController.playSong(at:)) already behaves differently, showing real drift risk. Medium severity: duplicated behavioral policy that a future rule change must edit in both places, with silent UX inconsistency if one is missed; not yet a demonstrated bug.

</details>

### [MEDIUM] Debounced local search implemented twice with divergent guards

`MuseAmp/Interface/Browse/Songs/SongsViewController+Table.swift:230` · seams-duplication

**问题**: SongsViewController's performSearch (lines 230-254) and SongLibraryViewController+Search.swift performSearch (lines 31-63) implement the same 300ms-debounced DB search with gratuitous differences: Songs guards staleness only via `Task.isCancelled` while SongLibrary re-checks `currentQuery == query`; Songs uses `try? await Task.sleep` then a separate isCancelled check while SongLibrary uses `do/catch { return }`; Songs propagates the search error from Task.detached and logs with `self`, SongLibrary logs inside the detached closure with a string tag; results land in `searchTracksByID` vs reused `tracksByID`. Neither follows the AGENTS Search Rule of separate `debounceTask`/`searchTask` properties. The drift makes it impossible to tell which differences are intentional.

**建议**: Pick one canonical shape (query-equality recheck plus the documented debounceTask/searchTask split) and apply it to both controllers, or extract a small generic `DebouncedLibrarySearch` helper in Interface/Browse/Support that both reuse.

<details><summary>验证记录</summary>

Verified against both files. The duplication and drift are real: /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/Browse/Songs/SongsViewController+Table.swift (performSearch, lines 230-254) and /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/Browse/Albums/SongLibraryViewController+Search.swift (performSearch, lines 31-63 — note the file is under Browse/Albums/, not Browse/Songs/ as the finding implied) both implement the identical 300ms-debounced `db.searchTracks(query:)` flow with divergent mechanics exactly as described: (1) staleness guard via `Task.isCancelled` only vs `currentQuery == query` recheck; (2) `try? await Task.sleep` + separate isCancelled guard vs `do/catch { return }`; (3) error handling that actually diverges behaviorally — Songs aborts and keeps prior results on a DB error, SongLibrary swallows the error inside the detached closure and applies an EMPTY search snapshot — plus `AppLog.error(self, ...)` vs a hardcoded string tag. A maintainer cannot tell which of these differences is intentional, and the divergent error behavior is the kind of drift that breeds one-sided fixes. Convention check: AGENTS.md Search Rules (lines 179-180) explicitly mandate the split `debounceTask` (delay) + `searchTask` (work) properties, and the canonical SearchViewController (/Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/Search/SearchViewController+Search.swift) follows that split — so the flagged single-task pattern is the opposite of the repo's documented convention; conventionEndorsed=false. The suggestion is also AGENTS-compatible: a shared helper in Interface/Browse/Support matches the documented scope "browse-only helpers shared across album/song/download flows", and canonicalizing to the debounceTask/searchTask split makes the code MORE like the rest of the repo, not less. One overstated detail: `searchTracksByID` vs `tracksByID` is partially structural, not gratuitous — SongsViewController keeps a separate full-library `tracksByID` (SongsViewController.swift line 228, lookup switch at line 277), while SongLibraryViewController only populates `tracksByID` for search results. That nuance does not undermine the core finding. Severity stays medium: the divergent guards and especially the keep-old-results vs clear-to-empty error behavior actively mislead readers about intent.

</details>

### [MEDIUM] Audio import flow duplicated verbatim across Songs and Albums controllers

`MuseAmp/Interface/Browse/Songs/SongsViewController.swift:476` · seams-duplication

**问题**: `importTapped`/`documentPicker`/`performImport`/`showImportResult` in SongsViewController.swift (lines 463-522) are a near line-for-line copy of SongLibraryViewController+Actions.swift (lines 25-78): same UIDocumentPickerViewController setup, same AlertProgressIndicatorViewController titles, same `Importing \(current) / \(total)...` progress purpose, and the identical four-line result summary alert. Any change to the import UX or its localized strings must be made twice and can silently drift.

**建议**: Extract a shared presenter (e.g. `AudioImportPresenter` in Interface/Common/Presenters/ holding a weak viewController plus the AudioFileImporter) that owns the picker, the progress alert, and the result alert; both controllers keep only a one-line call plus their post-import reload.

<details><summary>验证记录</summary>

Diff-verified: the import flow in SongsViewController.swift (463-523) and SongLibraryViewController+Actions.swift (25-78, 388-393) is line-for-line identical except one `private` keyword and method ordering — same picker setup, progress alert, localized progress string, and four-line result alert. Both controllers back live first-level tabs (Songs, Albums), so the copies will evolve in parallel. AGENTS.md does not endorse the duplication; it actively supports the suggested fix: Interface/Common/Presenters/ already contains a presenter family (SongExportPresenter, ProgressActionPresenter — the latter is used in the very same +Actions file for the refresh flow), and the placement rules say shared UI used by more than one feature belongs in Interface/Common/ or Browse/Support/. An AudioImportPresenter would match the dominant repo style rather than fight it.

</details>

### [MEDIUM] Silent catch swallows database error without logging

`MuseAmp/Interface/Browse/Support/AlbumNavigationHelper.swift:78` · error-boundaries

**问题**: `localCatalogAlbum(albumID:albumName:artistName:)` wraps `environment.databaseManager.tracks(inAlbumID:)` in `do { ... } catch { return nil }` (lines 76-80) with no AppLog call. AGENTS Logging Rules require every catch that silently swallows an error to log via AppLog.error or AppLog.warning; here a DB failure silently downgrades navigation to a stub album and the diagnostic trail is lost. Every comparable query in this scope logs (e.g. SongLibraryViewController+Table.swift:203, SongLibraryViewController+Actions.swift:144).

**建议**: Log before returning: `catch { AppLog.error(self, "localCatalogAlbum tracks query failed albumID=\(albumID) error=\(error)"); return nil }`.

<details><summary>验证记录</summary>

Confirmed: AlbumNavigationHelper.swift lines 76-80 wrap databaseManager.tracks(inAlbumID:) in do/catch that returns nil without any AppLog call. This directly violates the project's explicit Logging Rule ("Every catch block ... that silently swallows an error must log via AppLog.error or AppLog.warning"). The dominant local convention confirms the fix style: all five other tracks(inAlbumID:) catch blocks in the app (SongLibraryViewController+Table.swift:136/203, +Actions.swift:144/187/204, PlaylistDetailViewController+Actions.swift:256) log AppLog.error with albumID and error before returning a fallback. The suggested one-line log matches surrounding repo style exactly and would not make the code read unlike the rest of the module. A DB failure here silently downgrades navigation to a stub album with no diagnostic trail, which actively misleads anyone debugging empty/wrong album-detail reports, so medium severity stands.

</details>

### [MEDIUM] UIButton configuration built three times with ~10 identical lines each

`MuseAmp/Interface/Collections/AlbumHeaderView.swift:167` · seams-duplication

**问题**: `applyButtonStyle(to:filled:)` (lines 167-210) contains two branches whose bodies differ only in `.filled()` vs `.gray()` and two color lines, while the remaining configuration (imagePadding 4, capsule corner, medium size, 13pt semibold symbol config, 15pt semibold title transformer) is repeated verbatim in both branches AND a third time in `makeActionButton(systemImage:)` (lines 212-232). Any style tweak requires three synchronized edits.

**建议**: Create one `makeButtonConfiguration(filled: Bool, title: String?, image: UIImage?) -> UIButton.Configuration` that sets the shared attributes once and switches only the base style/colors; both applyButtonStyle and makeActionButton call it.

<details><summary>验证记录</summary>

Confirmed in MuseAmp/Interface/Collections/AlbumHeaderView.swift: applyButtonStyle(to:filled:) (167-210) has two branches identical except for .filled()/.gray() and two color lines, and makeActionButton(systemImage:) (212-232) repeats the same ~10-line configuration block a third time verbatim. Grep shows this pattern exists nowhere else in the repo, so it is not a deliberate convention, and AGENTS.md says nothing endorsing it. The duplication is more than cosmetic: makeActionButton sets the initial button appearance while applyButtonStyle rebuilds it on size-class changes, so an edit to one copy but not the others produces buttons that visibly change style after the first trait change. The suggested single configuration factory fits existing local style (the file already uses private make* helpers) and violates no AGENTS.md rule. Severity stays medium because the cross-function sync requirement genuinely breeds bugs, though it is contained to one file.

</details>

### [MEDIUM] Direct UIView.transition call bypasses the Interface animation wrapper

`MuseAmp/Interface/Common/AnimatedTextLabel.swift:53` · repository-conventions

**问题**: `animateTextTransition` calls `UIView.transition(with:duration:options:animations:)` directly (lines 53-58), violating the AGENTS Animation Rule "Never call UIView.animate or UIView.transition directly" — and it shows why the rule exists: the hand-built options list includes `.beginFromCurrentState` but omits `.allowUserInteraction`, which `Interface.transition` (Interface/Common/Style/Interface.swift:91-105) would have applied automatically. Line 8 additionally calls `layer.removeAllAnimations()` in the `disablesAnimations` didSet, which the same rules forbid.

**建议**: Replace with `Interface.transition(with: self, duration: textChangeAnimationDuration, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: {})` and drop the removeAllAnimations call (gate new transitions on `disablesAnimations` instead).

<details><summary>验证记录</summary>

Confirmed: AnimatedTextLabel.swift lines 53-58 call UIView.transition directly with a hand-built options set that includes .beginFromCurrentState but omits .allowUserInteraction; AGENTS.md line 133 explicitly forbids direct UIView.transition calls and mandates the Interface wrappers, and Interface.transition (Interface/Common/Style/Interface.swift:91-105) would supply both interruptible options automatically. Line 8's layer.removeAllAnimations() in the disablesAnimations didSet violates AGENTS.md line 136. Grep shows this is the only direct UIView.transition/animate call in the app target outside the wrapper file itself, so it is an outlier, not a local convention. The suggested fix (Interface.transition with animations: {}) compiles against the wrapper's signature and aligns the code with the rest of the repo. AGENTS.md explicitly forbids — not endorses — the flagged pattern, so conventionEndorsed=false.

</details>

### [MEDIUM] Preview temp-file writing duplicated with MuseAmpImageView+Preview

`MuseAmp/Interface/Common/Presenters/ImageQuickLookPreviewPresenter.swift:52` · seams-duplication

**问题**: `makePreviewFileURL(image:fileName:preferredExtension:)` (lines 52-80) reimplements the logic of MuseAmpImageView+Preview.swift `makePreviewFileURL(from:sourceURL:)` (lines 39-69): identical png-vs-jpeg(0.98) encoding choice, temporaryDirectory + UUID filename, atomic write, and the same AppLog warning/error messages ("makePreviewFileURL no data generated" / "write failed"). Both files also each carry their own QLPreviewControllerDataSource with the `previewItemURL! as NSURL` force unwrap (line 89 here, line 95 there).

**建议**: Extract one helper (e.g. `enum ImagePreviewFileWriter { static func writeTemporaryFile(image:baseName:preferredExtension:) -> URL? }`) in Interface/Common and have both call sites use it; consider sharing the single-item QLPreviewControllerDataSource too.

<details><summary>验证记录</summary>

Verified: ImageQuickLookPreviewPresenter.makePreviewFileURL (lines 52-80) and MuseAmpImageView+Preview.makePreviewFileURL (lines 39-69) duplicate the encode-and-write core verbatim — png-vs-jpeg(0.98) choice, temporaryDirectory+UUID path, atomic write, and identical AppLog warning/error strings. Both files also carry separate QLPreviewControllerDataSource implementations with the same `previewItemURL! as NSURL` force unwrap (line 89 / line 95). Surrounding logic differs (LRU caching keyed by sourceURL and extension-from-URL in the image view; filename sanitization and deinit cleanup in the presenter), so the suggestion's secondary idea of sharing the dataSource is weak, but extracting the temp-file writer is sound, both call sites are already in Interface/Common, and AGENTS.md explicitly places cross-feature shared UI infrastructure there — no convention endorses the duplication. A change to encoding/quality/temp strategy in one copy will silently miss the other, so medium severity is justified.

</details>

### [LOW] Skeleton row count is a bare magic number

`MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift:440` · named-constants

**问题**: `applySnapshot()` builds the loading state with `let count = 64` (line 440) — a magic literal with a meaningless name (`count`) that does not explain why 64 skeleton rows are appended while tracks load.

**建议**: Hoist to a named constant near the type's other configuration, e.g. `private static let skeletonRowCount = 64`, so the intent (fill the viewport with placeholder rows) is named at its declaration.

<details><summary>验证记录</summary>

Confirmed: line 440 of AlbumDetailViewController.swift is `let count = 64`, a bare magic literal with a meaningless name feeding skeleton row generation in the loading branch of applySnapshot(). AGENTS.md does not endorse inline magic numbers (its only hardcode rule is the unrelated 200 pt lyrics/queue spacer), and the same file already declares `private static let` configuration (releaseDateParser/releaseDateDisplay), so hoisting to `private static let skeletonRowCount = 64` matches existing local style. The adjacent `.map { AlbumItem.skeleton(index: $0) }` makes intent partially inferable, so this is cosmetic — severity low.

</details>

### [LOW] Redundant per-dequeue selectionStyle assignments fight TableBaseCell

`MuseAmp/Interface/Browse/AlbumDetail/AlbumDetailViewController.swift:381` · repository-conventions

**问题**: The cell provider sets `cell.selectionStyle = .none` on AlbumHeaderCell (line 381), the skeleton cell (line 389) and DetailFooterCell (line 422) even though all three inherit TableBaseCell, whose init already sets `selectionStyle = .none` and hides `selectedBackgroundView`. AGENTS Cell Rules state the gray highlight is controlled only by `selectedBackgroundView` visibility, so these reassignments are dead configuration noise repeated on every dequeue.

**建议**: Delete the three `cell.selectionStyle = .none` lines; keep only the `isUserInteractionEnabled` toggles that actually differ per row kind.

<details><summary>验证记录</summary>

Confirmed: lines 381, 389, 422 of AlbumDetailViewController.swift set cell.selectionStyle = .none on AlbumHeaderCell, AlbumTrackSkeletonCell, and DetailFooterCell, all of which inherit TableBaseCell (MuseAmp/Interface/Common/TableBaseCell.swift) whose init already sets selectionStyle = .none and installs a hidden selectedBackgroundView. The only path that could make the reassignment load-bearing — TableBaseCell.setEditing flipping selectionStyle to .default — never fires because AlbumDetailViewController never uses editing mode. AGENTS.md Cell Rules explicitly say cells inherit TableBaseCell for this and 'Never use selectionStyle to remove the gray tap highlight', so the flagged pattern violates rather than follows convention; the .track case in the same closure already omits the assignment, so deletion improves internal consistency. Cosmetic-only, hence low severity.

</details>

### [LOW] Force-cast cell dequeues inconsistent with sibling controllers' guarded pattern

`MuseAmp/Interface/Browse/Albums/SongLibraryViewController.swift:284` · mechanical-consistency

**问题**: The cell provider force-casts `as! AmMediaCell` (line 284) and `as! AmSongCell` (line 302) (SongsViewController.swift:275 does the same), whereas AlbumDetailViewController (lines 371-374, 394-399) and DownloadsViewController (lines 246-254) dequeue the same way but use `guard let ... as? ... else { return UITableViewCell() }`. Two crash-on-misregistration styles coexist for the identical operation within the same browse scope.

**建议**: Standardize on one dequeue idiom across the browse controllers — either the guarded `as?` + fallback used by AlbumDetail/Downloads, or SwifterSwift's `dequeueReusableCell(withClass:for:)` everywhere.

<details><summary>验证记录</summary>

Confirmed: SongLibraryViewController.swift:284/302 and SongsViewController.swift:275 force-cast dequeued cells (`as!`), while AlbumDetailViewController (371-374, 394-399) and DownloadsViewController (246-254) in the same Interface/Browse scope use `guard let ... as? ... else { return UITableViewCell() }` for the identical operation. The two idioms also coexist repo-wide (force-cast in Search/PlaylistViewController; guarded in PlaylistDetail/NowPlayingQueue/Sync), so neither is a dominant deliberate convention and standardizing would not make the code read unlike the repo. AGENTS.md has no dequeue rule; its SwifterSwift highlight of dequeueReusableCell(withClass:for:) is compatible with the suggestion. The inconsistency is genuine but purely mechanical/cosmetic — both idioms are standard UIKit and the casts cannot realistically fail given same-file registrations — so severity stays low.

</details>

### [LOW] Task-state predicates duplicated between menu builder and BarMenuState

`MuseAmp/Interface/Browse/Downloads/DownloadsViewController.swift:166` · seams-duplication

**问题**: `currentTasks.contains { $0.state != .failed }` appears at line 166 (buildMenuElements) and line 317 (currentBarMenuState); `currentTasks.contains { $0.state == .waitingForNetwork }` appears at line 187 and line 318. The two copies must stay in sync for the BarMenuState equality short-circuit (line 143) to correctly decide when the menu needs rebuilding.

**建议**: Introduce computed properties (`private var hasActiveTasks: Bool`, `private var hasTasksWaitingForNetwork: Bool`) and use them in both buildMenuElements and currentBarMenuState.

<details><summary>验证记录</summary>

Duplication confirmed: `currentTasks.contains { $0.state != .failed }` at lines 166 and 316, and `currentTasks.contains { $0.state == .waitingForNetwork }` at lines 187 and 318, with the BarMenuState equality short-circuit at line 143. The finding slightly overstates the consequence — the bar menu uses UIDeferredMenuElement.uncached, so menu contents are rebuilt at presentation and predicate drift would only misfire the bar-item refresh gate, not show stale actions. But the seam is real: BarMenuState fields silently mirror inline predicates in buildMenuElements, and the fix (private computed properties used at both sites) matches AGENTS.md's explicit rule that values derivable from other state should be computed properties. Nothing in AGENTS.md or the surrounding module endorses duplicating these predicates. Low severity: maintenance-only hazard with no current user-visible effect.

</details>

### [LOW] refreshVisibleCells resolves rows by index despite ID-keyed data source

`MuseAmp/Interface/Browse/Downloads/DownloadsViewController.swift:324` · seams-duplication

**问题**: `refreshVisibleCells()` (lines 324-335) maps `indexPath.row` into `currentTasks`, while the diffable source is keyed by trackID and the controller already maintains `tasksByTrackID` exactly for dequeue-time resolution (line 247). Correctness currently rests on the subtle invariant that `currentTasks` order always equals the applied snapshot order (guarded by `identityChanged` in renderCurrentTasks); resolving by ID would make the update self-evidently safe.

**建议**: Use `diffableDataSource.itemIdentifier(for: indexPath)` and look up `tasksByTrackID[trackID]` instead of `currentTasks[indexPath.row]`, the same scheme the cell provider uses.

<details><summary>验证记录</summary>

Verified: refreshVisibleCells() (DownloadsViewController.swift:324-335) indexes currentTasks[indexPath.row] while the diffable source is keyed by trackID and tasksByTrackID exists precisely for ID-based resolution (used by the cell provider at line 247). Correctness depends on the subtle invariant that currentTasks order matches the applied snapshot, made more delicate by the isShowingRowContextMenu deferral path where currentTasks is replaced while the displayed snapshot is stale. AGENTS.md does not endorse index-based resolution, and the dominant repo convention in sibling browse/playlist controllers is dataSource.itemIdentifier(for:) — so the suggested fix aligns with, rather than violates, local style. Current call sites preserve the order invariant, so no live bug; this is a low-severity clarity/fragility finding.

</details>

### [LOW] +Table file is a grab-bag: table delegate plus playback, deletion, menus, and search

`MuseAmp/Interface/Browse/Songs/SongsViewController+Table.swift:213` · file-organization

**问题**: Despite the repo's responsibility-based split convention (AGENTS UIKit File Rules; SongLibraryViewController has dedicated +Search.swift, and SongsViewController+Actions.swift already exists), this +Table file contains the UITableViewDelegate conformance (lines 14-95), a "Playback & Navigation" extension with playTrack/openAlbumForTrack/confirmDeleteTrack/buildContextMenu/makeRepairArtworkAction (lines 99-209), and the entire UISearchResultsUpdating + performSearch debounce implementation (lines 213-255). The filename promises table wiring but hides three other responsibilities.

**建议**: Move UISearchResultsUpdating/performSearch into SongsViewController+Search.swift (mirroring SongLibraryViewController+Search.swift) and the playback/menu/delete helpers into +Actions.swift or a +Playback.swift, leaving only delegate methods here.

<details><summary>验证记录</summary>

Facts verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/Browse/Songs/SongsViewController+Table.swift: lines 14-95 are UITableViewDelegate, lines 99-209 are a "Playback & Navigation" extension (playTrack, openAlbumForTrack, confirmDeleteTrack/deleteTrack, buildContextMenu, makeRepairArtworkAction), and lines 213-255 are UISearchResultsUpdating plus the full performSearch debounce implementation. The finding's description is accurate.

However, only part of it survives adversarial comparison with the surrounding module's dominant convention:

- The playback/menu-helper portion is largely conventional, not a defect: sibling +Table files do the same — SongLibraryViewController+Table.swift has an "Album Navigation & Helpers" extension with buildMenu/openAlbum/openAlbumForTrack/playbackTracks (lines 111-220), and PlaylistViewController+Table.swift has "Navigation & Preview Helpers" and "Subtitle Helpers" extensions. Moving buildContextMenu/playTrack out of +Table (as the suggestion proposes) would make Songs read UNLIKE its Browse siblings, so that half of the suggestion is refuted under the repository-conventions principle.
- The search portion is a genuine deviation: every other searchable controller in the repo keeps UISearchResultsUpdating + performSearch in a dedicated +Search.swift (Interface/Browse/Albums/SongLibraryViewController+Search.swift, Interface/Playlist/PlaylistViewController+Search.swift, Interface/Search/SearchViewController+Search.swift). SongsViewController is the lone outlier embedding search in +Table, and AGENTS.md UIKit File Rules explicitly names "+Search.swift" as a responsibility file. A SongsViewController+Search.swift mirroring SongLibraryViewController+Search.swift would be a strict consistency improvement with no convention conflict.

AGENTS.md does not endorse the grab-bag pattern itself (it mandates responsibility-based splits), so conventionEndorsed=false. Because half the complaint targets the module's deliberate convention and the remaining real issue (misplaced search code, ~43 lines, clearly MARKed) is a cosmetic organization/consistency matter rather than something that misleads readers into bugs, severity is adjusted down to low.

</details>

### [LOW] Track numbers above 50 silently render no number glyph

`MuseAmp/Interface/Collections/AlbumTrackCell.swift:199` · error-boundaries

**问题**: `trackNumberImage(_:)` builds the icon from the SF Symbol name `"\(number).circle.fill"` (lines 199-202). The numbered circle.fill symbols only exist for 0-50, so `UIImage(systemName:)` returns nil for larger track numbers (long compilations, multi-disc sets) and the cell shows an empty gap where the number should be, with no fallback or log.

**建议**: Fall back when the symbol is missing, e.g. return a text-drawn number image or a generic `circle.fill` for `number > 50`, making the limit explicit in code.

<details><summary>验证记录</summary>

Verified at AlbumTrackCell.swift:199-202: trackNumberImage builds "\(number).circle.fill" with no fallback; numbered SF Symbols only exist for 0-50, so larger track numbers produce a nil image and a silent blank gap. The input is unclamped — AlbumDetailViewController.swift:444 uses track.attributes.trackNumber ?? (index + 1), so albums with >50 tracks reach this path. AGENTS.md does not endorse the pattern (no SF Symbol conventions; logging rules actually discourage silent failure), and this is the only dynamic numbered-symbol construction in the repo. The suggested fallback is a one-line UIKit-idiomatic change that makes the hidden 0-50 limit explicit without violating any repo convention. Severity remains low: rare data shape and purely cosmetic degradation.

</details>

### [LOW] Stored hasAccessory flag duplicates view-hierarchy state

`MuseAmp/Interface/Collections/SearchSectionHeaderView.swift:16` · state-modeling

**问题**: `private var hasAccessory = false` (line 16) only tracks whether `accessoryButton` has been added to contentView (lines 34-42). That fact is already available as `accessoryButton.superview != nil`, so the flag violates the AGENTS Property Rule "Do not introduce stored properties to track state that is already available from an existing source of truth" and can desynchronize if the hierarchy ever changes.

**建议**: Drop the flag and guard with `if accessoryButton.superview == nil { contentView.addSubview(...); accessoryButton.snp.makeConstraints { ... } }` — or pre-add the button in init and toggle isHidden, per the pre-alloc convention.

<details><summary>验证记录</summary>

Confirmed: `hasAccessory` (line 16) is written once exactly where `accessoryButton` is added to contentView (lines 35-37) and read only to guard that add; it is a stored duplicate of `accessoryButton.superview != nil`. AGENTS.md Property Rules explicitly forbid stored properties tracking state available from an existing source of truth and require derived state to be computed. The repo's other `hasX` flags (hasPreparedInitialData, hasLoadedArtwork, the mandated hasAppliedInitialSnapshot) track facts not derivable from other state, so no local convention endorses this duplication. The suggested fix (superview check, or better, pre-adding in init and toggling isHidden) aligns with the AGENTS.md pre-alloc rule and is a safe drop-in — prepareForReuse already forces the lazy button's creation, so the lazy-trigger objection doesn't hold. Severity remains low: the button is never removed, so the flag cannot currently desync; this is purely a clarity/state-modeling improvement.

</details>

### [LOW] try? FileManager.removeItem swallows deletion errors without logging

`MuseAmp/Interface/Common/Presenters/ImageQuickLookPreviewPresenter.swift:41` · error-boundaries

**问题**: Two `try? FileManager.default.removeItem(at:)` calls silently discard errors: line 22 (deinit cleanup of the previous preview file) and line 41 (replacing a stale preview file in `present`). AGENTS Logging Rules require every error-swallowing `try?` to log via AppLog, and file I/O deletes specifically must log failures via AppLog.error. The same class already logs its write failures (lines 69, 77), so the delete paths are inconsistently silent.

**建议**: Convert line 41 to do/catch with `AppLog.warning(self, "failed to remove stale preview file error=...")`; for the deinit path, log via a nonisolated-safe AppLog call or schedule cleanup somewhere it can be observed.

<details><summary>验证记录</summary>

Confirmed: lines 22 and 41 of ImageQuickLookPreviewPresenter.swift use `try? FileManager.default.removeItem(at:)` with no logging, while the same class logs its write failures via AppLog (lines 69, 77). AGENTS.md line 203 explicitly requires every error-swallowing `try?` to log via AppLog.error/AppLog.warning, and the dominant repo convention for removeItem is do/catch + AppLog (DownloadArtworkProcessor, ExportMetadataProcessor, DownloadManager+Persistence, PlaybackSessionStore, Sync* stores all do this). The suggested fix matches local style rather than fighting it. Severity lowered to low: the swallowed error only concerns cleanup of OS-reclaimed temp files, so it cannot corrupt state or breed bugs — it is a diagnostics/convention gap, not actively misleading code.

</details>

### [LOW] Dead `_ = viewController` statements after guard

`MuseAmp/Interface/Common/Presenters/ProgressActionPresenter.swift:30` · mechanical-consistency

**问题**: Both run() overloads end their dismiss completions with `guard let viewController else { return }` followed by an unused-binding suppressor `_ = viewController` (lines 30, 38, 66). The binding is never actually used; the `_ =` exists only to silence the unused-variable warning, leaving three lines of hand-fought noise that read as if they do something.

**建议**: Replace each `guard let viewController else { return }` + `_ = viewController` pair with `guard viewController != nil else { return }`.

<details><summary>验证记录</summary>

Confirmed at lines 28-30, 36-38, 64-66 of ProgressActionPresenter.swift: each dismiss completion has `guard let viewController else { return }`, invokes the callback, then `_ = viewController` purely to suppress the unused-binding warning. Repo-wide grep shows this `_ =` suppressor pattern exists only in this file; all other `guard let viewController` sites genuinely use the binding, so the dominant local convention is to bind only when used. AGENTS.md says nothing endorsing the pattern. The fix (`guard viewController != nil`) is the compiler's own suggested idiom, keeps the alive-check intent, and has no semantic downside since callbacks capture and guard their own weak viewController. Cosmetic-only impact, so severity remains low.

</details>

## [clarity] interface-nowplaying (32)

### [HIGH] Tap/seek path re-parses lyrics from a different source than the rendered timeline

`MuseAmp/Interface/NowPlaying/LyricTimeline/LyricTimelineView+Actions.swift:90` · state-modeling

**问题**: `currentTimeline()` (lines 90-102) re-derives the timeline on every row tap / context menu by reading environment.lyricsService.cachedLyrics, re-running Chinese script conversion, and re-running LyricParser — even though the rendering pipeline in LyricTimelineView+Binding (parseLyrics/buildSnapshot) already produced a ParsedLyrics containing exactly this timeline. The view discards it, keeping only `items`. The two derivations can disagree (e.g. lyrics just loaded via loadLyrics but not yet in cachedLyrics), so a tapped line can seek against a timeline that does not match what is displayed.

**建议**: Store the latest ParsedLyrics (or its LyricTimeline) on LyricTimelineView when applying a snapshot, and use that single source of truth in seekToLine(at:) and makeLineContextMenu(at:), deleting currentTimeline().

<details><summary>验证记录</summary>

Confirmed and stronger than claimed. currentTimeline() (Actions.swift lines 90-102) re-derives the timeline from lyricsService.cachedLyrics + re-conversion + re-parse, while the rendered items come from a ParsedLyrics built via loadLyrics in Binding.swift that the view discards (only items[] is kept). LyricsService.loadLyrics only writes to the cache when the track is downloaded (persistLyricsIfDownloaded guards on database.hasTrack), so for any streamed track cachedLyrics returns nil, currentTimeline() returns nil, and seekToLine / "Play from Here" silently no-op despite a synced timeline being displayed — a permanent functional bug, not just a transient race. AGENTS.md does not endorse the pattern; the suggested fix (retain the ParsedLyrics/timeline applied to the snapshot as the single source of truth) matches the file's existing structure and the repo's source-of-truth property rules.

</details>

### [HIGH] Dead 300-line NowPlayingLyricsCoordinator shadows the live lyric-loading path

`MuseAmp/Interface/NowPlaying/Support/NowPlayingLyricsCoordinator.swift:14` · seams-duplication

**问题**: `final class NowPlayingLyricsCoordinator` is never instantiated anywhere in the repo (grep over MuseAmp/MuseAmpTV/MuseAmpTests finds only the definition; tvOS uses its own TVNowPlayingLyricsCoordinator). The live lyric-loading pipeline now lives in LyricTimelineView+Binding.swift (bindDataSource -> lyricsService.loadLyrics -> parseLyrics). Only the file-bottom free function `shouldCacheUnavailableLyricsResult` (line 303) is still referenced — by this dead class and MuseAmpTests/NowPlaying/NowPlayingLyricsLoadingTests.swift. The class carries a full stale state machine (lyricsCache/lyricsRawCache/lyricsLoadingTrackID/lyricsTransientFailureTrackID) that actively misleads readers into thinking it is the canonical lyrics path.

**建议**: Delete the NowPlayingLyricsCoordinator class. Relocate shouldCacheUnavailableLyricsResult into a small purpose-named file (e.g. under Backend/Lyrics/) so the existing tests keep passing, and update AGENTS-aligned file naming (filename = export).

<details><summary>验证记录</summary>

Verified: NowPlayingLyricsCoordinator is defined but never instantiated anywhere in MuseAmp/MuseAmpTV/MuseAmpTests (grep finds only the definition; tvOS uses a separate TVNowPlayingLyricsCoordinator, no symlink). The live lyric pipeline is LyricTimelineView+Binding.bindDataSource -> LyricsService.loadLyrics -> parseLyrics, and LyricsService.loadLyrics's own doc comment names itself as the bindDataSource loader. The only live reference into the file is the free function shouldCacheUnavailableLyricsResult, used by the dead class and by NowPlayingLyricsLoadingTests. Critically, the live path does not call that helper, so the 404 empty-lyrics caching behavior survives only in dead code while tests still validate it — a silent behavioral divergence that misleads and likely already constitutes a lost-behavior regression. All Support/ siblings are live, so this is not a local convention, and AGENTS.md does not endorse keeping superseded implementations; the suggested fix (delete class, relocate helper under Backend/Lyrics/) matches AGENTS.md placement rules and keeps tests passing.

</details>

### [MEDIUM] NowPlayingQueueTrackCell is dead code kept alive only by a test

`MuseAmp/Interface/NowPlaying/Components/NowPlayingQueueTrackCell.swift:5` · seams-duplication

**问题**: The class is never registered or dequeued anywhere in app code — NowPlayingQueueSectionView registers AmSongCell, NowPlayingQueueHeaderCell, NowPlayingQueueEmptyCell, NowPlayingQueueFooterCell (NowPlayingQueueSectionView.swift:116-131). The only reference outside this file is MuseAmpTests/NowPlaying/NowPlayingQueueCellTests.swift:41-42, which asserts selection suppression on a cell no screen uses.

**建议**: Delete NowPlayingQueueTrackCell.swift and the corresponding test case; AmSongCell is the canonical queue row cell.

<details><summary>验证记录</summary>

Confirmed dead code. Symlink-following repo-wide grep shows NowPlayingQueueTrackCell is never registered, dequeued, or instantiated in any app/package/tvOS code; NowPlayingQueueSectionView.swift:116-131 registers AmSongCell plus the header/empty/footer queue cells only, and the reuseID string is never used in a dequeue. The sole external reference is MuseAmpTests/NowPlaying/NowPlayingQueueCellTests.swift:41-45, which only re-asserts TableBaseCell selection suppression already covered by four base-class tests in the same suite, so deleting the cell and its test loses no coverage. AGENTS.md does not endorse retaining unused cells, and its Testing Rules actually discourage the presentation-only assertion keeping this class alive. The fix matches repo conventions. Severity medium is fair: the name/location (NowPlaying/Components, alongside three actually-used queue cells) actively misleads a maintainer into editing this cell to change queue row appearance, where AmSongCell is the real row cell.

</details>

### [MEDIUM] Trailing guards with empty bodies are leftover dead code in three methods

`MuseAmp/Interface/NowPlaying/Controller/NowPlayingCompactController+Playback.swift:28` · function-design

**问题**: applySupplementalPlaybackProgress ends with `guard controlIslandViewModel.selectedContentSelector == .lyrics else { return }` followed by nothing (lines 28-29); refreshPlayingContent ends with `guard selector == .lyrics else { return }` followed by nothing (lines 88-90); and NowPlayingRelaxedController+Playback.swift:29-31 has an entire body that is just `guard currentRightPanel == .lyrics else { return }`. These are remnants of removed lyric-progress pushes and mislead readers into believing lyric-specific work happens behind them.

**建议**: Delete the trailing guards; make the relaxed applySupplementalPlaybackProgress an explicit empty implementation (or remove the requirement for controllers that need no supplemental progress).

<details><summary>验证记录</summary>

All three cited locations verified verbatim: NowPlayingCompactController+Playback.swift line 28 (trailing guard ending applySupplementalPlaybackProgress) and lines 88-90 (trailing guard ending refreshPlayingContent), plus NowPlayingRelaxedController+Playback.swift lines 29-31 where the entire body is one guard. Each is a guard...else { return } followed by no statements — a functional no-op that implies lyric-specific work which does not exist. applySupplementalPlaybackProgress is a protocol requirement (NowPlayingPlaybackShellController.swift:49) invoked on every playback snapshot/progress update (lines 65, 144, 181), so readers tracing lyric progress flow will land here and be misled. Project instructions endorse guards for reducing nesting, not dead guards; no local convention endorses this. The suggested fix (delete the guards, keep an explicitly empty relaxed implementation since the protocol requires it) is behavior-preserving and consistent with repo style. Medium severity stands: it actively misleads maintainers about where lyric progress is handled.

</details>

### [MEDIUM] Lyric cells bypass TableBaseCell and re-set selectionStyle inline

`MuseAmp/Interface/NowPlaying/LyricTimeline/Cells/LyricTimelineCell.swift:5` · repository-conventions

**问题**: AGENTS.md Cell Rules: "All table/collection cells inherit from TableBaseCell". LyricTimelineCell (line 5), LyricTimelineMessageCell, LyricTimelineSpacerCell, and LyricSelectionCell (LyricSelectionSheetViewController.swift:196) all subclass UITableViewCell directly and hand-set `selectionStyle = .none` (line 30 here; MessageCell:25, SpacerCell:12). The queue cells in Components/ correctly inherit TableBaseCell, so the same feature contains both patterns, and NowPlayingQueueSectionView additionally re-sets `cell.selectionStyle = .none` on already-compliant cells (lines 331, 715).

**建议**: Rebase the LyricTimeline cells on TableBaseCell and drop the inline selectionStyle assignments (including the redundant ones in NowPlayingQueueSectionView). Keep LyricSelectionCell separate only if multi-select editing genuinely needs the system selected background, and document that exception.

<details><summary>验证记录</summary>

Every cited location verifies: LyricTimelineCell (line 5, selectionStyle at 30), LyricTimelineMessageCell (5/25), LyricTimelineSpacerCell (5/12), LyricSelectionCell (LyricSelectionSheetViewController.swift:196) all subclass UITableViewCell directly; NowPlayingQueueSectionView.swift:331 and :715 redundantly set selectionStyle = .none on cells already inheriting TableBaseCell. AGENTS.md lines 140-141 explicitly mandate TableBaseCell inheritance and explicitly forbid using selectionStyle to remove the tap highlight, so the flagged pattern is the opposite of the documented convention (conventionEndorsed=false). The dominant local convention also matches the fix: 14 app-target cells inherit TableBaseCell vs 4 direct UITableViewCell subclasses, and the queue cells in the same NowPlaying feature comply (including the backgroundColor = .clear override the lyric cells would need). The suggestion is feasible and would align code with both AGENTS.md and the surrounding module. Medium severity holds: the in-feature mixed pattern misleads maintainers, and the redundant selectionStyle stamps can fight TableBaseCell.setEditing's deliberate selectionStyle toggle during editing, a real bug vector. The only caveat — LyricSelectionCell may intentionally keep system selection for the sheet — is already handled by the suggestion's documented-exception clause.

</details>

### [MEDIUM] Stale LyricTimelineAnimation constants while live animation code inlines magic numbers

`MuseAmp/Interface/NowPlaying/LyricTimeline/LyricTimelineStyle.swift:3` · named-constants

**问题**: Of the seven constants in LyricTimelineAnimation, only plainRevealTranslationY is used — and it is misused as a layout inset (`let verticalInset = LyricTimelineAnimation.plainRevealTranslationY / 2`, LyricTimelineCell.swift:34), not as an animation translation. initialRevealDuration/initialRevealStagger/outgoingFadeDuration/outgoingFadeStagger/plainRevealDuration/easeOutOptions are dead, while the actual fade-in animation hardcodes `duration: 0.5, delay: Double(order) * 0.1` inline (LyricTimelineView.swift:162-164). The file also holds two unrelated exports (LyricTimelineAnimation + LyricTimelineLineStyle) under a third name, LyricTimelineStyle.

**建议**: Delete the dead animation constants, name the live 0.5/0.1 reveal duration/stagger in their place, and give the cell its own verticalInset constant. Rename the file (or split) so the filename matches its exports.

<details><summary>验证记录</summary>

Every claim verified by direct read + repo-wide grep. Six of seven LyricTimelineAnimation constants (initialRevealDuration/initialRevealStagger/outgoingFadeDuration/outgoingFadeStagger/plainRevealDuration/easeOutOptions) have zero references. The sole used constant, plainRevealTranslationY, is consumed at LyricTimelineCell.swift:34 as a static layout inset (`/ 2`), not as an animation translation. The live reveal animation (LyricTimelineView.swift:162-167, animateContentFadeIn) inlines duration 0.5 and stagger 0.1 — values that differ from the dead constants (0.32/0.035), so editing the constants file is a silent no-op and edits to the 'translation' constant silently change cell padding. The file LyricTimelineStyle.swift exports two enums, neither named LyricTimelineStyle. AGENTS.md contains nothing endorsing this; the surrounding module's own convention (nonisolated enum Layout of named constants in LyricTimelineView.swift:7-18) matches the suggested fix, so the fix reads like the rest of the repo. Medium severity is appropriate: the stale constants actively mislead maintainers tuning the animation, though no shipped bug was found.

</details>

### [MEDIUM] LyricTimelineView also uses a manual data source instead of the mandated diffable pattern

`MuseAmp/Interface/NowPlaying/LyricTimeline/LyricTimelineView.swift:71` · repository-conventions

**问题**: `tableView.dataSource = self` (line 71) with the conformance in LyricTimelineView+Delegate.swift, plus hand-rolled structure-change detection in applySnapshot (lines 122-130) and reloadData branches (lines 108, 116, 135), violates the AGENTS.md rule that all UITableViews use UITableViewDiffableDataSource. Items already have stable identities (.line(index)/.staticLine(index)/.spacer/.message), so the manual zip-based structure diff re-implements exactly what a diffable snapshot would do.

**建议**: Back the lyric table with UITableViewDiffableDataSource keyed by the Item cases (make Item Hashable), use reconfigureItems for active-line state changes, and keep the fade-in/fade-out branches as animation wrappers around snapshot application.

<details><summary>验证记录</summary>

Confirmed: LyricTimelineView.swift line 71 sets tableView.dataSource = self with UITableViewDataSource conformance in LyricTimelineView+Delegate.swift, and applySnapshot hand-rolls structure-change detection (zip diff, lines 122-130) plus three reloadData branches and a manual visible-cell patch loop. AGENTS.md line 124 explicitly mandates diffable data sources for ALL table/collection views with no exception for lyric views, so conventionEndorsed=false; the dominant repo pattern (10+ files, including the sibling LyricSheet controller in the same NowPlaying feature) is diffable, so the fix moves the code toward, not away from, repo style. The suggestion is feasible (items already carry stable indices; the two spacers are distinct), though its detail of keying by the full Item enum is slightly off — identity must exclude isActive for reconfigureItems to work. Severity stays medium because the hand-rolled diff already harbors a latent bug: the structure check compares only line indices, so a same-structure lyrics text update takes the state-only path and leaves stale text in visible cells.

</details>

### [MEDIUM] Manual UITableViewDataSource with hand-rolled diffing violates the repo diffable-data-source rule

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingQueueSectionView.swift:23` · repository-conventions

**问题**: AGENTS.md View Lifecycle Rules mandate: "All UITableView / UICollectionView must use UITableViewDiffableDataSource ... No manual data-source mutations." This view implements UITableViewDataSource directly (line 23), drives updates via reloadData/reloadSections(.fade) (lines 207, 225), and reimplements what diffable provides with a custom change-tracking struct NowPlayingQueuePresentationUpdate (lines 4-20: seven did*Change booleans) plus manual refreshVisibleCells/refreshQueueControlsCell/refreshQueueFooterCell. This is the largest deviation from the project's own mandated table pattern and must be re-learned by every maintainer.

**建议**: Migrate to UITableViewDiffableDataSource keyed by the existing string ItemIdentifier values, using snapshot.reconfigureItems() for in-place header/footer/track content updates and the hasAppliedInitialSnapshot flag the repo already prescribes; delete NowPlayingQueuePresentationUpdate.

<details><summary>验证记录</summary>

Verified: NowPlayingQueueSectionView.swift line 23 conforms to UITableViewDataSource directly, uses reloadData (line 207) and reloadSections(.fade) inside performBatchUpdates (lines 224-225), and reimplements diffing via the 7-boolean NowPlayingQueuePresentationUpdate struct (lines 4-20) plus manual refreshVisibleCells/refreshQueueControlsCell/refreshQueueFooterCell. AGENTS.md line 124 explicitly mandates diffable data sources for all UITableView/UICollectionView with 'No manual data-source mutations', so the pattern is the opposite of endorsed (conventionEndorsed=false). The dominant repo convention is diffable (10 files across Browse/Playlist/Search/Sync/Sidebar, including LyricSelectionSheetViewController inside the same NowPlaying module); manual data sources are a small minority. The suggested migration is feasible exactly as proposed: AMQueueItemContent.id values are already unique stable strings built via ItemIdentifier.track(trackID:occurrence:) in AMNowPlayingQueueSnapshotBuilder.swift, and the view already carries the repo-prescribed hasAppliedInitialSnapshot flag and snapshot vocabulary — which currently misleads readers into assuming diffable semantics. Severity adjusted from high to medium: no evidence the pattern has already bred a shipped bug, but it actively misleads readers and the hand-rolled section-diff booleans plus .fade section reloads are bug-prone for count-mismatch crashes.

</details>

### [MEDIUM] isProgramaticScrollBlocked is a Date named like a Bool, and misspelled

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingQueueSectionView.swift:143` · naming

**问题**: `var isProgramaticScrollBlocked: Date = .distantPast` uses an is-prefixed boolean-style name for a cooldown deadline, and misspells "Programmatic" (single m) in 5 occurrences (lines 143, 608, 618, 622, 634-635) while the same file spells `pendingProgrammaticScrollRetry`/`blockProgrammaticScroll` correctly. Sibling code uses the Deadline suffix for this exact pattern (LyricTimelineView.userInteractionDeadline, ProgressTrackView.scrubCommitCooldownDeadline). The Date-as-cooldown pattern itself is AGENTS-sanctioned; the misleading name is not.

**建议**: Rename to `programmaticScrollBlockDeadline: Date = .distantPast`, matching userInteractionDeadline/scrubCommitCooldownDeadline.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/NowPlaying/Sections/NowPlayingQueueSectionView.swift: line 143 declares `var isProgramaticScrollBlocked: Date = .distantPast`, and the misspelled identifier appears at lines 143, 608, 618, 622, 634, 635, while the same file spells `pendingProgrammaticScrollRetry`, `blockProgrammaticScroll`, `programmaticScrollBlockDuration`, and `hasActiveProgrammaticScrollBlock` with the correct double-m. The is-prefix makes a Date read as a Bool — e.g. `guard isProgramaticScrollBlocked <= Date()` at line 618 — which actively misleads. Sibling code uses the Deadline suffix for this exact pattern (LyricTimelineView.swift:52 `userInteractionDeadline`, ProgressTrackView.swift:29 `scrubCommitCooldownDeadline`), so the suggested rename `programmaticScrollBlockDeadline` matches the dominant local convention. AGENTS.md line 230 endorses only the `Date = .distantPast` cooldown pattern (phrased as `Date() < deadline`), not the boolean-style naming or the misspelling — the suggested fix aligns with AGENTS.md rather than violating it. Severity medium is justified: the name misleads readers about the type/semantics, and the inconsistent spelling breaks project-wide searches for "Programmatic".

</details>

### [MEDIUM] update(using:animated:) silently ignores its animated parameter

`MuseAmp/Interface/NowPlaying/Support/NowPlayingArtworkBackgroundCoordinator.swift:56` · function-design

**问题**: The signature is `func update(using backgroundSource: BackgroundSource, animated _: Bool)` — the parameter is discarded, yet callers carefully pass meaningful values (`animated: presentation.shouldAnimateTransition` in NowPlayingPlaybackShellController.swift:169-172, `animated: false` in applyInitialPlaybackPresentation and prepareForPopupPresentation). The background actually always animates because NowPlayingArtworkBackgroundView.apply hardcodes `setColors(colors, animated: true)`. The parameter is a behavioral lie that readers must debug to discover.

**建议**: Either honor the flag (thread it into backgroundView.apply / setColors(animated:)) or remove the parameter from the signature and from all call sites.

<details><summary>验证记录</summary>

Verified: the coordinator's update(using:animated:) discards `animated` (line 54-57) while three call sites pass meaningful, differing values (shouldAnimateTransition, false, false), and NowPlayingArtworkBackgroundView.apply hardcodes setColors(animated: true), so the flag is a behavioral lie. The repo's other `animated _:` discards are all UIKit overrides or protocol-extension defaults with externally fixed signatures; this method is self-authored on a final class with one implementation, so local convention does not endorse it. AGENTS.md contains nothing endorsing dead parameters. The suggested fix (honor the flag or delete the parameter and update call sites) is minimal and style-consistent. Medium severity: actively misleads readers and invites no-op "fixes", but no evidence of an existing user-facing bug.

</details>

### [MEDIUM] Lyric-sheet shell protocol is dead; LyricTimelineView re-implements the same presentation inline

`MuseAmp/Interface/NowPlaying/Support/NowPlayingLyricShellController.swift:9` · seams-duplication

**问题**: `presentLyricSelectionSheet(with:activeIndex:)` (lines 5, 9) has zero call sites. The only live path is the private duplicate `presentLyricSelectionSheet(lyrics:activeIndex:)` in LyricTimelineView+Actions.swift:73-88, which repeats the identical body: empty-lyrics guard, responder-chain controller lookup, presentedViewController == nil guard, UINavigationController wrap, .formSheet, prefersGrabberVisible. Consequently the one-line conformance files NowPlayingCompactController+LyricSheet.swift and NowPlayingRelaxedController+LyricSheet.swift wire nothing.

**建议**: Keep one canonical implementation: either route LyricTimelineView through the shell protocol (lookup the owning NowPlayingLyricSheetPresenting controller) and delete the private duplicate, or delete NowPlayingLyricShellController.swift plus both +LyricSheet conformance files and keep the view-local implementation.

<details><summary>验证记录</summary>

Verified: presentLyricSelectionSheet(with:activeIndex:) in NowPlayingLyricShellController.swift has zero call sites repo-wide; the two +LyricSheet conformance files are empty extensions that wire nothing. The only live path is the private presentLyricSelectionSheet(lyrics:activeIndex:) in LyricTimelineView+Actions.swift:73-88, which duplicates the identical presentation body (empty guard, presentedViewController guard, UINavigationController wrap, .formSheet, prefersGrabberVisible) plus a responder-chain lookup. AGENTS.md does not endorse dead protocols or shadowed duplicates; the suggested consolidation fits repo conventions. Medium severity is fair because the dead protocol in Support/ looks canonical and would mislead a maintainer editing sheet presentation behavior.

</details>

### [MEDIUM] Enum case .title is never constructed; all its handling is dead

`MuseAmp/Interface/NowPlaying/ViewModel/Queue/AMNowPlayingQueueHeaderContent.swift:4` · state-modeling

**问题**: `case title(String)` is pattern-matched in four accessors (lines 16, 25, 34, 43) and in NowPlayingQueueHeaderCell.configure (NowPlayingQueueHeaderCell.swift:110-116), but a repo-wide grep shows it is never built — every construction site uses `.controls(...)` (AMNowPlayingQueueSnapshotBuilder.swift:50, AMNowPlayingQueueSnapshot.swift:14, NowPlayingListSectionView.swift:94). Maintainers of the header cell must keep an unreachable branch (and its hide-actions/zero-width logic) alive.

**建议**: Delete the .title case, collapse AMNowPlayingQueueHeaderContent into a struct with title/repeatMode/isShuffleFeedbackActive/isShuffleEnabled fields, and remove the dead branch from NowPlayingQueueHeaderCell.configure.

<details><summary>验证记录</summary>

Verified: `case title(String)` in AMNowPlayingQueueHeaderContent.swift is pattern-matched in four accessors and in NowPlayingQueueHeaderCell.configure (lines 109-116, including hide-actions/zero-width logic), but a repo-wide grep across all targets and packages shows zero construction sites — all three constructors (AMNowPlayingQueueSnapshotBuilder.swift:50, AMNowPlayingQueueSnapshot.swift:14, NowPlayingListSectionView.swift:94) use `.controls(...)`. NowPlayingListSectionView even round-trips an existing headerContent through the accessors just to rebuild `.controls`, showing the enum shape adds ceremony with no payoff. AGENTS.md does not endorse the pattern; its Property Rules favor leaner state modeling. The dead branch carries plausible-looking layout behavior, misleading maintainers into preserving a header mode that never occurs, so medium severity stands.

</details>

### [LOW] Tag-based button dispatch with magic 1/2 instead of identity comparison

`MuseAmp/Interface/NowPlaying/Components/NowPlayingQueueHeaderCell.swift:79` · naming

**问题**: Buttons are assigned `button.tag = tag + 1` in a loop (line 80) and handleTap switches on `sender.tag` cases 1 and 2 (lines 159-166) to choose between onShuffleTap and onRepeatTap. The numeric indirection forces readers to reconstruct loop order to know which tag is which, when the two buttons are already stored properties.

**建议**: Drop the tags and dispatch on identity (`if sender === shuffleButton { onShuffleTap() } else if sender === repeatButton { onRepeatTap() }`), or use per-button UIAction handlers.

<details><summary>验证记录</summary>

Confirmed: NowPlayingQueueHeaderCell.swift lines 79-85 assign button.tag = tag + 1 in an enumerated loop and handleTap switches on sender.tag cases 1/2 (lines 159-166) to route to onShuffleTap/onRepeatTap, with a dead default branch — even though shuffleButton and repeatButton are stored properties. A repo-wide grep shows this is the ONLY tag-based dispatch in the codebase; sibling NowPlaying components (NowPlayingTransportView, NowPlayingCompactTransportView, PlayerControlButton) all use dedicated per-button selectors. AGENTS.md does not endorse tag dispatch and its style guidance (intention-revealing code, named constants over magic numbers) leans against it. The suggested fix (identity comparison or per-button handlers) would match the module's dominant convention. Impact is purely cosmetic in a two-button cell, so severity stays low.

</details>

### [LOW] Identical button-configuration boilerplate repeated across all four control buttons

`MuseAmp/Interface/NowPlaying/Components/TransportButtons/PlayPausePlayerControlButton.swift:7` · seams-duplication

**问题**: PlayPausePlayerControlButton (lines 7-17), NextPlayerControlButton, PreviousPlayerControlButton, and FavoritePlayerControlButton each repeat the same 10-line block: plain configuration, white baseForegroundColor, zero contentInsets, symbol configuration differing only in pointSize, white tintColor, setImage, accessibilityLabel. Three of them also repeat the `alpha = isEnabled ? 1 : 0.1` disabled treatment in bindState — and 0.1 already has a name (NowPlayingTransportView.Layout.unavailableTransportButtonAlpha) that none of them use.

**建议**: Add a `configureSymbolAppearance(systemName:pointSize:accessibilityLabel:)` helper and a `setAvailable(_:)` helper (using Layout.unavailableTransportButtonAlpha) on the PlayerControlButton base class, and call them from the subclasses.

<details><summary>验证记录</summary>

Verified: all four PlayerControlButton subclasses repeat the identical ~10-line configuration block (plain config, white baseForegroundColor, zero contentInsets, symbol config differing only in pointSize 30/20/20/16, white tintColor, setImage, accessibilityLabel). Three subclasses (Next, Previous, Favorite) hardcode `alpha = isEnabled ? 1 : 0.1` in bindState while NowPlayingTransportView.Layout.unavailableTransportButtonAlpha (= 0.1) exists and is already used by the sibling NowPlayingRoutePickerContainerView for the same disabled treatment — a genuine inconsistency and drift hazard. AGENTS.md does not endorse the duplication; the suggested helpers on the existing PlayerControlButton base class fit the repo's existing pattern (the base class already centralizes tap wiring, haptics, and cancellables), so the fix would not read against local convention. Impact is cosmetic clarity, so severity stays low.

</details>

### [LOW] makeShowLyricsAction/makeShowPlaybackQueueAction duplicated verbatim across both controllers

`MuseAmp/Interface/NowPlaying/Controller/NowPlayingCompactController+Playback.swift:93` · seams-duplication

**问题**: Lines 93-109 are byte-identical to NowPlayingRelaxedController+Playback.swift:75-91 (same titles, SF symbols, and controlIslandViewModel.setContentSelector bodies), and the surrounding updateTransportSongMenu construction is also largely repeated. Any wording or symbol change must now be made twice.

**建议**: Hoist both factories (and the shared songContextMenuProvider menu assembly) into an extension on NowPlayingPlaybackShellController where Self: UIViewController, since both controllers already conform and own controlIslandViewModel.

<details><summary>验证记录</summary>

The duplication is verified byte-for-byte: makeShowLyricsAction/makeShowPlaybackQueueAction in NowPlayingCompactController+Playback.swift:93-109 are identical to NowPlayingRelaxedController+Playback.swift:75-91 (same localized titles, SF symbols, setContentSelector bodies). The suggested hoist target already exists and is the module's established convention — NowPlayingPlaybackShellController.swift:55 has an `extension NowPlayingPlaybackShellController where Self: UIViewController` block holding shared logic for both controllers, controlIslandViewModel is a base NowPlayingShellController requirement, and both controllers conform. So the fix would make the code read MORE like the surrounding repo, not less. AGENTS.md does not endorse the duplication. However, severity is overstated: only the two small factories are pure duplication; the surrounding updateTransportSongMenu assemblies differ meaningfully (Compact adds a favorite/like section and targets pageViewController vs relaxedTransportView), and no drift has occurred. Adjusted to low (cosmetic maintenance, two adjacent files, trivial to sync).

</details>

### [LOW] Empty lifecycle overrides and empty deinit are dead code

`MuseAmp/Interface/NowPlaying/Controller/NowPlayingCompactController.swift:104` · function-design

**问题**: viewDidAppear (lines 104-106) and viewDidLayoutSubviews (lines 108-110) only call super, and `deinit {}` (line 127) is empty. The same pattern appears in NowPlayingRelaxedController.swift (viewDidLayoutSubviews 108-110, deinit 139), LyricTimelineView.swift layoutSubviews (183-185), and EdgeFadeBlurView.swift layoutSubviews (28-30). Each one signals customization that does not exist.

**建议**: Delete the no-op overrides and empty deinits in all four files.

<details><summary>验证记录</summary>

Verified all cited locations: NowPlayingCompactController.swift has viewDidAppear (104-106) and viewDidLayoutSubviews (108-110) that only call super plus an empty deinit (127); NowPlayingRelaxedController.swift mirrors this (108-110, 139); LyricTimelineView.swift (actually at Interface/NowPlaying/LyricTimeline/, lines 183-185) and EdgeFadeBlurView.swift (28-30) have layoutSubviews overrides that only call super. Refutation failed on all fronts: (1) repo convention is the opposite — every other viewDidAppear/viewDidLayoutSubviews/layoutSubviews override in the codebase (~15 occurrences) does real work, so these no-ops are anomalies that falsely signal customization; (2) AGENTS.md contains no endorsement of placeholder overrides or empty deinits; (3) removal is behaviorally identical (super-only overrides and empty deinit are semantically equivalent to absence; no protocol requires them). EdgeFadeBlurView's traitCollectionDidChange is a deliberate super-skip with a comment, but that is not part of the finding. Severity remains low: cosmetic clarity issue, does not actively mislead about runtime behavior.

</details>

### [LOW] No-op weak-self wrapper around onToggleShuffle diverges from the relaxed controller

`MuseAmp/Interface/NowPlaying/Controller/NowPlayingCompactController.swift:140` · seams-duplication

**问题**: installQueueActionHandlers wraps only onToggleShuffle in `{ [weak self] in guard self != nil else { return }; onToggleShuffle() }` (lines 140-143) while forwarding the other six handlers directly — and NowPlayingRelaxedController.swift:150-159 forwards all seven directly. The wrapper adds no behavior (the closures built in bindQueueSectionActions already capture self weakly) and makes a reader hunt for a difference that does not exist.

**建议**: Pass onToggleShuffle straight through like the other handlers, matching the relaxed controller.

<details><summary>验证记录</summary>

Confirmed: NowPlayingCompactController.installQueueActionHandlers wraps only onToggleShuffle in a [weak self] guard-nil wrapper while passing the other six handlers directly, whereas NowPlayingRelaxedController forwards all seven directly. The wrapper is provably a no-op: the only caller, bindQueueSectionActions in NowPlayingShellController.swift:91, already builds onToggleShuffle as { [weak self] in self?.shuffleQueueOnce() } where self is the same controller instance, so the closure already does nothing after dealloc. The asymmetry misleads readers into searching for a nonexistent behavioral difference. No AGENTS.md rule or local convention endorses the wrapper; the dominant convention (relaxed controller plus the six sibling handlers) is direct pass-through, so the suggested fix aligns with repo style. Cosmetic only, no functional risk.

</details>

### [LOW] Stray empty MARK sections

`MuseAmp/Interface/NowPlaying/Controller/NowPlayingRelaxedController.swift:65` · mechanical-consistency

**问题**: Back-to-back `// MARK: - Right Panel` and `// MARK: - Layout Containers` (lines 65-67) precede a single property, and `// MARK: - Background Setup` (line 162) is immediately followed by `// MARK: - Content Layout` with no members between them — leftover section headers from moved code that now mislabel the file's structure in the Xcode jump bar.

**建议**: Delete the empty MARK headers and keep only those that label actual sections.

<details><summary>验证记录</summary>

Verified in NowPlayingRelaxedController.swift: lines 65-67 have back-to-back `// MARK: - Right Panel` / `// MARK: - Layout Containers` preceding a single property, and lines 162-164 have `// MARK: - Background Setup` immediately followed by `// MARK: - Content Layout` with no members between (installBackgroundView is defined in a protocol extension, not this file). AGENTS.md does not endorse empty MARK headers; the file's own dominant convention is MARKs labeling real sections, so removing the empty/stale headers aligns with local style. Cosmetic jump-bar mislabeling only.

</details>

### [LOW] Dead private Animation constants enum

`MuseAmp/Interface/NowPlaying/LyricSheet/LyricSelectionSheetViewController.swift:13` · named-constants

**问题**: The private `enum Animation { duration = 1.0, damping = 1.05, initialVelocity = 0.75 }` (lines 13-17) is never referenced anywhere in the file — the controller performs no animations of its own. It is leftover scaffolding that suggests spring behavior that does not exist.

**建议**: Delete the unused Animation enum.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/NowPlaying/LyricSheet/LyricSelectionSheetViewController.swift: the private enum Animation (lines 13-17) is declared but none of its members (duration, damping, initialVelocity) are referenced anywhere in the file, and being private it is unreachable from other files. The controller performs no custom animations (only system `animated:` parameters), so the enum is dead code suggesting spring behavior that does not exist. AGENTS.md does not endorse keeping unused constants; deleting it is a safe, convention-consistent cleanup. Severity stays low: it is cosmetic dead code, mildly misleading but unlikely to breed bugs.

</details>

### [LOW] Haptic generator created on demand instead of stored as a property

`MuseAmp/Interface/NowPlaying/LyricSheet/LyricSelectionSheetViewController.swift:163` · repository-conventions

**问题**: `UINotificationFeedbackGenerator().notificationOccurred(.success)` is constructed inline at fire time (line 163), and the same on-demand pattern appears in the lyric copy action (LyricTimelineView+Actions.swift:57). AGENTS.md Cell Rules require haptic generators to be stored as instance properties, not created on demand — a convention every other haptic site in this scope follows (e.g. NowPlayingQueueHeaderCell.buttonFeedbackGenerator, ProgressTrackView.feedbackGenerator).

**建议**: Store a `private let copyFeedbackGenerator = UINotificationFeedbackGenerator()` on the controller (and on LyricTimelineView for the copy action), gated #if os(iOS) where the type is shared.

<details><summary>验证记录</summary>

Confirmed: both sites create UINotificationFeedbackGenerator inline at fire time (LyricSelectionSheetViewController.swift:163 and LyricTimelineView+Actions.swift:57, in LyricTimeline/ not Components/ — minor path slip, substance accurate). AGENTS.md line 142 explicitly requires haptic generators be stored as instance properties, not created on demand; though placed under Cell Rules, every other haptic site in the repo follows it including non-cell views (NowPlayingQueueHeaderCell, PlayerControlButton, ProgressTrackView), making property storage the dominant deliberate convention. These are the only two inline-creation sites repo-wide. The suggested fix (stored generator, #if os(iOS) gated where needed) reads exactly like neighboring code and avoids the missed-prep-window haptic latency issue. Severity stays low: it's a convention/consistency issue with at most an occasionally weak haptic, no correctness impact.

</details>

### [LOW] Parameter name typo: isUserInitialed

`MuseAmp/Interface/NowPlaying/LyricTimeline/LyricTimelineView+Delegate.swift:126` · naming

**问题**: `func focusCurrentLine(isUserInitialed: Bool)` (line 126, also call site LyricTimelineView+Binding.swift:113) misspells "isUserInitiated". The log line inside the same function even prints the correct spelling: `"focusCurrentLine activeRow=... userInitiated=\(isUserInitialed)"` (line 140), so the API and its diagnostics disagree.

**建议**: Rename the parameter to isUserInitiated at the declaration and both call sites.

<details><summary>验证记录</summary>

Confirmed: LyricTimelineView+Delegate.swift:126 declares `focusCurrentLine(isUserInitialed: Bool)` with the misspelling, and line 140 logs the correctly spelled `userInitiated=...` from the same parameter, so API and diagnostics disagree as claimed. The sole call site is LyricTimelineView+Binding.swift:113. Grep shows no other occurrences, so it is an isolated typo, not a module convention; nothing in the project instructions endorses it, and Apple's own `.userInitiated` terminology matches the suggested fix. Rename is local and safe. Severity is low: cosmetic clarity issue that does not actively mislead readers about behavior.

</details>

### [LOW] Dead stored properties: displayedArtworkURL and an unused cancellables set

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingAvatarSectionView.swift:8` · state-modeling

**问题**: `private var displayedArtworkURL: URL?` (line 8) is never read or written anywhere, and the outer class's `private var cancellables = Set<AnyCancellable>()` (line 9) is never stored into — the only Combine subscription lives in the nested NowPlayingArtworkImageView, which has its own set (line 41). Both properties imply state tracking that does not exist.

**建议**: Delete both properties (and the then-unneeded Combine import usage on the outer type).

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/NowPlaying/Sections/NowPlayingAvatarSectionView.swift: `displayedArtworkURL` (line 8) appears only at its declaration repo-wide (grep confirms no reads/writes), and the outer class's `cancellables` (line 9) is private and never stored into — the sole `.store(in: &cancellables)` at line 52 belongs to the nested private NowPlayingArtworkImageView with its own set at line 41. AGENTS.md does not endorse dead state; its Property Rules section ("Avoid unnecessary optionals", "Do not introduce stored properties to track state that is already available") actually supports removal. The per-class cancellables rule applies only when subscriptions exist. Minor correction to the suggestion: `import Combine` cannot be removed since the nested class in the same file uses it, but deleting the two dead properties is correct and clarifying. Severity stays low — cosmetic dead state that mildly implies tracking that doesn't exist, no bug risk.

</details>

### [LOW] +DataSource filename mislabels a snapshot-mapping helper

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingListSectionView+DataSource.swift:12` · file-organization

**问题**: In this codebase a +DataSource suffix means UITableView/UICollectionView data-source conformance (the table data source for this view actually lives in superclass NowPlayingQueueSectionView). This file contains only makeQueueSnapshot — a PlaybackTrack-to-AMNowPlayingQueueSnapshot mapping wrapper — so the responsibility-based filename points readers to the wrong place.

**建议**: Rename the file to NowPlayingListSectionView+Snapshot.swift (or fold the 15-line helper back into NowPlayingListSectionView.swift).

<details><summary>验证记录</summary>

Confirmed: NowPlayingListSectionView+DataSource.swift contains only makeQueueSnapshot, a PlaybackTrack-to-AMNowPlayingQueueSnapshot mapping wrapper used once (NowPlayingListSectionView.swift:61). The actual UITableViewDataSource conformance lives in superclass NowPlayingQueueSectionView (conformance at line 23, dataSource assignment at 157, MARK at 651). The finding slightly overstates by claiming an in-repo "+DataSource" convention — this is the only +DataSource file in the codebase — but AGENTS.md explicitly mandates responsibility-based extension naming (+Layout, +Actions, +Table, etc.), and in UIKit "+DataSource" universally connotes table/collection data-source methods, so the name does misdirect readers toward the wrong responsibility. The suggested rename to +Snapshot.swift (or inlining the 15-line single-use helper) conforms to AGENTS.md conventions and improves clarity. Impact is minor: the file is 27 lines, so the misdirection costs seconds, not bugs.

</details>

### [LOW] Trailing guard exists only to gate a misleading 'snapshot start' log

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingListSectionView.swift:76` · function-design

**问题**: In updateQueue, `guard update.appliedSnapshot else { return }` (lines 76-78) is followed solely by an AppLog.info reading "queue snapshot start ..." (lines 80-83) — but updateQueuePresentation already applied the snapshot synchronously on line 66, so the "start" message fires after the work completed and the guard protects nothing else. Readers of the logs and of the code both get the wrong picture of ordering.

**建议**: Fold the information into the existing "queue refresh apply" log (which already records identity/content/player change flags) and delete the trailing guard, or move the start log before updateQueuePresentation.

<details><summary>验证记录</summary>

Verified in NowPlayingListSectionView.swift lines 56-84: updateQueuePresentation (line 66) applies the table snapshot synchronously (applyQueueSnapshot runs inline in NowPlayingQueueSectionView lines 264-269), yet the trailing guard at lines 76-78 gates only a "queue snapshot start" AppLog.info (lines 80-83) with nothing after it. The paired "queue snapshot finished" log fires inside didApplyQueueSnapshot, which runs synchronously for the first-load and content-only paths — so logs can show "finished" before "start", and even in the batch path the reload work has already executed when "start" prints. The guard-then-log-then-end structure misrepresents both control flow and log ordering. AGENTS.md's Logging Rules do not endorse this pattern, and surrounding code (the accurate "queue refresh apply" log at lines 71-74) follows correct ordering, so the fix would match repo conventions. Impact is diagnostics-only; severity low.

</details>

### [LOW] Magic empty-cell height and thrice-repeated highlight color literal

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingQueueSectionView.swift:197` · named-constants

**问题**: heightForItemIdentifier returns a bare `72` for the empty-queue row (line 197) while every sibling height is a named Layout constant (sectionHeaderHeight, footerRowHeight, queueRowHeight). `UIColor.white.withAlphaComponent(0.08)` is repeated three times as the row-highlight color (lines 327, 435, 446) with no named constant, so the context-menu preview color and the current-row background can silently drift apart.

**建议**: Add `Layout.emptyQueueRowHeight: CGFloat = 72` and a `Palette.rowHighlightBackground` constant (matching the per-view Palette convention used by NowPlayingQueueHeaderCell) and use them at all four sites.

<details><summary>验证记录</summary>

Verified directly in NowPlayingQueueSectionView.swift: heightForItemIdentifier (line 189-203) returns bare `72` for the empty-queue identifier while every other branch uses a named Layout constant, breaking the file's own deliberate Layout-enum convention (which already holds nine named CGFloat constants). The literal UIColor.white.withAlphaComponent(0.08) is repeated at lines 327, 435, and 446; the three sites are semantically coupled — the context-menu targeted-preview background must match the current-row highlight background, so drift would produce a visible glitch. The proposed fix (Layout.emptyQueueRowHeight + a per-view Palette constant) matches the established per-view Palette convention in sibling NowPlaying components (NowPlayingQueueHeaderCell, NowPlayingTransportView), so it improves clarity without reading unlike the repo. AGENTS.md does not endorse inline literals and contains no rule the fix would violate. Severity stays low: this is cosmetic/drift-risk clarity, not an existing bug.

</details>

### [LOW] Dead Layout constants duplicating NowPlayingQueueHeaderCell's own values

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingQueueSectionView.swift:30` · named-constants

**问题**: `Layout.headerControlSize = 40` and `Layout.headerActionsWidth = 92` (lines 30-31) are referenced nowhere in the repo (verified by grep). The live copies are NowPlayingQueueHeaderCell.Layout.controlSize = 40 / actionsWidth = 92 (NowPlayingQueueHeaderCell.swift:9-10). Keeping a dead second source of truth invites someone to edit the wrong one.

**建议**: Delete headerControlSize and headerActionsWidth from NowPlayingQueueSectionView.Layout; the header cell owns its dimensions.

<details><summary>验证记录</summary>

Verified: NowPlayingQueueSectionView.Layout.headerControlSize (40) and headerActionsWidth (92) at lines 30-31 are referenced nowhere in the repo (grep across all Swift files returns only the definition lines, and a full read of the file shows no use). The actual header dimensions live in NowPlayingQueueHeaderCell's own private Layout enum (controlSize = 40, actionsWidth = 92), which cannot reference the section view's constants since it is private to the cell. These are dead duplicate constants that could mislead a maintainer into editing values with no effect. Deleting them matches the module's convention (each view/cell owns its Layout enum) and violates nothing in the project guidelines. Severity remains low: cosmetic dead code with mild mislead potential, no bug bred.

</details>

### [LOW] 741-line single-type file ignores the repo's responsibility-split convention

`MuseAmp/Interface/NowPlaying/Sections/NowPlayingQueueSectionView.swift:741` · file-organization

**问题**: One type body contains layout constants, item-identifier scheme, snapshot application, change detection, cell configuration, UITableViewDataSource, UITableViewDelegate, context-menu construction, anchored auto-scroll math, and programmatic-scroll throttling. Sibling LyricTimelineView splits the same responsibilities into +Binding/+Actions/+Delegate files, and AGENTS.md mandates splitting by responsibility (XxxView.swift plus +Table/+Actions extensions). The top-level struct NowPlayingQueuePresentationUpdate also lives in this file rather than its own (filename = export).

**建议**: Split into NowPlayingQueueSectionView.swift (state + snapshot application), +DataSource.swift, +ContextMenu.swift, and +Scrolling.swift, and move NowPlayingQueuePresentationUpdate to its own file (or fold it away during the diffable migration).

<details><summary>验证记录</summary>

Verified: the file is exactly 741 lines, one type body holding Layout constants, ItemIdentifier scheme, snapshot application, change detection (updateQueuePresentation), cell configuration, full UITableViewDataSource and UITableViewDelegate implementations, context-menu construction, anchored auto-scroll math, and programmatic-scroll throttling, plus the top-level NowPlayingQueuePresentationUpdate struct at lines 4–20. AGENTS.md (lines 118–119) mandates responsibility-based extension splits, and the dominant local convention follows it: sibling NowPlayingListSectionView+DataSource.swift exists in the same Sections/ folder, and LyricTimelineView is split into +Actions/+Binding/+Delegate. The suggested split (+DataSource, +ContextMenu, +Scrolling) matches repo style and violates nothing. Severity adjusted to low: each method is locally clear and the monolith does not actively mislead or hide state bugs; the harm is navigation burden and inconsistency with neighboring files, i.e., cosmetic clarity.

</details>

### [LOW] updateInterfaceSuspensionState takes an inout parameter shadowing the protocol property of the same name

`MuseAmp/Interface/NowPlaying/Support/NowPlayingLifecycleShellController.swift:29` · function-design

**问题**: `func updateInterfaceSuspensionState(_ suspended: Bool, isInterfaceSuspended: inout Bool)` exists only because NowPlayingPlaybackShellController declares `var isInterfaceSuspended: Bool { get }` (read-only), so the mixin cannot write it. Each conformer therefore defines setInterfaceSuspended that passes `&isInterfaceSuspended` back into the helper (NowPlayingCompactController.swift:154, NowPlayingRelaxedController.swift:226). The inout parameter named identically to the protocol property makes the data flow needlessly hard to follow.

**建议**: Change the protocol requirement to `var isInterfaceSuspended: Bool { get set }` (conformers already store it), let the default implementation assign it directly, and delete the inout parameter plus the per-controller setInterfaceSuspended forwarding.

<details><summary>验证记录</summary>

Verified: the inout helper, the read-only protocol requirement, and the per-controller setInterfaceSuspended forwarders all exist as cited. The shadowing is real, and the same protocol already uses { get set } for lastPresentedTrackID/lastPresentedArtworkURL with direct assignment from the protocol extension, so the suggested fix aligns with (not against) the module's dominant convention. The private(set) encapsulation counter-argument fails because sibling mixin-mutated properties are already plain var. AGENTS.md does not endorse the inout pattern. Additionally, inout copy-in/copy-out means callees inside the helper would observe a stale self.isInterfaceSuspended — a latent trap, though no current callee reads it, so severity remains low.

</details>

### [LOW] refreshControlIslandContent(animated:) parameter is dead across the whole hierarchy

`MuseAmp/Interface/NowPlaying/Support/NowPlayingPlaybackShellController.swift:184` · function-design

**问题**: The protocol requires `func refreshControlIslandContent(animated: Bool)` (line 52) but the only implementation is the default `func refreshControlIslandContent(animated _: Bool)` (line 184) which ignores it; neither NowPlayingCompactController nor NowPlayingRelaxedController overrides it. Call sites pass `animated: false` (bindContentSelector:84, NowPlayingLifecycleShellController.swift:45) implying a choice that does not exist.

**建议**: Drop the parameter from the protocol requirement, default implementation, and call sites, or implement the animated behavior if it was intended.

<details><summary>验证记录</summary>

Verified in /Users/qaq/Documents/GitHub/MuseAmp/MuseAmp/Interface/NowPlaying/Support/NowPlayingPlaybackShellController.swift: protocol requires refreshControlIslandContent(animated: Bool) (line 52); the sole implementation is the default extension method at line 184 which discards the parameter (animated _: Bool); repo-wide grep confirms no controller overrides it, and both call sites (line 84 and NowPlayingLifecycleShellController.swift:45) pass animated: false. The parameter is dead across the whole hierarchy. The 'deliberate extension-point' defense fails: sibling hooks in the same protocol (animateTrackTransitionIfNeeded, refreshPlayingContent) are each overridden somewhere and receive dynamic animation values, so the local convention is that hook parameters are actually consumed. AGENTS.md contains nothing endorsing unused parameters; dropping it would align the file with the surrounding module rather than diverge from it. Severity stays low: it is a cosmetic clarity issue — call sites imply an animation choice that does not exist, but no bug is bred today.

</details>

### [LOW] NowPlayingPlaybackShellController extension misfiled in NowPlayingShellController.swift

`MuseAmp/Interface/NowPlaying/Support/NowPlayingShellController.swift:145` · file-organization

**问题**: Lines 145-172 extend `NowPlayingPlaybackShellController` (bindCleanSongTitlePreference) inside the file named for NowPlayingShellController, which already hosts four other declarations (NowPlayingShellController, NowPlayingQueueActionPresenting plus two conformance extensions, NowPlayingQueueShellController with its default implementation). The repo's convention is filename = export with Type+Feature.swift extensions; a maintainer looking for playback-shell behavior in NowPlayingPlaybackShellController.swift will not find this binding.

**建议**: Move the bindCleanSongTitlePreference extension into NowPlayingPlaybackShellController.swift, and consider splitting the NowPlayingQueueActionPresenting protocol + conformances into their own file.

<details><summary>验证记录</summary>

Verified: NowPlayingShellController.swift:145-172 extends NowPlayingPlaybackShellController with bindCleanSongTitlePreference, while the dedicated NowPlayingPlaybackShellController.swift in the same Support directory hosts the protocol and ALL of its sibling bind* methods (bindContentSelector, bindQueueSnapshot, bindPlaybackSnapshot, bindPlaybackTime) in an identically-constrained extension. Grep confirms these are the only two extension sites for the protocol. Every other Support file (Artwork/Lyric/Lifecycle/Transport shell controllers) only extends protocols declared in the same file, so this is the lone cross-file stray and a maintainer scanning NowPlayingPlaybackShellController.swift for bindings will miss it. The primary fix (move the extension into NowPlayingPlaybackShellController.swift) matches both AGENTS.md's responsibility-split rule and the module's dominant convention. Caveat: the secondary suggestion to split NowPlayingQueueActionPresenting + conformances into their own file should be dropped — bundling a feature's Presenting protocol with its shell protocol in one file is the deliberate local convention (see NowPlayingArtworkShellController.swift hosting NowPlayingArtworkShellPresenting). Severity stays low: discoverability nit only, no behavioral or misleading-logic impact.

</details>

### [LOW] Write-only Presentation.shouldAnimatePlaybackStateChange and uncalled content(for:)

`MuseAmp/Interface/NowPlaying/ViewModel/ControlIsland/NowPlayingControlIslandViewModel.swift:21` · state-modeling

**问题**: `shouldAnimatePlaybackStateChange` is computed and stored on every apply(snapshot:) (NowPlayingControlIslandViewModel+Playback.swift:21) but read nowhere in app code or tests (repo-wide grep finds only the declaration, init parameter, and assignment). Similarly `content(for:)` (+Playback.swift:26-28) has zero call sites. Both inflate the Presentation API and make readers hunt for consumers that do not exist.

**建议**: Remove shouldAnimatePlaybackStateChange from Presentation and delete content(for:); reintroduce them only when a consumer exists.

<details><summary>验证记录</summary>

Verified by repo-wide grep: shouldAnimatePlaybackStateChange appears only as declaration, init parameter, init assignment, and the computation in apply(snapshot:) — no reader in app code or tests (tests only inspect presentation.content.routeName/routeSymbolName). content(for:) has zero call sites and just forwards to NowPlayingContentMapper.makeContent(from:). The clarity harm is real because the sibling flag shouldAnimateTransition IS consumed (NowPlayingPlaybackShellController.swift:168,171,173), inviting readers to hunt for a nonexistent consumer of the write-only twin. AGENTS.md does not endorse keeping unused API; its Property Rules lean the other way. The suggested removal is consistent with repo style. Severity low: cosmetic dead-code clutter, no behavioral risk.

</details>

### [LOW] Dead elapsedText/remainingText helpers while views hand-roll the same formatting

`MuseAmp/Interface/NowPlaying/ViewModel/Playback/AMNowPlayingContent.swift:37` · seams-duplication

**问题**: `elapsedText` (line 37) and `remainingText` (line 41) have no call sites anywhere (verified by grep across all targets); `progress` (line 45) is referenced only by a test. Meanwhile NowPlayingPlaybackTimeRowView re-implements the identical formatting inline (`"-\(formattedPlaybackTime(max(effectiveDuration - currentTime, 0)))"`, NowPlayingPlaybackTimeRowView.swift:70-71) and ProgressTrackView re-implements the clamped-ratio computation (ProgressTrackView.swift:73-77).

**建议**: Delete the unused computed properties (keeping `progress` only if the test coverage is deemed valuable), or — if the helpers are meant to be canonical — extract the elapsed/remaining/ratio formatting into shared free helpers next to formattedPlaybackTime and use them from both views.

<details><summary>验证记录</summary>

Verified: elapsedText and remainingText in AMNowPlayingContent.swift (lines 37-43) have zero call sites anywhere in MuseAmp, MuseAmpTV (no symlink to this file), or tests; progress (line 45) is used only by NowPlayingContentMapperTests.swift:56. NowPlayingPlaybackTimeRowView.swift:70-71 re-implements the identical elapsed/remaining formatting and ProgressTrackView.swift:73-77 re-implements the clamped ratio. The duplication framing is slightly overstated — those views consume raw TimeIntervals from playbackTimeSubject per the AGENTS.md Combine rules, so they legitimately cannot route through the content struct, and formattedPlaybackTime() is already the shared canonical helper — but that makes the struct's helpers permanently unreachable convenience accessors, i.e. real dead code. Deleting them (keeping progress for its test) improves clarity and violates no AGENTS.md convention. Cosmetic, so severity stays low.

</details>

---

## 被对抗验证驳回的发现（供参考）

- [clarity] MuseAmp/Application/AppEnvironment+Bootstrap.swift:20 — Bootstrap creates parallel APIClient and EmbeddedMetadataReader instances that diverge from AppEnvironment's
- [clarity] MuseAmp/Application/AppEnvironment+Bootstrap.swift:46 — Async initializeDatabaseManager wrapper relies on invisible executor hopping
- [clarity] MuseAmp/Application/AppPreferences.swift:29 — defaultAPIBaseURL is a sentinel placeholder, not a default
- [clarity] MuseAmp/Extension/Extension+Bundle.swift:11 — UIImage constant homed on Bundle with a name that overpromises
- [clarity] MuseAmp/Extension/Extension+UITableView.swift:11 — Asymmetric inout-threaded header/footer sizing API
- [clarity] MuseAmp/Backend/Library/AudioFileImporter.swift:435 — Log category string literal "AudioFileImporter" hand-repeated three times in detached task
- [clarity] MuseAmp/Backend/Playback/PlaybackController.swift:29 — itemCache is a grow-only unbounded dictionary cache
- [clarity] MuseAmp/Backend/Playlist/PlaylistTransferDocument.swift:60 — Document format version literal 1 duplicated
- [clarity] MuseAmp/Backend/Lyrics/LyricsReloadService.swift:64 — Two conflicting cache-persistence policies for the same LyricsCacheStore
- [clarity] MuseAmp/Backend/Sync/SyncServer.swift:529 — Repeated 64 * 1024 chunk-size literal not hoisted next to maxRequestBufferSize
- [clarity] MuseAmp/Backend/Sync/SyncBonjourBrowser.swift:209 — NetServiceResolver hand-rolls an optional-continuation once-guard instead of the shared helpers
- [clarity] MuseAmp/Interface/Common/MuseAmpImageView/MuseAmpImageView+Preview.swift:79 — PreviewCoordinator models one lifecycle with three independent optionals
- [clarity] MuseAmp/Interface/Common/MuseAmpImageView/MuseAmpImageView.swift:30 — Assigning onImageLoaded has a hidden replay side effect

---

# 附录：未完成对抗验证的发现（finder 原始产出，从缓存挖掘）

以下发现因 token 限额未走完 trace/impact 验证流程，可信度低于正文，使用前请人工核对。

## A. 数据完整性（integrity）— 全部维度

### 维度: downloads

#### [HIGH] Changing Max Concurrent Downloads cancels every in-flight download, destroys their resume data, and consumes the shared retry budget

`MuseAmp/Backend/Downloads/DownloadManager+Network.swift:23`

**问题**: observeConcurrencyChanges sets `DiggerManager.shared.maxConcurrentTasksCount = limit` whenever the user changes the setting (exposed live in DownloadsViewController.swift:222 while downloads run). Digger's didSet (DiggerManager.swift:48-54) calls `session.invalidateAndCancel()` and rebuilds the session, so every running download task fails with NSURLErrorCancelled (-999). Digger's notifyCompletionCallback compares only the error CODE against `DiggerError.downloadCanceled.rawValue == -999` (DiggerDelegate.swift:161, DiggerHelper.swift:17), which collides with NSURLErrorCancelled, so it DELETES the partial temp file — all downloaded bytes are discarded even though the requeue path relies on Range-header resume. Back in handleCompletion (DownloadManager+Digger.swift:133-151) each such cancel increments `retryCount` (shared with genuine failure retries) and after the counter reaches 3 the task is permanently marked .failed. Concretely: a user downloading a large file who adjusts the concurrency stepper 3-4 times loses all partial progress on each change and ends with the download marked failed.

**建议**: Do not mutate `DiggerManager.shared.maxConcurrentTasksCount` while tasks are executing — defer the change until activeCount == 0 (e.g. apply it in processNextIfNeeded the same way syncDiggerHTTPHeadersIfNeeded is gated), or stop tracking these self-inflicted cancellations against the 3-retry budget.

#### [HIGH] cancelTask suspends the Digger task instead of cancelling; re-download of the same track wedges forever in .downloading

`MuseAmp/Backend/Downloads/DownloadManager.swift:313`

**问题**: DownloadManager.cancelTask calls `DiggerManager.shared.stopTask(for: url)`. In the pinned Digger revision (6bd5c7d, DiggerManager.swift:198-207), stopTask only SUSPENDS the URLSessionDataTask; the DiggerSeed stays in `diggerSeeds` forever (seeds are only removed in notifyCompletionCallback) and the partial temp file is never deleted. cancelTask also never removes `url` from `hasMarkedDownloading`/`diggerStartedURLs`. Failure sequence: (1) user cancels a downloading track (DownloadsViewController swipe/menu); (2) user re-downloads the same track in the same app session; (3) startResolving re-resolves the playback URL — SubsonicMusicService uses one `tokenSalt = UUID()` per instance (SubsonicMusicService.swift:20), so the URL string is byte-identical; (4) startDiggerDownload calls `DiggerManager.shared.download(with: url)` → `createDiggerSeed` finds the stale suspended seed and returns it early WITHOUT calling `downloadTask.resume()` (DiggerManager.swift:139-142). The new task is set to .downloading but no bytes ever flow: it never progresses, never completes, holds the screen-awake flag, and permanently occupies a concurrency slot. Since `AppPreferences.maxConcurrentDownloads` defaults to 1, the entire download queue is blocked until app relaunch, while the persisted DownloadJob stays in `.downloading`.

**建议**: In cancelTask, call `DiggerManager.shared.cancelTask(for: url)` (which cancels the URLSession task so Digger's completion path removes the seed and temp file) instead of stopTask, and also remove the url from `hasMarkedDownloading` and `diggerStartedURLs` — mirroring the cleanup done in retryFailed.

### 维度: rebuild-validation-gap

#### [HIGH] makeTrackRecord performs no readability, playability, or duration-sanity validation

`MuseAmp/Backend/Library/EmbeddedMetadataReader.swift:55`

**问题**: makeTrackRecord only calls `asset.load(.duration)` (line 55) and metadata loads. There is no check that (a) the file content is actually decodable as audio (e.g. AVAudioPlayer creation or an audio-track presence check via load(.tracks)), or (b) the duration is sane. Line 56 `max(CMTimeGetSeconds(duration), 0)` accepts 0 exactly, accepts arbitrarily huge values (no <24h cap), and passes NaN through unchanged (Swift `max(NaN, 0)` returns NaN because `0 >= NaN` is false), so an indefinite CMTime would persist NaN into the WCDB index. Concrete failure: a truncated faststart M4A (moov atom intact, mdat incomplete — the layout ExportMetadataProcessor and most encoders produce) loads its full nominal duration from the header, so during rebuild (LibraryScanner.swift:110) and ingest (DatabaseManager+Writes.swift:72) the corrupt file is indexed as a fully healthy track with full duration. Playback then fails or cuts off mid-track, and nothing ever re-validates it: subsequent rebuilds skip the file because size/mtime match the stored record (LibraryScanner.swift:92-95). Zero-duration files (metadata-only containers, renamed non-audio files with parseable headers) are likewise indexed and surface in the UI as 0:00 tracks. The kit-side fallbacks `metadata.durationSeconds ?? 0` (LibraryScanner.swift:119, DatabaseManager+Writes.swift:91) bake the same acceptance of 0 into the records.

**建议**: In makeTrackRecord (so iOS, tvOS, and AudioFileImporter all inherit it), after loading duration: verify the asset has at least one audio track (try await asset.load(.tracks) / asset.loadTracks(withMediaType: .audio) non-empty, or attempt AVAudioPlayer(contentsOf:) for local files), and throw EmbeddedMetadataReaderError for durationSeconds that is !isFinite, <= 1.0, or >= 86_400. Callers already have throw-handling paths (scanner catch, ingest throw), so invalid files become explicit failures instead of silently indexed records.

### 维度: playback-state

#### [HIGH] Restore trusts raw persisted index before track-ID match, shifting current track and losing playback position

`MuseAmp/Backend/Playback/PlaybackController+Resolution.swift:25`

**问题**: restoredCurrentIndex() checks `resolvedItems.indices.contains(session.currentIndex)` FIRST and returns the raw persisted index, before the exact match on `session.currentTrackID` (line 28). resolvedItems is the persisted queue minus any tracks that failed local resolution (resolvePlayableItems drops tracks whose audio file no longer exists, PlaybackController+Resolution.swift:80-86). Concrete sequence: a 10-track queue is persisted with currentIndex=5/currentTrackID=T5; the user deletes the downloaded file for the track at position 2 (e.g. via Songs delete while the queue is empty, or it lingers in history per the removeTracksFromQueue gap); on next launch resolvedItems has 9 entries with originalIndex [0,1,3,4,5,...], `indices.contains(5)` is true, so restoredIndex=5 which is resolvedItems[5] = the track originally at index 6 — NOT T5, even though T5 is present at resolved position 4. Then PlaybackController.swift:519 computes `restoredCurrentTime = restoredCurrentTrack.id == session.currentTrackID ? session.currentTime : 0` → 0. Net effect: restore silently switches the current track to the wrong song and discards the saved in-track position; refreshSnapshot(persistState: true) at PlaybackController.swift:536 then re-persists the corrupted state. The exact-match branch that would have recovered correctly is unreachable whenever the stale index happens to stay in range.

**建议**: Reorder the checks: try `resolvedItems.firstIndex(where: { $0.track.id == session.currentTrackID })` first; only fall back to the positional index if it also matches the persisted track ID (`resolvedItems[session.currentIndex].track.id == session.currentTrackID`), then nearest-playable. Alternatively match on originalIndex: `resolvedItems.firstIndex(where: { $0.originalIndex == session.currentIndex })`.

#### [HIGH] Restore picks current track by stale index before identity match

`MuseAmp/Backend/Playback/PlaybackController+Resolution.swift:25`

**问题**: restoredCurrentIndex() returns session.currentIndex whenever it is merely in range of the compacted resolvedItems array, before ever checking session.currentTrackID. resolvePlayableItems() drops tracks whose local file is gone (PlaybackController+Resolution.swift:80-86 throws localFileUnavailable), so the array shrinks. Scenario: persisted queue [A,B,C,D,E,...,J] with currentIndex=5 (track F). User deletes track B's file (or it was already gone), relaunches. resolvedItems = 9 items (A,C,D,...) so indices.contains(5) is true and index 5 is returned — but resolvedItems[5] is now track G, not F. F is present and playable at index 4 and exactly matches session.currentTrackID, but the exact-match branch on line 28 is never reached. Then PlaybackController.swift:519 computes restoredCurrentTime = 0 because the IDs mismatch. Net effect: restore silently positions playback on the wrong track AND discards the saved playback position, even though the correct track was fully restorable.

**建议**: Reorder the checks: first try resolvedItems.firstIndex(where: { $0.track.id == session.currentTrackID }) (ideally also matching originalIndex == session.currentIndex when duplicates exist), and only fall back to positional/nearest-playable lookup when no ID match exists.

### 维度: sync-transfer

#### [HIGH] Data race on connectionIDs/listener between stop() and connection handlers

`MuseAmp/Backend/Sync/SyncServer.swift:122`

**问题**: SyncServer is `@unchecked Sendable` and serializes all NWListener/NWConnection callbacks on the serial `queue` (listener.start(queue: queue) line 118, connection.start(queue: queue) line 221). `accept` writes `connectionIDs[identifier] = connection` (line 202) and the per-connection stateUpdateHandler calls `connectionIDs.removeValue(...)` (lines 211/216) — all on `queue`. But `stop()` (lines 122-134) is a nonisolated `async` method invoked from the @MainActor `SyncTransferSession.stopSender` via `await server?.stop()` (SyncTransferSession.swift:191). A nonisolated async method does NOT hop onto the serial `queue`; it runs on the Swift cooperative thread pool. So `stop()` iterates `connectionIDs.values` and calls `connectionIDs.removeAll()` (lines 129-132) and reads/nils `listener` (lines 124-127) concurrently with `queue`-scheduled callbacks that are simultaneously mutating the same Swift Dictionary / optional. Concurrent mutation of a Swift Dictionary from two threads is undefined behavior: it can crash (bad access) or corrupt the table. This fires in the common path: a receiver is mid-download (active connection callbacks on `queue`) when the user/app tears the sender down (stopSender -> stop()).

**建议**: Marshal all mutable-state access through the serial `queue`. Make `stop()` dispatch its body onto `queue` (e.g. `await withCheckedContinuation { c in queue.async { ...teardown...; c.resume() } }`), so connectionIDs/listener are only ever touched on that queue, matching accept() and the connection state handlers.

### 维度: rebuild-validation-gap

#### [HIGH] ingestAudioFile inspects after moveToLibrary; inspection failure strands the file at its final library path with no record and no cleanup

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:72`

**问题**: Line 63 moves the source file to its final library location, then line 72 calls dependencies.inspectAudioFile(moved.finalURL). If inspection throws (truncated/corrupt/unreadable download), ingestAudioFile rethrows with the file already at Audio/<albumID>/<trackID>.<ext>: there is no rollback, no removeItem, and upsertTracks (line 108) never runs. Concrete consequences: (1) LAN-transfer/import path — AudioFileImporter catches the error and deletes only its staging copy (AudioFileImporter.swift:289-291), but on re-import of the same track the orphan at the destination trips the fileExists check at AudioFileImporter.swift:238 and the import is reported as `.duplicate`, so the user re-transferring a song sees 'duplicate(s) skipped' while the track never appears in the library — a silent, persistent inconsistency curable only by a destructive prune rebuild (this applies to the tvOS transfer flow too, which uses the symlinked AudioFileImporter). (2) Download path — completeFinalization marks the job failed (DownloadManager+Persistence.swift:66-80) while the corrupt audio sits at the exact final path; if the inspection failure was transient, a later rebuild indexes that file as a normal track (with sourceKind .unknown instead of .downloaded, since the bootstrap closure hardcodes .unknown) while the failed DownloadJob still exists in the state store — the Downloads UI then shows a failed download for a track that is simultaneously present in the library, and tapping retry deletes the now-indexed file (cleanupLocalAudioArtifacts) leaving a dangling index row until re-ingest completes.

**建议**: Inspect before committing the move: call dependencies.inspectAudioFile on the source/staging URL first and only moveToLibrary after inspection succeeds; or wrap lines 69-107 so that on any thrown error the moved file is removed (or moved back to the source URL) before rethrowing, keeping disk state consistent with the index.

### 维度: import-move

#### [HIGH] Non-atomic move+index in ingestAudioFile: a failed index write strands the file and the importer then permanently misreports the track as 'duplicate'

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:63`

**问题**: ingestAudioFile moves the audio file to its final library location first (line 63, fileManager.moveToLibrary) and only afterwards runs fallible steps: FileManager.attributesOfItem (line 69, throws), dependencies.inspectAudioFile (line 72, a second full AVFoundation parse that throws), indexStore.track(byID:) (line 83) and indexStore.upsertTracks (line 108, WCDB write that throws on DB error/disk-full). If any of these throws, there is no compensation: the file stays at Audio/<albumID>/<trackID>.<ext> with no index row. The caller's cleanup in MuseAmp/Backend/Library/AudioFileImporter.swift:289 only removes the Incoming stagingURL, which no longer exists because moveToLibrary already consumed it. On every retry of the same import, AudioFileImporter.swift:238 finds the orphan at destURL via FileManager.fileExists and returns .duplicate before ever reaching ingest — the user is told the song is a duplicate while it is absent from the library, and it can never be imported again. Recovery only happens via a manual Settings 'rebuild database' / album-screen resync (rebuildIndex is never run at boot; the only call sites are SettingsViewController+Actions.swift and SongLibraryViewController+Actions.swift), so the inconsistency persists indefinitely for users who never trigger a rebuild.

**建议**: On any throw after moveToLibrary succeeds, remove moved.finalURL (and its now-empty album directory) as a compensating delete before rethrowing; alternatively, in AudioFileImporter.importSingleFile, treat 'file exists at destURL but no index row for trackID' as an orphan and re-ingest instead of returning .duplicate.

### 维度: index-state-store

#### [HIGH] ingestAudioFile leaks the old audio file when an existing track's relativePath changes, then rebuild flip-flops the row to the stale file

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:108`

**问题**: ingestAudioFile fetches `existing = try indexStore.track(byID: metadata.trackID)` (line 83) but never compares or removes `existing.relativePath` when it differs from `moved.relativePath` (different albumID — e.g. server-side album retag/rename then LAN re-transfer, which bypasses AudioFileImporter's title/artist/ALBUM/duration dup-key when the album name changed — or different file extension). `upsertTracks([record])` (line 108) replaces the row via trackID primary key, but the old file at the previous relativePath stays on disk. The next rebuildIndexFromDisk then finds the orphan file: it is not in the snapshot (its row was replaced), so it is re-inspected and upserted; INSERT OR REPLACE on the trackID PK (IndexStore.swift:166, TrackRow.swift:90) replaces the row again, now pointing back at the STALE file, while the freshly ingested file becomes the un-indexed orphan. Every subsequent rebuild flips the row between the two paths; one copy of the song is always invisible in the UI and the duplicate file is never reclaimed. deletedPaths (LibraryScanner.swift:153) never removes either file because both are always 'seen'.

**建议**: In ingestAudioFile, after computing moved.relativePath, if `existing != nil && existing.relativePath != moved.relativePath`, call fileManager.removeTrackFile(relativePath: existing.relativePath) so disk and index stay 1:1 per trackID. Additionally, rebuildIndexFromDisk should detect two on-disk files mapping to the same trackID and delete/quarantine the older one instead of silently letting INSERT OR REPLACE drop a row.

### 维度: rebuild-validation-gap

#### [HIGH] Any inspectAudioFile error permanently deletes the audio file and its index row — transient failures are indistinguishable from corruption

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:142`

**问题**: The catch at lines 142-148 treats every thrown error identically: the relativePath is marked invalid and, because the app always rebuilds with pruneInvalidFiles: true (SongLibraryIndexer.swift:33 — both the Settings rebuild and the casual Albums-tab 'Refresh Library' at SongLibraryViewController+Actions.swift:85 go through it), the file is removed from disk (line 146) and its existing index row is deleted via line 153 (`|| invalidRelativePaths.contains($0)`). inspectAudioFile throws not only for genuinely corrupt files but for transient conditions: permission/file-protection errors, the file momentarily absent or half-written because moveToLibrary's remove-then-move window (LibraryFileManager.swift:36-39) interleaves with the off-actor scan, AVFoundation resource pressure, or a file mid-copy via Files-app sharing. In all of those cases a perfectly valid, fully-downloaded song is irreversibly deleted from disk. Only the Settings flow warns 'Unreadable files will be removed.' (SettingsViewController+Actions.swift:100); the Albums-tab refresh says only 'Scanning saved songs...' yet performs the same destructive prune. Note also the inconsistency with the forceArtwork branch (lines 96-105), where an inspection failure on an unchanged file is merely logged — the same error class is fatal-to-the-file in one branch and benign in the other.

**建议**: Stop deleting files on arbitrary inspection errors. Classify errors: prune only structural path violations (already handled at lines 68-75) and files that fail a cheap deterministic corruption check (e.g. unreadable header on a direct FileHandle read) across more than one attempt; for AVFoundation errors, record the path as 'needs attention' / quarantine into a separate directory instead of removeItem, and never include transiently-unreadable existing tracks in the deletedPaths index purge.

### 维度: rebuild-scan

#### [HIGH] Any single inspectAudioFile failure permanently deletes the user's audio file and its index row

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:146`

**问题**: In the catch block at lines 142-149, every error thrown by dependencies.inspectAudioFile (line 110) is treated as 'file is invalid' and, because pruneInvalidFiles is true on every production rebuild (MuseAmp/Backend/Library/SongLibraryIndexer.swift:33 hardcodes pruneInvalidFiles: true, and the .pruneInvalidFiles command in DatabaseManager+Commands.swift:141 also passes true), the user's audio file is irreversibly removed from disk (line 146) and its index row is deleted via the invalidRelativePaths branch of deletedPaths (line 153). The production inspectAudioFile (AppEnvironment+Bootstrap.swift:83-122) is an AVFoundation pipeline: `try await asset.load(.duration)` and collectMetadataItems can throw for reasons unrelated to file corruption — transient resource pressure, an interrupted media-services daemon, or CancellationError if the enclosing Task is ever cancelled (AVAsset.load throws on cancellation; if a caller ever cancels the rebuild Task, every remaining file in the loop would be 'inspection failed' and mass-deleted). There is no retry, no quarantine, and no distinction between a structurally invalid path (lines 68-75, which is a legitimate prune) and a read error on a file that played fine yesterday. One flaky AVAsset load deletes a downloaded/imported song with no recovery besides re-downloading.

**建议**: Only prune files that are structurally invalid (bad relative path or .tmp suffix). On an inspectAudioFile error, log, leave the file on disk, and keep the existing index row (do not append to invalidRelativePaths; the path is already in seenRelativePaths so the row survives). Optionally track an 'uninspectable' count in RebuildResult and only delete a file after N consecutive failed inspections across rebuilds. Also explicitly rethrow CancellationError instead of treating it as file invalidity.

### 维度: caches

#### [HIGH] Orphan prune races with in-flight download finalization, deleting just-written artwork/lyrics caches

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:156`

**问题**: Download finalization writes caches BEFORE the track is committed to the index: DownloadManager+Digger.swift:225-275 spawns Task(priority: .utility) that (a) writes the artwork jpg via DownloadArtworkProcessor.cachedArtworkData (DownloadArtworkProcessor.swift:84 `try data.write(to: cacheURL)`) and the lyrics lrc via DownloadLyricsProcessor.cacheLyrics, (b) then runs two AVAssetExportSession passes (embedArtwork + embedExportMetadata, up to 30 s each), and only then (c) calls databaseManager.send(.ingestAudioFile) which upserts the index row. This Task is not on DatabaseActor, and rebuildIndexFromDisk is a nonisolated async function (runs off DatabaseActor under Swift 6 language mode, Package.swift swiftLanguageModes [.v6]), so a user-triggered rebuild (SongLibraryViewController+Actions.swift:80 refreshLibrary -> resyncSongLibrary -> rebuildIndex(pruneInvalidFiles: true)) can run concurrently with finalization. The rebuild reads validTrackIDs once (line 155) and then deletes every cache file whose ID is not in that set (line 156-157, CacheCoordinator.pruneOrphans:97-104). Any track in window (a)-(c) has cache files but no index row, so its artwork and lyrics are deleted as 'orphans'. Consequences: if embedArtwork failed/timed out (only a warning at DownloadArtworkProcessor.swift:42), the pruned jpg was the only artwork copy and the track ends up permanently artwork-less (subsequent rebuilds skip the file because size/mtime match, lines 92-95); if the lyrics file is pruned between the cache writes (line 238) and the read-back at DownloadManager+Digger.swift:240, lyrics come back nil and are never embedded or stored. The same TOCTOU exists against ingestAudioFile itself: trackIDs() read before the ingest upsert commits (DatabaseManager+Writes.swift:108) combined with file deletion after the ingest cache write (line 75) deletes a committed track's fresh caches.

**建议**: Make pruning tolerant of in-flight writes: skip cache files whose modification date is newer than the scan start time, and/or re-read indexStore.trackIDs() plus the active download-job trackIDs (stateStore downloads) immediately before deletion and exclude them. Alternatively serialize rebuild with ingest by isolating rebuildIndexFromDisk's commit+prune section on DatabaseActor.

### 维度: index-state-store

#### [HIGH] Transient metadata-inspection failure permanently deletes the user's audio file

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:146`

**问题**: In rebuildIndexFromDisk, when `dependencies.inspectAudioFile(fileURL)` throws (lines 142-149), the path is appended to invalidRelativePaths and, when pruneInvalidFiles is true, the audio file is deleted from disk (`try? FileManager.default.removeItem(at: fileURL)` line 146). The app ONLY ever rebuilds with pruneInvalidFiles=true: SongLibraryIndexer.syncLibrary (MuseAmp/Backend/Library/SongLibraryIndexer.swift:33) hardcodes `.rebuildIndex(pruneInvalidFiles: true, ...)` and is the sole rebuild entry (Refresh Library in SongLibraryViewController+Actions.swift:85 and Settings rebuild). inspectAudioFile is AVFoundation-based (`asset.load(.duration)` / metadata loading in EmbeddedMetadataReader.makeTrackRecord:54-57) and can throw transiently (media-services reset, I/O pressure, momentary file lock) for a perfectly valid file. Trigger path: any new or modified file (size/mtime mismatch at lines 92-94 forces re-inspection — e.g. after TrackArtworkRepairService rewrites a file, or after restoring the Audio folder with a fresh index.db where every file is re-inspected). One transient AVFoundation error during a refresh = the song file is irrecoverably deleted, plus its index row is dropped (line 153 includes invalidRelativePaths in deletedPaths) and its cached artwork/lyrics are pruned (lines 155-157). Even with pruneInvalidFiles=false the row deletion + cache prune still happen for a file that is still on disk.

**建议**: Distinguish structural invalidity (bad path shape, .tmp leftovers) from inspection errors. On inspectAudioFile failure, keep the file and its existing index row (or mark it for retry), never removeItem; only prune files that fail path validation. At minimum require N consecutive failures across rebuilds before destructive pruning.

### 维度: playback-state

#### [HIGH] Shuffled-mode removal of a pre-current permutation entry does not shift currentIndex, desyncing queue from engine and skipping a track

`MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:436`

**问题**: removeCanonicalIndex()'s shuffled branch (lines 435-443) rebuilds shufflePermutation via compactMap but, unlike the non-shuffled branch (line 445: `if canonicalIndex < ci { currentIndex = ci - 1 }`), never decrements currentIndex when the removed entry's permutation POSITION is before currentIndex (its bounds check `ci > shufflePermutation.count` only handles overflow, and is itself off-by-one — should be >=). Reachable scenario: shuffle is on; the user swipe-deletes the currently playing row in the NowPlaying queue list → PlaybackController.removeFromQueue(at:) (MuseAmp/Backend/Playback/PlaybackController.swift:334-336) calls player.next() (advance(): playedIndices gains old current, ci becomes k+1) then player.removeFromQueue(id: oldCurrent.id) → remove(id:) passes the not-currently-playing guard and removes the permutation entry at position k < ci. All entries after position k shift left, so the item the engine just started playing moves to position k while currentIndex stays k+1. Consequences: queue.nowPlaying points at the item AFTER the one actually audible (MusicPlayer.currentItem); QueueSnapshot.orderedItems omits the actually-playing item entirely; PlaybackController snapshot and persisted session record the wrong current track; when the audible track ends, handleItemEnd's advance() marks the never-played item at ci as played and jumps past it — that track is silently skipped.

**建议**: In the shuffled branch of removeCanonicalIndex, capture the removed entry's position in shufflePermutation before compactMap (`let removedPos = shufflePermutation.firstIndex(of: canonicalIndex)`), and if `removedPos < ci` decrement currentIndex; also change the overflow guard to `ci >= shufflePermutation.count`.

#### [HIGH] Shuffled removal of a history item desyncs currentIndex from the playing item

`MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:441`

**问题**: removeCanonicalIndex() in the shuffled branch (lines 435-443) removes the entry from shufflePermutation but never decrements currentIndex when the removed entry's permutation position precedes currentIndex (the non-shuffled branch handles this at lines 445-446). Reachable path: shuffle on, user removes the current row in the Now Playing queue list (NowPlayingShellController.swift:103 → PlaybackController.removeFromQueue(at: playerIndex), PlaybackController.swift:324-337), which calls player.next() then player.removeFromQueue(id: oldCurrentItem.id). next() leaves the old current at permutation position ci, advances ci to ci+1 and starts item X; remove(id:) then deletes the permutation entry at position ci (< new ci) and shifts everything left, so currentIndex now points one slot PAST X. Concrete: items [A,B,C,D], P=[2,0,3,1], playing A at ci=1; remove-current → engine plays D, but queue.nowPlaying becomes B. The snapshot/UI shows B as current while D is audible, makePersistedSession persists currentTrackID=B, and a subsequent next() marks B played and (repeat off) hits end-of-queue → playback stops and B never plays.

**建议**: In removeCanonicalIndex's shuffled branch, capture the removed entry's position in shufflePermutation before filtering (e.g. let removedPos = shufflePermutation.firstIndex(of: canonicalIndex)) and decrement currentIndex when removedPos < currentIndex, mirroring the non-shuffled adjustment.

### 维度: rebuild-scan

#### [MEDIUM] inspectAudioFile dependency discards embedded lyrics and provenance, so every rebuilt row gets hasEmbeddedLyrics=false and sourceKind=.unknown

`MuseAmp/Application/AppEnvironment+Bootstrap.swift:115`

**问题**: The production RuntimeDependencies.inspectAudioFile closure builds ImportedTrackMetadata with `lyrics: nil` (line 115) and `sourceKind: .unknown` (line 116), even though EmbeddedMetadataReader.makeTrackRecord already computed hasEmbeddedLyrics (EmbeddedMetadataReader.swift:69/89) and the reader has an extractLyrics API. LibraryScanner then derives `hasEmbeddedLyrics: metadata.lyrics.nilIfEmpty != nil` (LibraryScanner.swift:129), which is therefore ALWAYS false in production, and the embedded-lyrics cache write at LibraryScanner.swift:139-141 is unreachable dead code. Net effect: any track indexed or re-indexed through the rebuild path (file modified, row lost, file landed on disk without ingest) silently flips hasEmbeddedLyrics true→false and sourceKind .downloaded/.imported→.unknown in the index, diverging from what the file actually contains; the flag is exported via AudioTrackRecord+AppModels.swift:35 (catalogSong.hasLyrics). It also means a rebuild can never restore lost .lrc caches from lyrics that are physically embedded in the files, defeating the rebuild's purpose as a disk-truth recovery tool.

**建议**: In the inspectAudioFile closure, extract embedded lyrics (metadataReader.extractLyrics over the collected metadata items) and pass them through ImportedTrackMetadata.lyrics; alternatively extend AudioFileInspection to carry record.hasEmbeddedLyrics and have LibraryScanner use it. Preserve the existing row's sourceKind in the scanner (snapshot[relativePath]?.sourceKind ?? metadata.sourceKind) instead of overwriting with .unknown.

### 维度: caches

#### [MEDIUM] cachedArtworkData prefers stale cached artwork and bakes it into newly downloaded files

`MuseAmp/Backend/Downloads/DownloadArtworkProcessor.swift:79`

**问题**: When a track is re-downloaded (e.g. after deletion, or to pick up updated server art), prepareDownloadedTrack -> cachedArtworkData returns the OLD cached jpg whenever it exists (lines 79-81) instead of fetching the task's artworkURL, and then embedArtwork writes that stale image into the freshly downloaded audio file (line 40). The stale artwork is thereby permanently embedded into the new file's metadata, so even a later forceArtwork rebuild (which re-extracts embedded artwork) restores the stale image — the staleness survives the one mechanism designed to fix the cache. Combined with CacheCoordinator.writeArtwork's file-exists guard, there is no automatic path by which updated server artwork ever reaches a previously-downloaded trackID; only the manual TrackArtworkRepairService (which deliberately re-downloads and overwrites at TrackArtworkRepairService.swift:180) fixes it per-track.

**建议**: For fresh downloads, fetch from the artworkURL and overwrite the cache (the network fetch is happening at download time anyway), or at minimum bypass the cache when the cached file predates the download task. Keep the cache-read path only as a network-failure fallback.

### 维度: downloads

#### [MEDIUM] Metadata-embed export temp files (<UUID>.m4a) are written into the scanned Audio/<album>/ directory: rescans delete them mid-export, and crash orphans can be indexed as ghost tracks

`MuseAmp/Backend/Downloads/DownloadArtworkProcessor.swift:285`

**问题**: temporaryOutputURL places the AVAssetExportSession output at `<albumDir>/<UUID>.m4a`, i.e. inside the library Audio tree, because the finalizing ingest file `.tmp.<trackID>.m4a` lives in `Audio/<albumID>/`. Two failure scenarios: (a) If the user triggers a library rescan (AppEnvironment.resyncSongLibrary / rebuildLibraryDatabase → rebuildIndex(pruneInvalidFiles: true)) while a download is finalizing, LibraryScanner enumerates the half-written `<UUID>.m4a` (it is not hidden and does not end in `.tmp`, so neither the `.skipsHiddenFiles` option nor the `.hasSuffix(".tmp")` filter at LibraryScanner.swift:68 excludes it); inspectAudioFile fails on the partial file and pruneInvalidFiles DELETES it (LibraryScanner.swift:145-148) underneath the running export — the metadata embed fails and the track is ingested without its trackID/albumID comment metadata, which the export/transfer features later rely on. (b) If the app is killed after the export completes but before `replaceItemAt` (ExportMetadataProcessor.swift:186-187), a complete valid `<UUID>.m4a` remains; the next rescan passes validatePath (`album/UUID.m4a`) and indexes it as a duplicate ghost track whose trackID is a random UUID.

**建议**: Write export temps outside the scanned tree (e.g. FileManager.default.temporaryDirectory) or use a dot-prefixed name like `.export.<UUID>.m4a` so `.skipsHiddenFiles` excludes it, then replaceItemAt the destination.

#### [MEDIUM] Swallowed cancelled completion leaves stale diggerStartedURLs/task.url; subsequent resume calls startTask on a nonexistent seed and the task wedges in .downloading

`MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:130`

**问题**: When a cancelled completion arrives for an intentionallyPaused track, handleCompletion returns immediately without removing the url from `diggerStartedURLs`/`hasMarkedDownloading` or clearing `task.url` — but Digger has already removed the seed (DiggerDelegate.notifyCompletionCallback → removeDigeerSeed) and deleted the temp file. Sequence: (1) user taps Pause All → tasks suspended, trackIDs inserted into intentionallyPaused; (2) user changes Max Concurrent Downloads → session.invalidateAndCancel fires cancelled completions → swallowed at this line, seed gone, diggerStartedURLs still contains the url; (3) user taps Resume All → state .waiting → startResolving sees `task.url != nil` and `diggerStartedURLs.contains(url)` (DownloadManager+Queue.swift:54-55) → calls `DiggerManager.shared.startTask(for: url)` which silently no-ops because `diggerSeeds[url]` no longer exists (DiggerManager.swift:209-218). The task is now persisted and displayed as .downloading with no underlying transfer, occupies a concurrency slot (blocking the whole queue at the default maxConcurrent=1), and only an app relaunch reconciles it.

**建议**: In the swallowed-cancel branch, still clean up: remove the url from `diggerStartedURLs` and `hasMarkedDownloading` and set `tasks[trackID]?.url = nil` so a later resume goes through the fresh startDiggerDownload path. Additionally, startResolving should fall back to startDiggerDownload when DiggerManager has no seed for the url instead of assuming startTask succeeds.

#### [MEDIUM] intentionallyPaused is never cleared when tasks resume via WiFi restore or Allow Cellular, so genuine cancellations of running downloads are silently swallowed

`MuseAmp/Backend/Downloads/DownloadManager+Network.swift:48`

**问题**: handleNetworkChange(.cellular)/(.none) inserts the trackID into `intentionallyPaused` (lines 66, 83) before suspending the task, but the WiFi-restore branch (lines 46-52) and allowCellularDownload (DownloadManager.swift:331-344) move the task back to .waiting WITHOUT removing it from `intentionallyPaused` (only resumeAll and cancelTask remove entries, and resumeAll only for tasks currently in .paused). Result: after any cellular blip, an actively re-downloading task permanently carries the intentionallyPaused flag. Any later real NSURLErrorCancelled completion for that task (e.g. the session invalidation from a concurrency-setting change) hits the swallow guard at DownloadManager+Digger.swift:130 while the task state is .downloading, leaving it wedged in .downloading with no Digger seed and no requeue — the retry/requeue machinery that exists precisely for unexpected cancellations is bypassed.

**建议**: Remove the trackID from `intentionallyPaused` wherever a task transitions back to .waiting: in the WiFi-restore loop of handleNetworkChange and in allowCellularDownload, and in startResolving as a defensive reset before (re)starting a download.

#### [MEDIUM] Re-downloading a failed song via normal Download actions is silently skipped; the failed-record cleanup branch is unreachable

`MuseAmp/Backend/Downloads/DownloadManager.swift:181`

**问题**: submitRequests first checks `tasks[request.trackID] != nil` and skips. Failed tasks REMAIN in `tasks` (markFailed keeps the entry, and reconcileOnLaunch rehydrates persisted failed records into `tasks` via rehydrateFailedRecord). Therefore the later branch at lines 192-199 that deletes a `.failed` store record and requeues is dead code: any failed download — in-session or rehydrated after relaunch — is reported as `skipped` when the user taps Download on the song/album again, and the track never downloads. The only recovery path is the per-row Retry button on the Downloads screen, while album-level 'Download All Songs' will perpetually skip the failed track without surfacing an error, leaving the album silently incomplete.

**建议**: In submitRequests, when `tasks[request.trackID]?.state == .failed`, reuse the retryFailed logic (cleanup artifacts, reset url/progress, set .waiting, persist .queued) instead of counting it as skipped; keep the skip only for non-failed in-flight states.

### 维度: rebuild-validation-gap

#### [MEDIUM] AudioFileImporter has the same validation gap: corrupt-but-parseable and zero-duration files are imported into the library

`MuseAmp/Backend/Library/AudioFileImporter.swift:180`

**问题**: importSingleFile loads duration at lines 180-181 (`max(CMTimeGetSeconds(duration), 0)`) and builds the record via makeTrackRecord at line 248, with no playability check and no duration sanity bounds anywhere. A zero-duration file or a truncated file with an intact moov header passes every gate (catalog-ID check, title/artist check, duplicate checks) and is staged and ingested into the library as a healthy track (line 287). Only files whose duration load throws outright are counted as errors by the caller loop (lines 116-119). Additionally the duplicate heuristics make corrupt batches worse: with durationSeconds 0, any two distinct corrupt files sharing title/artist/album within ±2s (DuplicateKey bucketing at line 161, isDuplicate at line 345) are collapsed as 'duplicates', and a NaN duration never matches `abs(track.durationSeconds - duration) < 2.0`, so an indexed NaN-duration track can be re-imported repeatedly without ever being detected as a duplicate.

**建议**: Once validation is added to EmbeddedMetadataReader.makeTrackRecord (audio-track presence/AVAudioPlayer check plus finite 1s..24h duration bounds), importSingleFile inherits it via line 248; additionally treat a thrown validation error from makeTrackRecord as a distinct 'unplayable' result so the import summary can report it separately from generic errors, and validate the locally computed durationSeconds at line 181 before using it for duplicate detection.

### 维度: sync-transfer

#### [MEDIUM] Re-downloaded track flagged for update is silently dropped, leaving stale file on disk

`MuseAmp/Backend/Library/AudioFileImporter.swift:238`

**问题**: missingEntries (SyncTransferSession.swift:265-277) marks a manifest entry as needing transfer when a track with the same trackID already exists locally but its duration differs from the manifest by more than 1.0s — i.e. the existing local copy is considered stale and is re-fetched. The receiver downloads it (downloadEntries) and hands it to importFiles. But importSingleFile dedup at line 238 checks `if FileManager.default.fileExists(atPath: destURL.path)` where destURL = `albumID/trackID.ext` (line 235-237). Because the existing stale copy lives at exactly that deterministic path, the freshly downloaded (corrected) file returns `.duplicate` and is discarded — the on-disk file and the DB record are NEVER updated. The duration-mismatch detection in the receiver is therefore defeated by the importer: bandwidth is spent, the transfer is reported as a 'skipped/already existed' success, yet the library still holds the wrong-duration file. The two layers disagree on what 'already have it' means (importer: path/identity; receiver: identity + duration).

**建议**: Make the path-existence branch consistent with the receiver's freshness check: when a file already exists at destURL, compare its actual duration/size against the incoming file and replace it when they diverge, instead of unconditionally returning .duplicate. Alternatively have missingEntries not re-request tracks the importer will only drop.

### 维度: playlist

#### [MEDIUM] Add to Playlist menu allows duplicate entries and direct adds into Liked Songs, desyncing the liked state machine

`MuseAmp/Backend/MenuProviders/AddToPlaylistMenuProvider.swift:86`

**问题**: The menu lists `playlistStore.playlists` unfiltered (line 82), which includes the Liked Songs playlist (fixed zero UUID, returned by fetchPlaylists like any other row), and the action at line 86 calls playlistStore.addSong, which appends unconditionally — StateStore.addPlaylistEntry has no trackID containment check, and addSong's `inserted` flag (PlaylistStore.swift:132) is computed from `playlists != previousPlaylists`, which is always true on success because savePlaylistEntries bumps updatedAt. Concrete corruption sequence: a song is already liked via the heart button; the user also picks 'Liked Songs' in any Add to Playlist menu → the liked playlist now holds two entries with the same trackID. toggleLiked (PlaylistStore.swift:332-342) then calls removeSong(trackID:) which removes only the first matching index (line 353), returns `.unliked`, yet isLiked(trackID:) still reports true — the heart UI and the actual playlist contents disagree, and the user must tap unlike N times. PlaylistDetail's own move/copy flow proves the intended invariant: availableTargetPlaylists filters out playlists already containing the trackID (PlaylistDetailViewController+Actions.swift:127-131), but this shared provider used by Albums/Songs/AlbumDetail/NowPlaying flows does not.

**建议**: In addSong (or StateStore.addPlaylistEntry), skip insertion when the playlist already contains the trackID and return false, or at minimum filter already-containing playlists (and the Liked Songs playlist) out of AddToPlaylistMenuProvider's playlist list; for liked-state integrity make removeSong(trackID:) remove all entries with that trackID from the liked playlist.

### 维度: playback-state

#### [MEDIUM] Stale pendingSeekSnapshotTime resurfaces an old seek target as currentTime on every later pause

`MuseAmp/Backend/Playback/PlaybackController+Snapshot.swift:213`

**问题**: seekState.pendingSeekSnapshotTime is set by seek(to:) (PlaybackController.swift:365), previous()-restart (line 263), and restartCurrentTrack (line 275), but is only ever cleared when the queue empties (PlaybackController+Snapshot.swift:23) or the current track changes (line 49) — never when the seek completes or playback progresses past it. resolvedSnapshotCurrentTime (lines 202-219) returns the pending value whenever state is .idle/.paused/.error. Concrete sequence: while a track plays, the user scrubs to 60s (pending=60), listens on to 200s (didUpdateTime only mutates latestSnapshot's time, pending survives), then taps pause → didChangeState(.paused) → refreshSnapshot full path with nil explicit time → resolvedSnapshotCurrentTime returns the stale 60 → the published snapshot reports currentTime=60 while the player is actually at 200. Consumers of snapshot.currentTime show the wrong position: popup mini-player progress (MainController+Popup.swift:210, TabBarController+Popup.swift:187) jumps back to 60, and opening NowPlaying while paused seeds ProgressTrackView/NowPlayingPlaybackTimeRowView via `.prepend((playbackController.snapshot.currentTime, ...))` with 60 and receives no further subject events while paused. The wrong value sticks for the entire pause. (Persisted time is unaffected since makePersistedSession reads player.currentTime directly — i.e. published state and persisted state disagree.)

**建议**: Invalidate the pending value once it is no longer relevant: clear seekState.pendingSeekSnapshotTime in musicPlayer(_:didUpdateTime:) when a time update arrives (the engine is now reporting authoritative time), or clear it in the seek(to:) completion Task after the awaited player.seek returns.

#### [MEDIUM] Persisted-session restore can stomp user-initiated playback started during its await window

`MuseAmp/Backend/Playback/PlaybackController.swift:524`

**问题**: restorePersistedPlaybackIfNeeded() sets didAttemptPersistedRestore, then performs long awaited work: the per-track restoredArtworkURL loop (which can call metadataReader.extractArtwork — full AVAsset metadata reads — for every restored track whose artwork cache is missing, lines 490-508) and resolvePlayableItems (line 509). After these suspensions it unconditionally overwrites queueState.currentSource/trackLookup (lines 521-522) and calls player.restorePlayback (line 524) with no re-check that the player is still idle. SceneDelegate.swift:74-83 presents the interactive MainController and only then launches this restore in a detached Task, so the user can tap a song while restore is resolving. Sequence: user taps song → play(tracks:) → player.startPlayback begins audible playback and sets queueState.trackLookup; the in-flight restore then resumes, replaces trackLookup with the stale persisted map, and MusicPlayer.restorePlayback (MuseAmpPlayerKit MusicPlayer+Restoration.swift:32-53) replaces playbackQueue and the engine's current item, then sets state .paused (allowAutoPlay is false on iOS). The song the user just started is killed mid-play and replaced by yesterday's queue, paused — and refreshSnapshot(persistState: true) re-persists the stale queue over the user's new one.

**建议**: After the awaits and immediately before applying state (before line 521), guard that no playback was started concurrently: `guard player.queue.totalCount == 0, !player.state.isActive else { return false }` (or capture a generation counter incremented by play()/playNext()/addToQueue and abort if it changed).

#### [MEDIUM] removeTracksFromQueue leaves deleted tracks in queue history and re-persists dead entries

`MuseAmp/Backend/Playback/PlaybackController.swift:292`

**问题**: removeTracksFromQueue is called by library deletion flows right after the audio files and DB records are destroyed (e.g. SongsViewController+Actions.swift:52-53 calls musicLibraryTrackRemovalService.removeTracks then removeTracksFromQueue). But the purge loop (lines 292-300) only iterates `player.queue.upcoming`, and the current-track branch (lines 302-313) just calls player.next() without removing the item — unlike removeFromQueue(at:) (lines 334-336) which does next() + removeFromQueue(id:). Result: (a) history entries matching the deleted trackIDs are never touched, and (b) the just-deleted current track moves into history and stays in the queue. These dead entries remain visible in the NowPlaying queue list; tapping one or pressing previous() loads a missing file, producing didFailItem and an automatic forward skip. Worse, the didChangeQueue persist writes the dead entries into PersistedPlaybackSession at positions before currentIndex, which on next launch fail resolution and trigger the restoredCurrentIndex shift (wrong restored current track, position reset to 0).

**建议**: Also iterate `player.queue.history` and call player.removeFromQueue(id:) for matching entries, and in the current-track branch remove the current item after next() (mirroring removeFromQueue(at:)). Note: removing history entries in shuffle mode requires the PlaybackQueue.removeCanonicalIndex currentIndex-shift fix first.

#### [MEDIUM] Launch restore clobbers user-initiated playback started during its async window

`MuseAmp/Backend/Playback/PlaybackController.swift:521`

**问题**: restorePersistedPlaybackIfNeeded() is fired in a detached Task right after MainController becomes the interactive root (MuseAmp/Application/SceneDelegate.swift:80-83). Between sessionStore.load() and player.restorePlayback() it awaits per-track restoredArtworkURL() — which can run metadataReader.extractArtwork (AVAsset reads) for every queued track whose artwork cache is missing — plus resolvePlayableItems() file checks. If the user taps a song during this window, play(tracks:) starts real playback via player.startPlayback. When the restore task resumes it performs no re-check: lines 521-522 overwrite queueState.currentSource/trackLookup and line 524 calls player.restorePlayback, which unconditionally replaces the engine item, replaces the whole queue, and pauses (autoPlay=false → MusicPlayer+Restoration.swift:75-77). The user's just-started playback is silently killed and replaced with the stale prior session, and refreshSnapshot(persistState:true) then persists that stale session over the new queue. The didAttemptPersistedRestore flag only guards re-entry of restore itself, not this race.

**建议**: After the awaits (immediately before mutating queueState and calling player.restorePlayback), bail out with `guard player.queue.totalCount == 0 else { return false }` so a user-initiated queue created during the restore window always wins.

#### [MEDIUM] removeTracksFromQueue leaves deleted tracks in queue history and persisted session

`MuseAmp/Backend/Playback/PlaybackController.swift:302`

**问题**: removeTracksFromQueue is invoked right after the audio file is deleted from disk (e.g. SongsViewController+Table.swift:146-149 calls musicLibraryTrackRemovalService.removeTrack then this). It only purges matches from player.queue.upcoming (line 292) and, for the current item, calls player.next()/stop() (lines 306-310) WITHOUT removing the item — unlike removeFromQueue(at:) which follows next() with player.removeFromQueue(id: currentItem.id) (lines 335-336). Two consequences: (1) advance() moves the deleted current track into playedIndices, and any matching tracks already in history are never scanned, so the queue still references files that no longer exist on disk; tapping previous() rewinds to the deleted entry and loadAndPlay creates an AVPlayerItem for a missing file → didFailItem error mid-session. (2) Every subsequent persistPlaybackState writes the deleted track into the persisted queue; on next launch resolvePlayableItems drops it, shrinking the array and triggering the restoredCurrentIndex position-shift defect, so deleting one song can also corrupt the restored playback position.

**建议**: Scan player.queue.history (in addition to upcoming) and remove matches via player.removeFromQueue(id:); for the current-item case call player.next() followed by player.removeFromQueue(id: currentItem.id), matching the removeFromQueue(at:) implementation.

### 维度: caches

#### [MEDIUM] Shuffled cover render is persisted under the canonical size-specific cache key, leaving different views showing different covers

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:89`

**问题**: image(for:shuffled:true) skips cache reads but still stores its randomly-shuffled render into memory and disk under the same cacheKey as the canonical cover (lines 88-89); the key includes sidePixels (line 250). The only shuffled caller is regenerateCover (PlaylistDetailViewController+Menu.swift:179-183), which invalidates all sizes and then renders shuffled at sideLength 200 only. Result: the 200pt cache entry now holds the new shuffled arrangement, while every other active size — sidebar at sideLength 28 (MainController+Sidebar.swift:245), playlist list cells at ~44 (PlaylistCell.swift:123), cover preview at 1200 (PlaylistDetailViewController+Menu.swift:211) — re-renders the ORIGINAL unshuffled arrangement after the invalidation. The same playlist persistently shows two different covers depending on the surface, and because the `if !shuffled` guard (line 90) suppresses the .playlistArtworkDidUpdate notification, on-screen observers are never told the persisted 200pt cover changed either. The shuffle order itself is not persisted anywhere, so the regenerated cover silently reverts at every other size and after the next updatedAt bump.

**建议**: Never persist shuffled renders under the canonical key. Either render shuffled covers uncached (return without setObject/write), or make regeneration durable: persist the chosen entry order (or the rendered image into playlist.coverImageData via updatePlaylistCover) so all sizes derive the same arrangement, and post .playlistArtworkDidUpdate when the persisted cover changes.

### 维度: playlist

#### [MEDIUM] ensureLikedSongsPlaylist recreates via destructive importLegacyPlaylists keyed on in-memory state; a failed reload at init wipes all liked songs

`MuseAmp/Backend/Playlist/PlaylistStore+Support.swift:55`

**问题**: PlaylistStore.init runs reload() then ensureLikedSongsPlaylist(). reload() (PlaylistStore.swift:344-350) swallows fetch errors and leaves `playlists` at its prior value — at init that is `[]`. ensureLikedSongsPlaylist decides existence purely from this in-memory array (line 55) and, when it sees no liked playlist, calls createPlaylist(id: Playlist.likedSongsPlaylistID, ...) (lines 60-64). createPlaylist is implemented via `.importLegacyPlaylists([candidate])` with empty entries (PlaylistStore.swift:39), and StateStore.importLegacyPlaylists (StateStore.swift:213-227) does insertOrReplace of the playlist row followed by an unconditional DELETE of every playlist_entries row for that playlistID. So one transient fetchPlaylists failure at startup (DB busy/IO error) followed by a successful write silently destroys the user's entire Liked Songs playlist contents. The same destructive replace fires from toggleLiked → ensureLikedSongsPlaylist whenever `playlists` is stale-empty.

**建议**: Make the existence check authoritative against the database (e.g. databaseManager fetchPlaylist(id:)) before creating, or add a non-destructive `.createPlaylistIfAbsent` command; never route create-only flows through importLegacyPlaylists, which deletes existing entries for the same ID.

#### [MEDIUM] updateSong rewrites playlist via non-atomic clear + per-entry add; mid-loop failure permanently loses entries

`MuseAmp/Backend/Playlist/PlaylistStore.swift:170`

**问题**: updateSong(in:at:with:) issues `.clearPlaylistEntries` (line 170) as one committed DB transaction, then re-inserts every song with a separate `.addPlaylistEntry` command per entry (lines 171-173). Each command is its own WCDB transaction (StateStore.savePlaylistEntries). If any add throws mid-loop (disk full, I/O error), the single catch at line 174 only logs and the function returns: the clear has already committed, so all songs from the failing index onward are permanently deleted from the database; if the first add fails, the entire playlist is emptied. refreshSongs (line 255) calls updateSong once per changed song during the user-facing 'Refresh' action, multiplying the number of full clear+re-add rewrites and the exposure window. Additionally, after such a partial failure, the remaining loop iterations in refreshSongs keep using indices captured from the pre-failure snapshot (line 226), so subsequent updateSong calls write merged metadata onto the wrong, shifted entries — silent cross-entry corruption.

**建议**: Replace the clear+add loop with the already-transactional path: build the updated Playlist value and send `.importLegacyPlaylists([updatedPlaylist])` (StateStore wraps row replace + entry delete + inserts in one transaction), or add a dedicated `replacePlaylistEntries(playlistID:entries:)` command that performs delete+insert inside one transaction.

#### [MEDIUM] createPlaylist is a destructive upsert: existing playlist with same UUID has all entries wiped

`MuseAmp/Backend/Playlist/PlaylistStore.swift:39`

**问题**: createPlaylist(id:name:coverImageData:) sends `.importLegacyPlaylists([candidate])` with candidate.entries = []. StateStore.importLegacyPlaylists (StateStore.swift:209-228) does insertOrReplace of the PlaylistRow and then DELETES every PlaylistEntryRow for that playlistID before inserting the (empty) candidate entries. So 'create' silently destroys any existing playlist with the same id, including its entries, createdAt and cover. The reachable trigger is ensureLikedSongsPlaylist (PlaylistStore+Support.swift:53-66): it decides existence purely from the in-memory `playlists` array. PlaylistStore.reload() (PlaylistStore.swift:344-350) swallows fetchPlaylists errors and leaves `playlists` stale/empty; if the fetch in init throws while writes still succeed, ensureLikedSongsPlaylist sees no Liked Songs playlist and calls createPlaylist(id: likedSongsPlaylistID) at PlaylistStore+Support.swift:60, which deletes every liked-songs entry in the database. The error path of a read is thereby converted into a destructive write keyed by the all-zero UUID.

**建议**: Make createPlaylist non-destructive: check the database (databaseManager.fetchPlaylist(id:)) and return the existing playlist instead of importing over it, or extend the `.createPlaylist` LibraryCommand to accept id/cover and use StateStore.createPlaylist which uses plain insert (fails instead of replacing). At minimum, ensureLikedSongsPlaylist must verify absence against the DB, not the in-memory array.

#### [MEDIUM] refreshSongs merge erases stored artworkURL when remote response omits artwork

`MuseAmp/Backend/Playlist/PlaylistStore.swift:237`

**问题**: In the merged PlaylistEntry built at lines 230-241, every other optional field falls back to the existing value (`albumID: refreshed.albumID ?? existing.albumID`, `albumTitle: ... ?? existing.albumTitle`, `durationMillis: ... ?? existing.durationMillis`, `trackNumber: ... ?? existing.trackNumber`), but line 237 uses `artworkURL: refreshed.artworkURL` with no fallback. refreshed.artworkURL is `catalogSong.attributes.artwork?.url` (line 204), which is nil whenever the server response lacks the artwork object. In that case merged.artworkURL becomes nil, `artworkChanged` (line 244) is true, and updateSong persists the entry with its artwork template erased — a transient missing field in one network response permanently deletes stored artwork data for the entry. Downstream, PlaylistDetailViewController+Artwork.artworkURL(for:) and PlaylistCoverArtworkCache.coverIdentity degrade for that song (cover grid identity falls back to album-id/song keys, row artwork disappears for non-downloaded tracks).

**建议**: Use `artworkURL: refreshed.artworkURL ?? existing.artworkURL` to match the merge policy of the neighboring fields, or explicitly distinguish 'server returned no artwork object' from 'artwork intentionally removed'.

#### [MEDIUM] mergeSongs creates duplicate trackIDs in Liked Songs, breaking toggleLiked/heart state

`MuseAmp/Backend/Playlist/PlaylistStore.swift:310`

**问题**: mergeSongs (lines 310-317) calls addSong for every source song with no containment check, and addSong (line 111) unconditionally appends (StateStore.addPlaylistEntry has no dedup). PlaylistContextMenuProvider.swift:95 builds merge targets as `playlists.filter { $0.id != playlist.id }`, which includes the Liked Songs playlist. Scenario: song X is already liked; user merges a playlist containing X into Liked Songs; Liked Songs now holds two entries for trackID X. Tapping unlike (heart button, lock-screen like command, album menu) runs toggleLiked (line 332): isLiked is true, removeSong(trackID:) (line 352) removes only the FIRST matching entry, returns .unliked — but the second entry remains, so isLiked(trackID:) is still true and PlaybackController.refreshSnapshot re-renders the heart as liked. The UI reports 'unliked' while the song stays in Liked Songs; the user must tap once per duplicate. This also contradicts the app's own no-duplicate intent expressed in PlaylistDetailViewController+Actions.availableTargetPlaylists (lines 127-131), which filters out playlists already containing the trackID.

**建议**: Either skip songs whose trackID already exists in the target inside mergeSongs (and addSong for the Liked Songs playlist specifically), or make removeSong(trackID:from:) remove ALL entries matching the trackID so toggleLiked converges in one action.

#### [MEDIUM] updateSong clears then re-adds entries without a transaction; mid-loop failure permanently drops the tail of the playlist

`MuseAmp/Backend/Playlist/PlaylistStore.swift:170`

**问题**: updateSong issues `.clearPlaylistEntries(playlistID:)` as one synchronous command, then re-adds every song via a separate `.addPlaylistEntry` command per entry (PlaylistStore.swift:170-173). Each command is an independent WCDB transaction (StateStore.savePlaylistEntries wraps only its own delete+insert). If any add throws partway (SQLITE_FULL, SQLITE_BUSY/IOERR), the single catch at line 174 only logs and falls through to reload() — the clear has already committed, so every entry from the failing index onward is permanently gone from the database with no rollback and no user-facing error. This path is also the write path for refreshSongs (line 255), which calls updateSong once per changed song, so a 200-song playlist refresh executes hundreds of clear/rebuild cycles, multiplying the exposure window. Additionally each `.addPlaylistEntry` re-reads and rewrites the entire entry table for the playlist (StateStore.swift:171-175), giving O(n²) row writes for a single one-field entry update.

**建议**: Add a `replacePlaylistEntries(playlistID:entries:)` LibraryCommand that performs the delete + bulk insert inside one StateStore transaction (savePlaylistEntries already does exactly this), and have updateSong/refreshSongs send that single command instead of clear + N adds.

#### [MEDIUM] refreshSongs merge nils out stored artworkURL when the server response lacks artwork, unlike every other optional field

`MuseAmp/Backend/Playlist/PlaylistStore.swift:237`

**问题**: In the refreshSongs merge (PlaylistStore.swift:230-241), albumID, albumTitle, durationMillis and trackNumber all fall back to the existing value (`refreshed.x ?? existing.x`), but line 237 assigns `artworkURL: refreshed.artworkURL` with no fallback. `refreshed.artworkURL` comes from `catalogSong.attributes.artwork?.url` (line 204), which is nil whenever the Subsonic response omits cover art (temporarily missing coverArt, server-side artwork issue). Because line 244 computes `artworkChanged = merged.artworkURL != existing.artworkURL`, the nil is treated as a change and persisted via updateSong — silently erasing the previously stored artwork URL for that entry. Cover-grid rendering then only works for tracks whose local artwork file exists (PlaylistDetailViewController+Actions.swift:297-301); for the rest the tile and row artwork degrade permanently until another refresh happens to return artwork.

**建议**: Use `artworkURL: refreshed.artworkURL ?? existing.artworkURL` to match the other optional fields, or only clear artwork when the fetch explicitly succeeded with an empty artwork relationship.

### 维度: sync-transfer

#### [MEDIUM] No integrity (size/checksum) field in manifest; corrupt-but-right-length source transferred and imported undetected

`MuseAmp/Backend/Sync/SyncProtocol.swift:223`

**问题**: SyncManifestEntry (lines 223-231) carries trackID/title/duration/fileExtension but no file size or content hash. The sender's handleTrack sets Content-Length from the prepared file's on-disk size (SyncServer.swift:449) and streams exactly that file, so Content-Length always equals the bytes streamed — meaning the receiver's only available validation (URLSession length checking) can detect a dropped connection but can NEVER detect a source file that is the correct length yet corrupt (e.g. a previously-interrupted download in the sender's own library, or bit-rot). On the receiver, downloadTransferTrack (APIClient+Transfer.swift:84-137) writes the bytes and returns; importSingleFile then loads it via AVURLAsset and, crucially, performs NO comparison of the imported file's duration against the manifest entry's durationSeconds. A corrupt source therefore propagates into the receiver's library and playlist session as a valid track. There is no end-to-end integrity check anywhere in the transfer.

**建议**: Add a contentHash (e.g. SHA-256) and/or byteSize to SyncManifestEntry, compute it on the sender at prepare time, and verify it on the receiver after download (in downloadTransferTrack or before import). Reject/skip and report as failed any entry whose downloaded bytes do not match, rather than importing it.

### 维度: index-state-store

#### [MEDIUM] Nonisolated sendSynchronously mutation path races @DatabaseActor ingest/rebuild on the same stores

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Commands.swift:19`

**问题**: sendSynchronouslyIfSupported is nonisolated and invoked directly from app threads (PlaylistStore+Support.swift:36, MusicLibraryDatabase+Downloads.swift:25/40, MusicLibraryTrackRemovalService.swift:20), while .ingestAudioFile/.rebuildIndex run on @DatabaseActor (send, line 124). There is no shared lock, so removeTrackSynchronously/removeAlbumSynchronously (file delete + row delete, DatabaseManager+Writes.swift:127-155) can interleave arbitrarily with an in-flight download ingest for the same album. Concrete sequence: a background download for album X is finalizing — ingestAudioFile on the actor runs moveToLibrary (file created under Audio/X/) and is about to upsert; the user simultaneously deletes album X from the Songs/Albums UI (SongsViewController+Actions.swift:52 → sendSynchronously on the main thread): removeAlbumSynchronously removes the whole Audio/X directory (including the just-moved file) and deletes rows; ingest then executes `upsertTracks([record])` (line 108), re-inserting a row whose file no longer exists. Result: a ghost track in the library that fails to play (and is reported as downloaded by DownloadStore.isDownloaded only until the fileExists check, while the tracks list still shows it) until the next manual library refresh. The reverse interleaving resurrects a user-deleted album at the next rebuild from the orphan file.

**建议**: Serialize all mutating commands through one executor: make the synchronous path acquire the same mutual exclusion as @DatabaseActor (e.g. an NSRecursiveLock held by both, or route removeTrack/removeAlbum through the actor and drop the synchronous variants), so file-system mutation + row mutation pairs cannot interleave.

### 维度: rebuild-scan

#### [MEDIUM] ingestAudioFile orphans the old audio file when relativePath changes, and rebuilds then flip-flop the row between the two files

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:83`

**问题**: ingestAudioFile fetches `existing = try indexStore.track(byID:)` (line 83) only to preserve createdAt. When the re-ingested track's relativePath differs from existing.relativePath (album reorganization on the server changes albumID — e.g. re-import via LAN sync passes AudioFileImporter's title/artist/album/duration dedupe because the album name changed, and the destURL-exists check at AudioFileImporter.swift:238 checks only the NEW path), the upsert (line 108, INSERT OR REPLACE keyed on trackID PK per TrackRow.swift:90) silently repoints the row to the new path while the old file at existing.relativePath is never deleted. Consequence chain in the rebuild pipeline: on the next rebuildIndexFromDisk the orphaned old file is not in the snapshot, gets re-inspected and upserted (LibraryScanner.swift:135/152), and INSERT OR REPLACE replaces the row again — now pointing back at the OLD file; the new path was 'seen' so deleteTracks does not touch it. Every subsequent rebuild flips the row between the two paths (whichever file is absent from the snapshot gets re-inspected and wins), so the library alternates between two different audio files for the same trackID, updatedAt churns, and one file is always invisible/orphaned on disk.

**建议**: In ingestAudioFile, after the upsert, compare existing?.relativePath with moved.relativePath; if they differ, delete the old file via fileManager.removeTrackFile(relativePath: existing.relativePath) (and clean its empty parent directory) so disk and index stay one-to-one.

### 维度: index-state-store

#### [MEDIUM] DB stores raw trackID/albumID while the file is named with sanitized components — identity drifts on the first re-inspection

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:85`

**问题**: ingestAudioFile writes `trackID: metadata.trackID` and `albumID: metadata.albumID` verbatim into the index row (lines 85-86), but LibraryFileManager.moveToLibrary names the file `sanitizePathComponent(albumID)/sanitizePathComponent(trackID).ext` (LibraryFileManager.swift:21), where sanitizePathComponent replaces any of `/:\?%*|"<>`, newlines, and '..' with '_' (StringUtilities.swift:23-40). LibraryScanner re-derives trackID/albumID from the (sanitized) path (LibraryScanner.swift:83-86). For any server-issued ID containing one of those characters (Subsonic IDs are opaque, server-controlled strings), the DB row and the file disagree: as soon as the file's size/mtime changes (artwork repair, metadata embed, restore) the rebuild re-inspects it and the upsert replaces the row (relativePath UNIQUE conflict) with the SANITIZED trackID. Consequences: playlist entries keyed by the raw trackID become permanently unresolved; artwork/lyrics caches written under the raw trackID at ingest (DatabaseManager+Writes.swift:75,79) are deleted by pruneOrphanArtwork/pruneOrphanLyrics (LibraryScanner.swift:155-157) because validTrackIDs now only contains the sanitized ID; DownloadStore.isDownloaded(raw trackID) turns false so the song is offered for re-download.

**建议**: Normalize once at the boundary: store `sanitizePathComponent(metadata.trackID)` / `sanitizePathComponent(metadata.albumID)` in the index row (and in cache keys) so the persisted identity always round-trips through the filesystem, or persist the raw ID as a separate column and key files/caches by the sanitized form consistently.

### 维度: caches

#### [MEDIUM] Orphan prune compares sanitized cache filenames against raw index trackIDs, deleting valid tracks' caches

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/CacheCoordinator.swift:117`

**问题**: Cache files are written under sanitized names: LibraryPaths.artworkCacheURL/lyricsCacheURL (LibraryPaths.swift:71-77) apply sanitizePathComponent(trackID), which rewrites any of /:\?%*|"<> plus control chars to '_', collapses '..', and trims whitespace (StringUtilities.swift:23-40). But the index stores the RAW trackID: ingestAudioFile builds AudioTrackRecord with metadata.trackID verbatim (DatabaseManager+Writes.swift:85) while only the file path is sanitized via moveToLibrary (LibraryFileManager.swift:21). orphanTrackIDs() derives the candidate ID from the sanitized filename (line 116) and checks it against validTrackIDs = indexStore.trackIDs() (raw IDs) at line 117. For any server-issued trackID where sanitizePathComponent(trackID) != trackID (e.g. an ID containing ':', '/', or leading/trailing whitespace), the membership test always fails, so pruneOrphanArtwork/pruneOrphanLyrics (called from LibraryScanner.rebuildIndexFromDisk lines 156-157 on every 'Refreshing Library' pull-to-refresh) delete that valid track's artwork and lyrics cache on every rebuild, and writeArtwork's file-exists guard means the artwork is only restored if the scan re-inspects the file (it does not for unchanged files). The audit (DatabaseManager+Audit.swift:29-31) also permanently reports these as orphans. Sanitization also maps distinct trackIDs ('a/b' and 'a:b') to the same cache file name, silently sharing one artwork/lyrics entry between two tracks.

**建议**: In orphanTrackIDs(), compare against sanitized IDs: build `let validNames = Set(validTrackIDs.map(sanitizePathComponent))` and test filename membership in that set. Longer term, sanitize trackID once at ingest so index, audio filename, and cache filenames all agree, and make sanitizePathComponent collision-resistant (e.g. append a short hash when the input was modified).

#### [MEDIUM] writeArtwork never replaces an existing file, so artwork cache stays stale forever after a track update

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/CacheCoordinator.swift:17`

**问题**: writeArtwork returns early when the jpg already exists (line 17) and never compares contents. Two real paths hit this: (1) re-downloading a track whose album art changed on the server — ingestAudioFile extracts the new embedded artwork and calls writeArtwork (DatabaseManager+Writes.swift:75), which silently keeps the old image, yet still emits `.artworkCacheChanged(trackIDs:)` (line 76) telling the UI the cache changed when it did not; (2) rebuildIndexFromDisk detects a changed file (size/mtime mismatch, lines 92-95 fail), re-inspects it and calls writeArtwork (LibraryScanner.swift:137) — the new embedded artwork is again discarded. Lyrics behave differently (LyricsCacheStore.saveLyrics overwrites unconditionally), so after a track update lyrics are fresh while artwork is stale — a silent divergence between the audio file's embedded artwork, the index record (hasEmbeddedArtwork/updatedAt refreshed), and the artwork cache that all UI reads (AudioTrackRecord+AppModels, PlaylistCell.swift:127, PlaylistDetailViewController+Actions.swift:297 all read artworkCacheURL). The only recovery is the manual forceArtwork rebuild.

**建议**: Remove the fileExists early-return on the update paths: overwrite unconditionally (writes are atomic), or compare data (length/hash) and overwrite when different. If the guard exists to avoid redundant writes during plain rescans, pass an `allowOverwrite` flag from the changed-file and ingest paths.

### 维度: import-move

#### [MEDIUM] moveToLibrary deletes the existing library file before validating that the replacement move can succeed

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryFileManager.swift:35`

**问题**: Lines 35-37 unconditionally removeItem(finalURL) when a file already exists, BEFORE attempting moveItem(sourceURL -> stagingURL) at line 38. If that first move throws (source vanished, file-protection/locking error, cross-volume copy failure), the previously valid library file has already been destroyed while its index row still points at relativePath — the track remains listed in the UI but playback fails, and only a manual rebuild with pruneInvalidFiles removes the ghost row. The overwrite path is reachable: e.g. a track imported via LAN transfer (file at Audio/<albumID>/<trackID>.m4a, sourceKind .imported, no download record) can be re-downloaded — DownloadManager.submitRequests only checks the download store, so the download's ingest hits an existing finalURL. Additionally, if the second move (stagingURL -> finalURL, line 39) fails, the payload is stranded as '<trackID>.<ext>.tmp' in the album directory and the source is gone; the importer's catch in AudioFileImporter.swift:289 only checks the Incoming stagingURL, so the .tmp leaks until the same exact track is re-ingested (lines 32-34) or a manual rebuild with prune runs (LibraryScanner.swift:68 prunes '.tmp' suffixes only when pruneInvalidFiles=true).

**建议**: Reorder to: move source into the .tmp staging name first, then remove the existing finalURL, then rename .tmp to final (or use FileManager.replaceItemAt for an atomic swap). On failure after the .tmp move, move the .tmp back or delete it so no stale .tmp survives.

#### [MEDIUM] Re-ingesting the same trackID with a different file extension orphans the old audio file and makes the index flip-flop between the two files on every rebuild

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryFileManager.swift:21`

**问题**: moveToLibrary's overwrite handling (lines 21, 35-37) is extension-specific: ingesting trackID 123 as 'albumID/123.mp3' does not remove an existing 'albumID/123.m4a'. TrackRow's primary key is trackID with insertOrReplace semantics (Internal/WCDB/TrackRow.swift:90, IndexStore.swift:166), so DatabaseManager+Writes.swift:108 repoints the single row's relativePath to the .mp3 while the .m4a stays on disk, indexed by nothing. The orphan is never cleaned: LibraryScanner.validatePath accepts any alphanumeric extension, so on every manual rebuild BOTH files pass scanning, both produce AudioTrackRecords with the same trackID (LibraryScanner.swift:86, 112-135), and insertOrReplace makes filesystem enumeration order decide which physical file the row points at — the track's audio/metadata can silently switch between the two copies across rebuilds, and the losing file occupies disk forever. Reachable when importing a different-format rip of an already-present track whose title/artist/duration dedup misses (e.g. duration differs >=2s or artist string differs), since AudioFileImporter.swift:238 only checks destURL with the new file's own extension.

**建议**: In moveToLibrary (or ingestAudioFile before the move), look up the existing index row for trackID and delete its old relativePath file when the extension differs; in LibraryScanner, detect multiple files mapping to one trackID, keep one deterministically, and prune the rest.

### 维度: rebuild-validation-gap

#### [MEDIUM] Single unreadable file aborts the entire rebuild because the per-file stat is outside the per-file catch

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:88`

**问题**: `try FileManager.default.attributesOfItem(atPath:)` at line 88 sits in the scan loop but OUTSIDE the do/catch that begins at line 109, so one failing stat throws out of rebuildIndexFromDisk entirely: all accumulated upserts (line 152) are discarded, stale-row deletion (line 153-154) and orphan pruning never run, setLastRebuild is never written, and DatabaseManager+Writes.swift:21 has already sent .indexRebuildStarted with no matching finished event. This is reachable: rebuildIndexFromDisk is a nonisolated async func, so it does NOT run on @DatabaseActor and interleaves freely with actor-isolated ingestAudioFile, whose moveToLibrary briefly removes an existing finalURL during re-download finalization (LibraryFileManager.swift:36-39); removeTrack is fully synchronous on any caller thread (MusicLibraryTrackRemovalService.swift:20 -> sendSynchronously) and deletes files mid-scan; and a permission-denied/protected file in the audio directory stats with an error. The file list was captured up front by discoverAudioFiles, so any file that disappears or becomes unreadable between enumeration and its turn in the loop converts a one-file problem into 'Rebuild Failed' for the whole library (SettingsViewController+Actions.swift:172-183).

**建议**: Move the attributesOfItem call (lines 88-90) inside the per-file do/catch, treating a stat failure as that single file being skipped (or invalid) rather than aborting the scan; alternatively catch around lines 88-90 separately and `continue`. Also emit a terminal rebuild event on the failure path in DatabaseManager+Writes.rebuildIndex so observers are not left with an unfinished indexRebuildStarted.

### 维度: rebuild-scan

#### [MEDIUM] Uncaught attributesOfItem throw aborts the entire rebuild when one file vanishes mid-scan

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:88`

**问题**: Line 88 (`let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)`) is a bare try outside the do/catch that only wraps the inspection block (lines 109-149). The file list is materialized once in discoverAudioFiles() before the loop, and the loop suspends on `await dependencies.inspectAudioFile` for every changed file, so the scan can run for minutes. During that window, @DatabaseActor work continues to run (rebuildIndexFromDisk is a nonisolated async function executing off the actor): removeTrackSynchronously / removeAlbumSynchronously (user deletes a song/album while 'Refreshing Library' runs) and DownloadManager.cleanupLocalAudioArtifacts both delete files inside the Audio directory. If any enumerated file is deleted before the scanner reaches its stat, line 88 throws and the whole rebuild aborts: upsertTracks/deleteTracks (lines 152-154) never run, all completed inspection work is discarded, invalid/.tmp files already pruned inline (lines 70-73, 145-148) are gone from disk while the index cleanup never executes, caches written at lines 137/140 for already-inspected new files become orphans, and DatabaseManager+Writes.rebuildIndex propagates the error after having sent .indexRebuildStarted with no terminal event.

**建议**: Wrap the attributesOfItem call in a per-file do/catch: on failure, log and `continue` (the path is already in seenRelativePaths, so the existing row is preserved and nothing is deleted). A vanished file will be reconciled on the next rebuild.

#### [MEDIUM] Orphan-cache prune races with concurrent ingestAudioFile and deletes a just-downloaded track's artwork/lyrics caches

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:155`

**问题**: rebuildIndexFromDisk is a nonisolated async function, so under the package's Swift 6 language mode (swift-tools 6.2, no NonisolatedNonsendingByDefault) it runs on the global concurrent executor while DatabaseActor stays free — DatabaseManager+Writes.rebuildIndex merely awaits it. Download finalization concurrently calls send(.ingestAudioFile) (MuseAmp/Backend/Downloads/DownloadManager+Digger.swift:275) on @DatabaseActor. ingestAudioFile writes the artwork cache (DatabaseManager+Writes.swift:75) and lyrics cache (line 79) BEFORE upserting the track row (line 108). Interleaving: scanner executes `let validTrackIDs = try indexStore.trackIDs()` (line 155) after ingest wrote the caches but before its upsert lands; pruneOrphanArtwork/pruneOrphanLyrics (lines 156-157) then delete the new track's .jpg/.lrc as orphans (trackID not in validTrackIDs); ingest's upsert lands afterwards with hasEmbeddedArtwork=true. Because writeArtwork is never re-attempted for snapshot-matching files on later rebuilds (lines 92-106 `continue`) and CacheCoordinator.writeArtwork early-returns when nothing changed, the index permanently claims artwork/lyrics that no longer exist on disk until the user runs a forceArtwork rebuild. Trigger is realistic: user taps 'Refreshing Library' (SongLibraryViewController+Actions.swift:85) while an album download is finalizing; pruneOrphans enumerates the whole cache directory, giving a sizable window.

**建议**: Serialize rebuild with all other library writes: either make rebuildIndexFromDisk's DB/cache mutation tail (upsert, delete, prune) run on @DatabaseActor, or hold a manager-level write gate for the duration of the rebuild so ingest/remove commands queue behind it. Alternatively re-fetch trackIDs immediately before deleting each orphan candidate and skip IDs that appeared.

### 维度: caches

#### [MEDIUM] forceArtwork rebuild wipes the whole artwork cache but can only restore embedded artwork, losing remote-fetched artwork

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:54`

**问题**: With forceArtwork (Settings action, SettingsViewController+Actions.swift:147), clearArtworkCache() deletes every jpg up front (line 54). Restoration only happens from embedded artwork: unchanged files re-extract at lines 98-101, changed files at lines 136-138. Tracks whose cached jpg was created by the remote download path (DownloadArtworkProcessor.cachedArtworkData writes the jpg even when artwork embedding subsequently fails or times out — DownloadArtworkProcessor.swift:84 then 40-43) have hasEmbeddedArtwork == false and their only artwork copy is the cache file; for these, the wipe is unrecoverable by the scan and the track deterministically loses its artwork (UI falls back to placeholder/remote URL, which is unavailable offline). Additionally, because the clear happens before the scan, any error thrown mid-rebuild (e.g. attributesOfItem at line 88 throwing because a file was concurrently removed via the nonisolated removeTrackSynchronously path, DatabaseManager+Commands.swift:18-19) aborts rebuildIndexFromDisk after the cache was emptied but before any artwork was rewritten, leaving the entire library artwork-less until a successful rerun.

**建议**: Do not bulk-clear up front. Instead overwrite per track at re-extraction time (delete+rewrite each trackID's jpg only when new embedded artwork was successfully obtained), preserving cache entries for tracks without embedded artwork and making a mid-scan failure non-destructive.

### 维度: index-state-store

#### [MEDIUM] trackID-only primary key silently drops one of two files whose filename stems collide across album directories

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/WCDB/TrackRow.swift:90`

**问题**: On-disk identity is `albumID/trackID.ext` (LibraryScanner derives trackID purely from the filename stem, LibraryScanner.swift:86, and albumID from the directory, line 83), but the tracks table primary key is trackID alone (TrackRow.swift:90). If two files with the same stem exist under different album directories (e.g. 'AlbumA/1.m4a' and 'AlbumB/1.m4a' — numeric Subsonic song IDs are not globally unique across servers, and LAN transfer + import can land same-stem files in different folders), rebuildIndexFromDisk creates two AudioTrackRecords with the same trackID and upsertTracks's per-record `insertOrReplace` (IndexStore.swift:164-168) lets the second silently replace the first inside the same transaction. No error, no log; one file stays on disk forever but never appears in allTracks/listAlbums, is never deleted (its path is in seenRelativePaths so deletedPaths skips it), and its bytes are invisible to librarySummary. The same INSERT OR REPLACE also silently removes an unrelated second row when the relativePath UNIQUE constraint (line 93) conflicts.

**建议**: Detect trackID collisions during the scan (group candidate records by trackID before upserting), log via DBLog.error, and either quarantine/delete the duplicate file or derive a composite identity (albumID + trackID) so both files remain addressable. At minimum surface the collision in AuditSnapshot instead of silently losing a track.

### 维度: downloads

#### [LOW] Cross-launch download resume never works and partial temp files are orphaned, because the playback URL embeds a per-session random token salt

`MuseAmp/Backend/Downloads/DownloadManager+Queue.swift:66`

**问题**: The reconcile design persists interrupted jobs and requeues them (reconcileOnLaunch), and Digger resumes via a Range header from a temp file keyed by SHA256 of the URL string (DiggerManager.swift:250-254, DiggerCache.tempPath). But startResolving always re-resolves the URL through apiClient.playback, and SubsonicMusicService generates `tokenSalt = UUID()` once per service instance (SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:20), so the `s=`/`t=` query items — and therefore the temp-file hash — differ on every app launch. Consequences after any kill/relaunch mid-download: (1) the download restarts from byte 0 even though most of the file was already fetched, and (2) the previous partial file at NSTemporaryDirectory()/<old-hash> is orphaned — DownloadManager never calls DiggerCache.cleanDownloadTempFiles, so repeatedly interrupted large downloads accumulate multi-MB garbage until iOS purges tmp. The persisted `DownloadJob.sourceURL` exists but is never reused by rehydrateQueuedRecord.

**建议**: Reuse the persisted `record.sourceURL` when rehydrating queued records (set task.url from it) so the same URL/temp file is resumed within token validity, and/or call DiggerCache.cleanDownloadTempFiles when reconcileOnLaunch finds no active records to bound the orphaned-partials growth.

#### [LOW] cancelTask has no guard for .finalizing and races the detached ingest pipeline; worst case leaves a library track row whose audio file was just deleted

`MuseAmp/Backend/Downloads/DownloadManager.swift:309`

**问题**: cancelTask is offered by the Downloads UI for every non-failed state and runs cleanupLocalAudioArtifacts, which deletes both `.tmp.<id>.m4a` and the final `<album>/<id>.m4a`. Finalization runs concurrently on a detached Task + @DatabaseActor (startFinalizing → DatabaseManager.ingestAudioFile), which (1) moves the tmp file to the final path (DatabaseManager+Writes.swift:63), (2) awaits inspectAudioFile, (3) upserts the track row (line 108), then hops back to MainActor for completeFinalization. If the user's cancel lands after step 3 but before completeFinalization removes the task, cleanupLocalAudioArtifacts deletes the final audio file while the freshly-upserted AudioTrackRecord (and the .tracksChanged inserted event already sent) remain — the library then lists a track whose file does not exist, and the DownloadJob record has been deleted so no download UI references it either. Cancels landing earlier in the window are benign (ingest throws on the missing file), but nothing serializes cancel against the in-flight finalization.

**建议**: Either refuse cancelTask while state == .finalizing (the download is already complete on disk), or record the in-flight finalization Task per trackID and cancel/await it before running cleanupLocalAudioArtifacts; alternatively have completeFinalization verify the final file still exists before treating ingestion as success.

### 维度: import-move

#### [LOW] DuplicateKey duration bucketing contradicts both its own ±1s comment and the cross-batch abs<2.0 rule, letting near-identical files through within one batch

`MuseAmp/Backend/Library/AudioFileImporter.swift:161`

**问题**: DuplicateKey buckets duration as Int((duration / 2.0).rounded()) and the comment claims '±1s tolerance matches'. Neither holds: two files with the same lowercased title/artist/album and durations 178.99s and 179.01s (0.02s apart) land in buckets 89 vs 90, so the intra-batch check at line 221 misses them and both are imported in a single batch — while the identical pair imported in two separate batches is rejected by isDuplicate's uniform abs(diff) < 2.0 test (line 345). Conversely, durations up to ~2s apart can share a bucket. Result: whether the library ends up with one or two copies of the same song depends on whether the user picked the files in one picker session or two — silent, order-dependent inconsistency in dedup behavior.

**建议**: Drop the bucketing: keep an array of (title, artist, album, duration) for the batch and test it with the same predicate as isDuplicate (case-insensitive compare plus abs(durationDiff) < 2.0), so intra-batch and cross-batch dedup are identical.

#### [LOW] Staging copies in Documents/OfflineLibrary/Incoming leak permanently if the app is killed mid-import; no sweeper exists

`MuseAmp/Backend/Library/AudioFileImporter.swift:257`

**问题**: Each import copies the picked file to Incoming/<UUID>.<ext> (lines 257-264) before ingest. The only cleanup is the inline catch at lines 289-291, which runs solely when ingest throws in-process. If the app crashes or is force-quit between the copyItem (a multi-second window for large FLAC/WAV files or big batches) and the ingest move, the staged copy is never removed: grep confirms incomingDirectory is referenced only here and in LibraryPaths (creation in ensureDirectoriesExist) — no bootstrap, rebuild, or scanner path ever enumerates or clears it (LibraryScanner only scans audioDirectory). Orphans accumulate invisibly in Documents, inflating the app's storage footprint with no user-visible way to reclaim them.

**建议**: Sweep incomingDirectory at startup (e.g. in LibraryPaths.ensureDirectoriesExist or DatabaseBootstrapper): delete all files, or files older than a short TTL, since every legitimate staging file is consumed within the same import call.

### 维度: playback-state

#### [LOW] Shuffled session persistence loses the canonical order, so un-shuffling after restore cannot recover the original order

`MuseAmp/Backend/Playback/PlaybackController+Resolution.swift:194`

**问题**: makePersistedSession persists only `queue.orderedItems` — the effective play order (history + nowPlaying + upcoming, which under shuffle is the shuffle permutation order) — and discards PlaybackQueue's canonical `items` array and shufflePermutation. On restore, PlaybackQueue.restore (MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:103) sets `shufflePermutation = Array(0..<items.count)` (identity) over the persisted play order. Consequence: before app restart, toggling shuffle off (setShuffle(false), PlaybackQueue.swift:393-404) restores the original album/playlist order from the canonical array; after a restart of a shuffled session, the canonical array IS the shuffled order, so toggling shuffle off silently keeps the shuffled order. Same user action produces different queue order depending on whether the app was relaunched in between — persisted state does not round-trip.

**建议**: Persist the canonical item order plus the current permutation (or per-entry canonical indices) in PersistedPlaybackSession, and have restore rebuild items in canonical order with the saved permutation, instead of flattening to play order with an identity permutation.

#### [LOW] Persisting only the effective shuffled order loses the original queue order across restart

`MuseAmp/Backend/Playback/PlaybackController+Resolution.swift:194`

**问题**: makePersistedSession() persists queue.orderedItems, which for a shuffled queue is the effective play order (history + nowPlaying + upcoming, QueueSnapshot.swift:15-20); the canonical insertion order is never saved. On restore, PlaybackQueue.restore (PlaybackQueue.swift:103) sets items to that shuffled order with an identity shufflePermutation. Before the restart, setShuffle(false) would return the queue to its original (e.g. album) order via the saved canonical indices; after a restart, setShuffle(false) resolves currentCanonical from the identity permutation and the 'unshuffled' queue silently remains in the old shuffled order. The user's original queue ordering is unrecoverably lost across any app relaunch while shuffle is on, producing pre-restart vs post-restart behavioral inconsistency from identical user actions.

**建议**: Persist the canonical item order plus the shuffle permutation (or the canonical index of each effective-order entry) in PersistedPlaybackSession, and have PlaybackQueue.restore rebuild items in canonical order with the saved permutation instead of synthesizing an identity permutation.

### 维度: playlist

#### [LOW] Shuffled cover render is persisted under the canonical cache key without posting playlistArtworkDidUpdate

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:88`

**问题**: image(for:...) with shuffled: true skips cache reads (line 47) but still stores the randomized rendering into memoryCache and the disk file under the SAME canonical cacheKey (lines 88-89), while the `.playlistArtworkDidUpdate` notification is only posted for non-shuffled renders (lines 90-96). 'Regenerate Cover' (PlaylistDetailViewController+Menu.swift:167-193) invalidates all cached files for the playlist, then renders shuffled at sideLength 200 only. Result: (a) the shuffled image becomes the persisted canonical 200pt cover, but no notification fires, so already-rendered surfaces (sidebar via MainController+Sidebar playlistArtworkDidUpdate observer, playlist list cells) keep displaying the old image — persisted cache and visible UI silently disagree; (b) every other size (sidebar 28pt, 'Show Cover' 1200pt) re-renders NON-shuffled with a deterministic arrangement, so after regeneration the same playlist permanently shows two different cover arrangements at different sizes until the next mutation bumps updatedAt.

**建议**: Either don't persist shuffled renders under the canonical key (use a distinct key or return without caching), or treat regeneration as a first-class state change: persist the shuffled arrangement (e.g., a stored seed/ordering), invalidate all sizes, and post .playlistArtworkDidUpdate so every surface re-renders consistently.

#### [LOW] Cover cache disk files keyed by updatedAt are never pruned, growing unboundedly

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:248`

**问题**: cacheKey (lines 248-251) embeds the playlist's updatedAt millisecond timestamp and song count, and savePlaylistEntries bumps updatedAt on every add/remove/move/lyrics change, so each mutation produces a brand-new key and a new PNG written at line 89 — per requested size (200pt detail, 28pt sidebar, list size). Files for superseded keys are never deleted: invalidateCache (lines 24-34) is the only pruning path and is invoked solely from the 'Regenerate Cover' action (PlaylistDetailViewController+Menu.swift:179) for one playlist. Deleted playlists never get their files removed at all. The directory under Caches therefore accumulates one orphan PNG per playlist mutation per rendered size indefinitely; the OS may purge Caches under pressure, but nothing in the app ever reclaims or bounds this storage. (invalidateCache also calls memoryCache.removeAllObjects(), discarding every other playlist's cached covers instead of only the target's.)

**建议**: When writing a freshly rendered image, delete sibling files with the same `v3-<playlistID>-` prefix but a different timestamp; remove cached files in deletePlaylist flows; and in invalidateCache remove only the target playlist's memory keys instead of removeAllObjects().

#### [LOW] Shuffled cover render is persisted under the deterministic cache key for one size only, leaving different surfaces showing different covers

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:89`

**问题**: image(for:...) computes the same cacheKey regardless of `shuffled` (line 44) and unconditionally stores the rendered result into the memory cache and disk file (lines 88-89). regenerateCover (PlaylistDetailViewController+Menu.swift:167-192) invalidates then renders with shuffled=true at sideLength 200, so the random tile arrangement is persisted as the canonical cached cover — but only for the 200pt pixel size. Every other consumer renders at its own size (MainController+Sidebar.swift:244 uses its sidebar size; showCoverPreview uses 1200, PlaylistDetailViewController+Actions.swift:211) and, after the invalidation, re-renders the deterministic arrangement. Result: after 'regenerate cover', the playlist detail header permanently shows one tile arrangement while the sidebar/list and the full-size cover preview/export show a different one — silent inconsistency between persisted cache states for the same playlist. The skipped `.playlistArtworkDidUpdate` post for shuffled renders (line 90) further prevents other views from converging.

**建议**: Persist the shuffle decision rather than its raster: e.g. render the shuffled order once, store the chosen song order (or a seed) so all sizes reproduce the same arrangement, or write the shuffled result for all cached sizes and post .playlistArtworkDidUpdate; alternatively never cache shuffled renders and require an explicit cover commit.

#### [LOW] Timestamped cache keys orphan every previous cover PNG; disk cache grows unboundedly and is never pruned

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:250`

**问题**: cacheKey embeds playlist.updatedAt in milliseconds plus song count (lines 248-251), and savePlaylistEntries bumps updatedAt on every entry mutation (StateStore.swift:310), so each add/remove/move/lyrics edit produces a brand-new key and a new PNG written to disk (line 89). The only deletion path is invalidateCache(for:) (lines 24-34), which is invoked solely from the manual 'regenerate cover' menu action (PlaylistDetailViewController+Menu.swift:179) and only for that one playlist. Nothing ever removes the PNGs keyed by older timestamps, sizes, or deleted playlists (deletePlaylist never touches this cache), so the PlaylistCoverArtworkCache directory accumulates one dead image per mutation per render size indefinitely.

**建议**: When writing a new render, delete sibling files for the same `v3-<playlistID>-` prefix and pixel size (the prefix scan in invalidateCache already shows how), and invalidate the cache directory entry when a playlist is deleted.

### 维度: caches

#### [LOW] updatedAt-versioned cover cache keys are never evicted, so stale PNGs accumulate unboundedly

`MuseAmp/Backend/Playlist/PlaylistCoverArtworkCache.swift:250`

**问题**: cacheKey embeds playlist.updatedAt (ms) and songs.count (line 249-250), and StateStore.savePlaylistEntries bumps updatedAt on every add/remove/move/lyrics edit (StateStore.swift:310). Every playlist mutation therefore creates a new disk PNG per requested size, while files for all previous keys remain: the only deletion path is invalidateCache(for:), which is called solely from the manual regenerateCover action (PlaylistDetailViewController+Menu.swift:179) — never on ordinary playlist mutation or deletion (deletePlaylist leaves all of that playlist's cover files behind permanently). A frequently edited playlist viewed at 3-4 sizes leaks one PNG per size per edit into Library/Caches/PlaylistCoverArtworkCache with no bound and no reader ever matching the old keys again.

**建议**: After a successful write for the current key, delete sibling files with the same `v3-<uuid>-` prefix but a different key (the prefix matching logic already exists in invalidateCache). Also call invalidateCache when a playlist is deleted.

### 维度: playlist

#### [LOW] Playlist export/import round-trip silently drops persisted per-entry lyrics (and artworkURL)

`MuseAmp/Backend/Playlist/PlaylistTransferDocument.swift:20`

**问题**: SongReference (lines 20-37) serializes trackID/title/artist/album/duration/trackNumber but omits PlaylistEntry.lyrics and artworkURL, while the document does faithfully carry coverImageData. lyrics is real persisted user data: AlbumDetailViewController.fetchLyricsInBackground (AlbumDetailViewController.swift:230-243) fetches lyrics per track and persists them into playlist entries via PlaylistStore.updateLyrics after 'Save as Playlist'/add-to-playlist. On import, PlaylistTransferCoordinator (PlaylistTransferCoordinator.swift:59-65) rebuilds entries from AudioTrackRecord.playlistEntry, which sets neither lyrics nor artworkURL (AudioTrackRecord+AppModels.swift:13-23). Exporting a playlist and re-importing it — including on the same device as a backup/restore — silently loses all fetched lyrics, and entries lose their remote artwork template so artwork can only come from the local artwork cache or embedded metadata.

**建议**: Add optional `lyrics` (and `artworkURL`) fields to SongReference, encode them on export, and on import prefer the document values when rebuilding entries (falling back to the local track record).

#### [LOW] Transfer document round trip silently drops per-entry custom lyrics

`MuseAmp/Backend/Playlist/PlaylistTransferDocument.swift:20`

**问题**: SongReference (lines 20-38) serializes trackID/title/artist/album/duration/trackNumber but omits the entry's `lyrics` field, and the import path discards the references entirely in favor of locally rebuilt entries: PlaylistTransferCoordinator.handleImportedFile maps each reference to `track.playlistEntry` (PlaylistTransferCoordinator.swift:59-65), and AudioTrackRecord.playlistEntry constructs the entry with lyrics defaulted to nil (AudioTrackRecord+AppModels.swift:13-23). Per-entry lyrics are real user state — they are written through PlaylistStore.updateLyrics / .updateEntryLyrics and persisted in playlist_entries.lyrics. So exporting a playlist and re-importing it (even on the same device, e.g. as a backup/restore) silently resets every song's chosen lyrics; the import summary reports full success. Same loss applies to the stored artworkURL, though that is mitigated by the cover renderer's local-artwork fallback.

**建议**: Include `lyrics` (and `artworkURL`) in SongReference with encodeIfPresent, and on import prefer the document's per-entry values over the bare track-derived entry when present; the existing version field plus decodeIfPresent keeps old documents compatible.

### 维度: rebuild-scan

#### [LOW] tempFileCount audit metric can never see real staged temp files

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Support.swift:46`

**问题**: tempFileCount lists only the TOP level of paths.audioDirectory (non-recursive contentsOfDirectory) and counts names with a `.tmp` suffix. Both actual temp-file schemes live one level deeper inside album subdirectories: LibraryFileManager.moveToLibrary stages `<album>/<file>.<ext>.tmp` (LibraryFileManager.swift:24), and DownloadManager finalization stages hidden `<album>/.tmp.<file>` prefix files (MuseAmp/Backend/Downloads/DownloadManager+Persistence.swift:18-21). Neither is at the audio root, so AuditSnapshot.stagedTempFiles is structurally always 0 even when crash-leftover staging files exist — note the hidden `.tmp.` prefix files are also skipped by the rebuild scanner (.skipsHiddenFiles at LibraryScanner.swift:28), so they are never cleaned by rebuild either and the audit silently under-reports them forever.

**建议**: Enumerate audioDirectory recursively (without skipping hidden files) and count both `hasSuffix(".tmp")` and `lastPathComponent.hasPrefix(".tmp.")` entries; optionally have the rebuild prune `.tmp.`-prefixed leftovers whose download job no longer exists.

#### [LOW] Failed rebuild never records failure: audit reports stale lastRebuildSucceeded=true and no terminal event follows .indexRebuildStarted

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:27`

**问题**: rebuildIndex sends .indexRebuildStarted (line 21) and only on success writes setLastRebuild(timestamp:succeeded: true) (line 27). There is no catch path: when rebuildIndexFromDisk throws (e.g. the uncaught stat error in LibraryScanner.swift:88), no setLastRebuild(succeeded: false) is written and no failure/finished event is emitted. IndexStore.setLastRebuild is never called anywhere else with false (verified by grep), so auditSnapshot (DatabaseManager+Audit.swift:84) reports lastRebuildSucceeded from the PREVIOUS successful run — i.e. the diagnostics screen claims the last rebuild succeeded after it actually failed, and event subscribers that saw .indexRebuildStarted never receive a terminal event for that run.

**建议**: Wrap the scanner call in do/catch: on error, try? indexStore.setLastRebuild(timestamp: .init(), succeeded: false), emit a failure event (e.g. .indexRebuildFailed or .indexRebuildFinished with an error flag), then rethrow.

### 维度: import-move

#### [LOW] removeTrackSynchronously/removeAlbumSynchronously delete files before index rows, so a failed index delete leaves ghost rows pointing at deleted files

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:131`

**问题**: removeTrackSynchronously removes the audio file (line 131) and caches (line 132) before indexStore.deleteTrack (line 133); removeAlbumSynchronously likewise removes the whole album directory (line 149) before indexStore.deleteAlbum (line 153). If the index delete throws after the file removal succeeds, the throw propagates with no compensation: the track(s) remain in the index and UI with relativePaths that resolve to nothing, so they stay browsable but unplayable until a manual rebuild with pruneInvalidFiles. This is the mirror image of the ingest ordering bug — both write paths order the irreversible filesystem mutation before the fallible database mutation.

**建议**: Invert the order: delete the index row(s) first (the recoverable side — an on-disk file without a row is re-adoptable by rebuild), then remove files and caches, logging but not rethrowing file-removal failures.

### 维度: index-state-store

#### [LOW] last_rebuild_succeeded is never recorded as false, so the audit reports stale success after failed rebuilds

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:27`

**问题**: setLastRebuild(timestamp:succeeded:) is called exactly once in the codebase, with `succeeded: true` after a fully successful rebuild (DatabaseManager+Writes.swift:27). When rebuildIndexFromDisk throws (e.g. the unguarded attributes read, or a WCDB error in upsertTracks/deleteTracks), no failure stamp is written, so IndexStore.lastRebuildSucceeded() (IndexStore.swift:53) keeps returning the previous true and lastRebuildTimestamp keeps the previous date. AuditSnapshot (DatabaseManager+Audit.swift:84-85) then reports lastRebuildSucceeded=true with an old timestamp even though every recent rebuild attempt failed — the one diagnostic surface meant to expose this is silently wrong.

**建议**: Wrap the scanner call in do/catch in rebuildIndex and write `setLastRebuild(timestamp: .init(), succeeded: false)` (best-effort) before rethrowing, so the audit reflects the actual last outcome.

#### [LOW] Schema/format version mismatch is silently stamped over; reset machinery is unreachable

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/DatabaseBootstrapper.swift:35`

**问题**: When the stored index schema/format version differs from DatabaseFormat (line 33), bootstrap() simply rewrites the meta keys to the current versions (lines 35-38) without any migration, reindex, or reset, and DatabaseBootstrapResult.indexResetReason is hardcoded nil (line 64), making DatabaseResetReason.indexVersionMismatch/.stateVersionMismatch/.corruption and the .indexResetStarted/.indexResetFinished events (DatabaseManager.swift:60-63) dead code. If indexFormatVersion is ever bumped because row semantics changed (e.g. trackID derivation or relativePath layout), every existing install will stamp the new version while keeping old-format rows, permanently masking the mismatch — the audit's stateIndexVersionMismatch check (DatabaseManager+Audit.swift:79) can then never fire because the stamp always matches. StateStore.migrateIfNeeded (StateStore.swift:38-44) has the same stamp-only behavior.

**建议**: On version mismatch, either run a real migration or trigger an index rebuild from disk and report the appropriate DatabaseResetReason through DatabaseBootstrapResult instead of stamping the new version unconditionally; only stamp after the corrective action succeeds.

### 维度: rebuild-scan

#### [LOW] Enumeration failure is indistinguishable from an empty library and mass-deletes every index row plus all artwork/lyrics caches

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:30`

**问题**: discoverAudioFiles returns [] when the enumerator cannot be created (line 29-30) and passes no errorHandler to FileManager.enumerator, so per Apple's documented behavior a mid-enumeration I/O error on a subdirectory silently continues, dropping that subtree from the result. rebuildIndexFromDisk has no guard distinguishing 'zero/partial files discovered' from 'user actually has an empty library': deletedPaths = all snapshot keys not seen (line 153), deleteTracks wipes those rows (line 154), and pruneOrphanArtwork/pruneOrphanLyrics (lines 156-157) then delete the corresponding artwork and lyrics cache files. Rows can be re-created by the next successful rebuild, but network-fetched lyrics caches (written only at download time by DownloadLyricsProcessor) are permanently lost because the rebuild's embedded-lyrics re-cache path is dead (see the inspectAudioFile finding), and createdAt/sourceKind are reset. A transient unreadable album directory thus silently degrades the library.

**建议**: Pass an errorHandler to the enumerator that records any enumeration error and abort (throw) the rebuild instead of treating the partial listing as truth. Additionally, refuse the deletion phase (or require an explicit flag) when scanned == 0 while the snapshot is non-empty.

#### [LOW] deletedPaths computation is O(tracks x invalidPaths) due to Array.contains inside filter

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:153`

**问题**: `snapshot.keys.filter { !seenRelativePaths.contains($0) || invalidRelativePaths.contains($0) }` performs a linear scan of the invalidRelativePaths Array for every snapshot key. With a large library (thousands of rows) and many invalid paths (e.g. a directory full of leftover .tmp files or a failing-inspection batch from the prune path), this is quadratic work executed inside the rebuild critical path, on top of the disk I/O. seenRelativePaths is already a Set; invalidRelativePaths is not.

**建议**: Build a `let invalidSet = Set(invalidRelativePaths)` once before the filter and test membership against it.

#### [LOW] forceArtwork clears the whole artwork cache but can only restore embedded artwork

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:54`

**问题**: With forceArtwork=true (Settings 'Rebuild Database' passes it, SettingsViewController+Actions.swift:146), clearArtworkCache() deletes every cached artwork file up front (line 53-55), but the rebuild loop re-writes artwork only from inspection.embeddedArtwork (lines 96-104 and 136-138). Tracks whose artwork exists only as a network-fetched cache file — written by DownloadArtworkProcessor.cachedArtworkData when embedding into the audio file failed or timed out (embed failures are swallowed as warnings in prepareDownloadedTrack) — lose their artwork permanently; the rebuild cannot refetch it and later non-force rebuilds skip unchanged files entirely (lines 92-106). Recovery requires the user to notice and run the manual per-track TrackArtworkRepairService action, which needs network. Additionally, if the rebuild aborts mid-loop (see the line 88 finding), even embedded artwork for not-yet-visited files stays deleted until a full successful re-run.

**建议**: Do not bulk-clear up front. Instead, for each track during the scan, overwrite the cache from embedded artwork when present, and only delete a cache file after confirming a replacement was extracted (or record trackIDs that had cache-only artwork and refetch them via the existing artwork URL pipeline).

### 维度: index-state-store

#### [LOW] Single unreadable file aborts the entire library rebuild

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:88`

**问题**: Inside the per-file loop, `try FileManager.default.attributesOfItem(atPath:)` (line 88) is the only unguarded throwing call: every other per-file failure (invalid path line 68, inspection failure lines 142-149) is handled per-file, but an attributes read failure (file removed between enumeration and processing by the concurrent nonisolated removal path, permission/I-O error, unreadable item dropped into the Audio directory) propagates out of rebuildIndexFromDisk, aborting the whole rebuild before any upserts/deletes are committed (lines 152-154). 'Refresh Library' then fails wholesale every time until the offending file disappears, so index/disk reconciliation is blocked indefinitely, while side effects already performed earlier in the loop (artwork/lyrics cache writes, pruned invalid files) are kept — a partially-applied scan.

**建议**: Wrap the attributes read in the same per-file error handling as inspection: on failure, log via DBLog.warning, count the path as skipped (not invalid, to avoid the prune-deletion path), and continue with the remaining files.

#### [LOW] Rebuild commits upserts and deletes in two separate transactions

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:152`

**问题**: `try indexStore.upsertTracks(upserts)` (line 152) and `try indexStore.deleteTracks(relativePaths: deletedPaths)` (line 154) run as two independent WCDB transactions on the same logical reconciliation. If deleteTracks throws (or the process dies) after upsertTracks committed, rows for files that no longer exist on disk stay live: the UI lists ghost tracks that fail to play, librarySummary over-counts, and cache pruning (lines 155-157, keyed on the now-stale trackIDs set) skips artwork/lyrics that should have been removed. The inconsistency persists until the user manually refreshes again.

**建议**: Expose a single IndexStore method that performs both the upserts and the relative-path deletes inside one `database.run(transaction:)`, so the scan result is applied atomically.

### 维度: playlist

#### [LOW] savePlaylistEntries inserts entry rows even when the parent PlaylistRow does not exist, creating invisible orphan rows

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/StateStore.swift:304`

**问题**: savePlaylistEntries (lines 294-313) inserts all entry rows (lines 300-303) BEFORE checking that the parent PlaylistRow exists; the guard at lines 304-309 merely `return`s from the transaction closure, which commits the already-inserted rows instead of rolling back. addPlaylistEntry (line 171) never validates the playlistID either. Reachable chain: AlbumDetailViewController.saveAlbumAsPlaylist (AlbumDetailViewController.swift:204-211) calls PlaylistStore.createPlaylist, which on a DB write failure logs and returns the unsaved candidate (PlaylistStore.swift:45 `playlist(for: id) ?? candidate`); the subsequent `entries.forEach { addSong($0, to: playlist.id) }` then inserts one orphan PlaylistEntryRow per track for a playlistID that has no PlaylistRow. fetchPlaylists only maps PlaylistRows, so these rows are invisible to the UI, are never cleaned (deletePlaylist only deletes by a known id; the audit unresolvedPlaylistEntryCount checks trackIDs, not orphaned playlistIDs), and silently inflate playlistEntryCount forever. The same hole applies to any add against a just-deleted playlist id.

**建议**: In savePlaylistEntries, fetch/verify the parent PlaylistRow FIRST and throw (rolling back the transaction) when it is missing; alternatively add a periodic cleanup that deletes PlaylistEntryRows whose playlistID has no PlaylistRow.

### 维度: index-state-store

#### [LOW] savePlaylistEntries commits orphan playlist_entries rows when the playlist row is missing

`MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/StateStore.swift:304`

**问题**: Inside the savePlaylistEntries transaction the entry rows are inserted FIRST (lines 300-303) and only afterwards is the playlist row fetched; if it does not exist the closure does a plain `return` (lines 304-309), which COMMITS the transaction with the freshly inserted entries. Any call of addPlaylistEntry/updateEntryLyrics/clearPlaylistEntries with a stale playlist ID (playlist deleted moments earlier — deletion events reach PlaylistStore asynchronously via Combine on the main queue, PlaylistStore+Support.swift:15-28, so a queued user action can still target the dead ID) permanently writes playlist_entries rows whose playlistID matches no playlist. They are invisible to fetchPlaylists/makePlaylist, are never garbage-collected (deletePlaylist only removes entries for IDs being deleted), inflate playlistEntryCount() in the audit, and are not counted by unresolvedPlaylistEntryCount (which only validates trackIDs, lines 277-284).

**建议**: Check playlist existence at the top of the transaction and abort (throw or return before inserting) when the playlist row is absent; optionally add a sweep that deletes playlist_entries whose playlistID has no matching playlists row.

### 维度: rebuild-validation-gap

#### [LOW] inspectAudioFile closure is duplicated verbatim between iOS and tvOS bootstrap instead of shared, guaranteeing drift when validation is added

`MuseAmpTV/Application/TVAppContext+Bootstrap.swift:88`

**问题**: EmbeddedMetadataReader.swift itself is shared with the TV target via relative symlink (MuseAmpTV/Backend/Library/EmbeddedMetadataReader.swift -> ../../../MuseAmp/Backend/Library/EmbeddedMetadataReader.swift, verified with ls -la), but the ~40-line inspectAudioFile closure at TVAppContext+Bootstrap.swift:88-127 is a byte-for-byte duplicate of AppEnvironment+Bootstrap.swift:83-122 in a regular (non-symlinked) file. Both closures contain the identical unvalidated path: stat with `fileSize ?? 0` / `modifiedAt ?? now` fallbacks, makeTrackRecord with no readability/playability/duration checks, and sourceKind hardcoded to .unknown (which is how rebuild-indexed tracks lose their .downloaded/.imported provenance). Any fix for the validation gap applied to the iOS closure will silently not apply to tvOS rebuild/ingest, and vice versa.

**建议**: Hoist the closure body into the already-symlinked shared layer — e.g. a static EmbeddedMetadataReader.inspect(fileURL:paths:) returning AudioFileInspection — and have both makeRuntimeDependencies implementations delegate to it, so the readability/playability/duration validation lives in exactly one compiled-into-both-targets place.

## B. 其余未验证的 clarity 发现

- [HIGH/docs-sync] `AGENTS.md:22` — MuseAmpInterfaceKit package does not exist on disk
- [HIGH/docs-sync] `AGENTS.md:315` — Entire MuseAmpInterfaceKit Package Reference entry is fictional; key types live in app targets
- [HIGH/docs-sync] `AGENTS.md:22` — MuseAmpInterfaceKit package listed in Top Level does not exist on disk
- [HIGH/docs-sync] `AGENTS.md:315` — Package Reference section documents nonexistent MuseAmpInterfaceKit package
- [HIGH/error-boundaries] `MuseAmp/Interface/Sync/SyncContentPickerViewController.swift:252` — loadData discards thrown database errors with no log and no user feedback
- [HIGH/seams-duplication] `MuseAmp/Interface/Sync/SyncServerStatusViewController.swift:307` — Stack-scroll helper set copy-pasted across four Sync controllers with signature drift
- [HIGH/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/RuntimeDependencies.swift:21` — Five of six RuntimeDependencies closures are never called by the package
- [HIGH/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Playback.swift:134` — Transition-publish sequence duplicated across loadAndPlay, continueWithCurrentEngineItem, and restorePlayback
- [HIGH/seams-duplication] `MuseAmpTV/Application/TVAppContext+Bootstrap.swift:65` — makeRuntimeDependencies is a verbatim ~75-line copy of AppEnvironment+Bootstrap
- [HIGH/seams-duplication] `MuseAmpTV/Application/TVAppContext+Bootstrap.swift:65` — makeRuntimeDependencies duplicated verbatim between AppEnvironment and TVAppContext bootstrap
- [HIGH/seams-duplication] `MuseAmpTV/Backend/Sync/TVSessionStateAdapter.swift:428` — Tail of receiveTransfer duplicates importAndComplete nearly verbatim
- [HIGH/seams-duplication] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricParser.swift:3` — TVLyricParser/Timeline/Line/Progress are verbatim copies of the iOS lyric engine
- [HIGH/seams-duplication] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricParser.swift:3` — TV lyric model layer is a rename-only fork of the iOS lyric model layer (5 files)
- [HIGH/named-constants] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:152` — Magic sentinel host "example.com" encodes hidden cross-module contract
- [MEDIUM/repository-conventions] `AGENTS.md:100` — AGENTS.md documents Sync-only symlink mirroring; actual coverage spans nine subdomains
- [MEDIUM/docs-sync] `AGENTS.md:140` — Cell Rules attribute TableBaseCell to nonexistent MuseAmpInterfaceKit
- [MEDIUM/docs-sync] `AGENTS.md:52` — Interface/Common 'compatibility shims into MuseAmpInterfaceKit' claim describes a migration that does not exist
- [MEDIUM/docs-sync] `AGENTS.md:66` — LyricTimelineView no longer lives in NowPlaying/Components; LyricTimeline/ subdirectory is undocumented
- [MEDIUM/docs-sync] `AGENTS.md:27` — Application/ 'contains only' file list omits MacCatalystTerminationPolicy.swift
- [MEDIUM/docs-sync] `AGENTS.md:16` — Top Level section omits real top-level directories Website/, MuseAmpTests/, and Resources/
- [MEDIUM/docs-sync] `AGENTS.md:100` — Symlink mirroring rule documented only for Backend/Sync but actually spans most of MuseAmpTV/Backend
- [MEDIUM/docs-sync] `AGENTS.md:140` — Cell rule attributes TableBaseCell to MuseAmpInterfaceKit; it is an app-target file
- [MEDIUM/docs-sync] `AGENTS.md:27` — Application layer 'contains only' file list omits MacCatalystTerminationPolicy.swift
- [MEDIUM/docs-sync] `AGENTS.md:66` — LyricTimelineView documented under NowPlaying/Components/ but lives in undocumented NowPlaying/LyricTimeline/
- [MEDIUM/docs-sync] `AGENTS.md:100` — tvOS symlink mirroring documented only for Backend/Sync but actually spans nearly all Backend subdomains
- [MEDIUM/docs-sync] `AGENTS.md:49` — MuseAmpTV Interface subdirectories beyond Root/ are undocumented
- [MEDIUM/state-modeling] `MuseAmp/Interface/NowPlaying/Components/NowPlayingRelaxedShellView.swift:15` — currentRightPanel state duplicated between shell view and controller
- [MEDIUM/abstraction-levels] `MuseAmp/Interface/NowPlaying/Components/TransportView/NowPlayingTransportView+Navigation.swift:16` — Transport view performs app-root navigation by digging into MainController
- [MEDIUM/abstraction-levels] `MuseAmp/Interface/NowPlaying/ViewModel/Queue/AMNowPlayingQueueSnapshotBuilder.swift:26` — Pure view-model builder reaches into a UIKit view for identity scheme and limits
- [MEDIUM/repository-conventions] `MuseAmp/Interface/Playlist/PlaylistCell.swift:67` — layer.removeAllAnimations() used despite explicit AGENTS.md ban
- [MEDIUM/function-design] `MuseAmp/Interface/Playlist/PlaylistDetailViewController+Menu.swift:57` — Rename action removed post-hoc by matching its localized title string
- [MEDIUM/repository-conventions] `MuseAmp/Interface/Playlist/PlaylistDetailViewController.swift:124` — Clean-title setting change triggers tableView.reloadData() instead of snapshot reconfigure
- [MEDIUM/state-modeling] `MuseAmp/Interface/Playlist/PlaylistViewController+Table.swift:158` — targetedPreview derives the row from sortedPlaylists instead of the diffable snapshot
- [MEDIUM/seams-duplication] `MuseAmp/Interface/Playlist/PlaylistViewController.swift:432` — applyPlaylistsSnapshot and applySearchSnapshot are near-identical duplicates
- [MEDIUM/seams-duplication] `MuseAmp/Interface/Root/BootProgressController.swift:80` — BootProgressController fork drift: TV localized 'Boot Failed', iOS still hardcodes it
- [MEDIUM/file-organization] `MuseAmp/Interface/Search/SearchState.swift:47` — SearchState.swift is a grab-bag: persistence store bundled with view state types
- [MEDIUM/naming] `MuseAmp/Interface/Search/SearchViewController+Search.swift:135` — reorderSections is hand-compressed with cryptic single-letter names
- [MEDIUM/state-modeling] `MuseAmp/Interface/Search/SearchViewController+Search.swift:169` — SearchSection conflates result kinds with the loading placeholder, forcing dead .loading branches
- [MEDIUM/repository-conventions] `MuseAmp/Interface/Search/SearchViewController+Table.swift:142` — History table uses a classic data source with manual deleteRows/reloadData
- [MEDIUM/repository-conventions] `MuseAmp/Interface/Search/SearchViewController.swift:276` — Error background view rebuilt from scratch on every applySnapshot
- [MEDIUM/repository-conventions] `MuseAmp/Interface/Settings/LogViewerController.swift:159` — LogViewerController bypasses the diffable data source mandate with raw cells
- [MEDIUM/naming] `MuseAmp/Interface/Settings/LogViewerController.swift:296` — allLines is misnamed and parseLogLines hides filtering plus a category side effect
- [MEDIUM/naming] `MuseAmp/Interface/Settings/ServerProfileImportCoordinator.swift:26` — Closure named validateConfiguration actually persists the configuration with rollback
- [MEDIUM/error-boundaries] `MuseAmp/Interface/Sync/SyncContentPickerViewController.swift:392` — resolveSelectedTracks swallows album-track query errors with unlogged try?
- [MEDIUM/seams-duplication] `MuseAmp/Interface/Sync/SyncPlaylistAppleTVSenderViewController.swift:631` — makeQRCodeView/makeQRCodeImage duplicated verbatim from SyncServerStatusViewController
- [MEDIUM/error-boundaries] `MuseAmp/Interface/Sync/SyncQRCodeScannerViewController.swift:119` — Capture-session setup failure is silent (try? + guard return without logging)
- [MEDIUM/seams-duplication] `MuseAmp/Interface/Sync/SyncReceiverViewController.swift:348` — Single-button OK alert scaffolding reimplemented in seven-plus call sites
- [MEDIUM/state-modeling] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager.swift:26` — Initialization lifecycle modeled as three optionals plus a bool, producing impossible-state fallbacks
- [MEDIUM/named-constants] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/CacheCoordinator.swift:62` — Cache file extensions "jpg"/"lrc" duplicated between CacheCoordinator and LibraryPaths
- [MEDIUM/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/DatabaseBootstrapper.swift:64` — Index-reset event machinery is unreachable: indexResetReason is always nil
- [MEDIUM/naming] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/DownloadCoordinator.swift:42` — pauseAll()/resumeAll() are no-ops whose names promise behavior that does not exist
- [MEDIUM/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/DownloadCoordinator.swift:27` — Canonical '<albumID>/<trackID>.<ext>' relative path is hand-built in three places
- [MEDIUM/named-constants] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryFileManager.swift:24` — Staging suffix ".tmp" is a load-bearing literal spread across three files
- [MEDIUM/abstraction-levels] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:48` — rebuildIndexFromDisk mixes orchestration with per-file string parsing in one 120-line function
- [MEDIUM/error-boundaries] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:71` — Invalid-file pruning deletes files with silent try? and the block is duplicated
- [MEDIUM/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:168` — Empty-directory removal implemented separately in LibraryScanner and LibraryFileManager
- [MEDIUM/naming] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/StateStore.swift:209` — importLegacyPlaylists is the canonical playlist-replace operation, not a legacy import
- [MEDIUM/error-boundaries] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/StateStore.swift:14` — StateStore stores a logger it never uses; all state writes are unlogged
- [MEDIUM/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/StateStore.swift:54` — activeDownloads() re-encodes the 'active' status set that DownloadJobStatus.isActive already defines
- [MEDIUM/naming] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/LibraryCommandResult.swift:11` — Result case named `none` collides with Optional.none in the optional-returning command path
- [MEDIUM/error-boundaries] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/AudioSession/AudioSessionManager.swift:105` — Silent try? on audio session activate/deactivate despite available logger
- [MEDIUM/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Engine/AudioPlaybackEngine.swift:12` — Speculative protocol requirements: rate and hasAdvancedToPreloadedItem are never used
- [MEDIUM/state-modeling] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/MediaCenter/RemoteCommandManager.swift:12` — Write-only stored property: weak var player is assigned but never read
- [MEDIUM/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Playback.swift:147` — Item-failure handling (NSError construction + advance-or-stop) duplicated in two files
- [MEDIUM/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer.swift:203` — Four-argument like-command refresh repeated verbatim at five call sites
- [MEDIUM/state-modeling] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer.swift:67` — Asymmetric side effects between shuffled and repeatMode setters
- [MEDIUM/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue+Shuffle.swift:40` — Three unused permutation helpers (dead code in tricky index domain)
- [MEDIUM/file-organization] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:482` — Dead private method rebuildShufflePermutationIndices with a factually false comment
- [MEDIUM/repository-conventions] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:169` — Misleading comments in rewind() contradict the actual logic
- [MEDIUM/seams-duplication] `MuseAmpTV/Application/TVAppContext+Bootstrap.swift:136` — configureImageRequestAuthorization drift: TV copy lost the Kingfisher cache limits
- [MEDIUM/state-modeling] `MuseAmpTV/Application/TVAppContext+Session.swift:14` — Per-app identity state stored as static type-level properties
- [MEDIUM/repository-conventions] `MuseAmpTV/Application/TVSceneDelegate.swift:42` — Direct UIView.transition for window-root swap instead of Interface wrapper
- [MEDIUM/seams-duplication] `MuseAmpTV/Backend/Sync/TVSessionStateAdapter.swift:333` — Session-save failure fallback block triple-duplicated
- [MEDIUM/named-constants] `MuseAmpTV/Backend/Sync/TVSessionStateAdapter.swift:404` — Disconnect-detection heuristic magic numbers duplicated
- [MEDIUM/state-modeling] `MuseAmpTV/Backend/Sync/TVSessionStateAdapter.swift:222` — Pending transferReadyContinuation never resumed on cancel paths
- [MEDIUM/seams-duplication] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricEdgeFadeView.swift:54` — Private-API variable-blur implementation duplicated in TVLyricEdgeFadeView
- [MEDIUM/seams-duplication] `MuseAmpTV/Interface/NowPlaying/TVNowPlayingController.swift:176` — Playback item ID parsing duplicated inline with no canonical inverse
- [MEDIUM/class-design] `MuseAmpTV/Interface/Pairing/TVQRPairingView.swift:100` — configure(content:) ignores most of AMTVUploadWaitingContent; instruction text duplicated
- [MEDIUM/abstraction-levels] `MuseAmpTV/Interface/Root/TVRootBackgroundView.swift:119` — Raw pixel-bucketing palette algorithm with unnamed thresholds inline in a view
- [MEDIUM/error-boundaries] `MuseAmpTV/Interface/Root/TVRootViewController.swift:397` — presentStatusAlert lacks the presented-VC guard; consumed pending alert can be lost
- [MEDIUM/class-design] `MuseAmpTV/Interface/Transfer/TVTransferProgressView.swift:59` — configure(content:) discards content.title and content.progress
- [MEDIUM/error-boundaries] `SubsonicClientKit/Sources/SubsonicClientKit/Models/Subsonic/SubsonicResponse.swift:30` — Payload decoded even when Subsonic status is not ok
- [MEDIUM/seams-duplication] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:117` — playback(id:) reimplements the perform() cache pipeline inline
- [MEDIUM/function-design] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:194` — perform() duplicates its decode→cache→return tail in the auth-fallback branch
- [MEDIUM/file-organization] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:691` — KeyedDecodingContainer lossy-decoding extension buried at tail of service file
- [MEDIUM/named-constants] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:592` — Resource-type literals "songs"/"albums"/"artists" repeated across mappers and into the app
- [LOW/docs-sync] `AGENTS.md:160` — Documented amusic.* notification name list is incomplete
- [LOW/docs-sync] `AGENTS.md:52` — Stale claim about compatibility shims forwarding into MuseAmpInterfaceKit
- [LOW/docs-sync] `AGENTS.md:16` — Top Level section omits real top-level directories Website/ and MuseAmpTests/
- [LOW/docs-sync] `AGENTS.md:160` — Documented amusic.* notification list is incomplete
- [LOW/error-boundaries] `MuseAmp/Backend/Sync/SyncServer.swift:531` — Silent try? handle.close() without log trace
- [LOW/function-design] `MuseAmp/Backend/Sync/SyncServer.swift:35` — receiveOutcome is a pure pass-through to underscore twin
- [LOW/function-design] `MuseAmp/Interface/NowPlaying/Components/NowPlayingQueueHeaderCell.swift:200` — removeAnimation(forKey: "queueShuffleFade") removes a key that is never added
- [LOW/seams-duplication] `MuseAmp/Interface/NowPlaying/Components/TransportView/NowPlayingTransportView+Navigation.swift:5` — Two hand-rolled responder-chain walks duplicate each other and SwifterSwift's parentViewController
- [LOW/repository-conventions] `MuseAmp/Interface/Playlist/PlaylistCell.swift:14` — Unbounded NSCache used where the repo standard is LRUCache
- [LOW/named-constants] `MuseAmp/Interface/Playlist/PlaylistDetailViewController+Actions.swift:72` — Magic fallback string "unknown" used as an album ID
- [LOW/naming] `MuseAmp/Interface/Playlist/PlaylistDetailViewController.swift:165` — handlePlaylistsDidChange exists only to call handlePlaylistStoreDidChange
- [LOW/mechanical-consistency] `MuseAmp/Interface/Playlist/PlaylistDetailViewController.swift:238` — Optional() wrapper hack to get a mutable snapshot binding inside guard
- [LOW/repository-conventions] `MuseAmp/Interface/Playlist/PlaylistDetailViewController.swift:301` — Redundant selectionStyle assignments contradict the TableBaseCell contract
- [LOW/function-design] `MuseAmp/Interface/Playlist/PlaylistTransferCoordinator.swift:147` — PlaylistTransferDocument constructed twice in makeExportFile
- [LOW/seams-duplication] `MuseAmp/Interface/Playlist/PlaylistViewController+Search.swift:16` — Empty-query reset block duplicated between updateSearchResults and scheduleSearch
- [LOW/named-constants] `MuseAmp/Interface/Playlist/PlaylistViewController.swift:113` — Random-playlist size options are inline magic numbers and the default count is dead
- [LOW/seams-duplication] `MuseAmp/Interface/Playlist/PlaylistViewController.swift:398` — Five sort branches repeat the same name tiebreak comparator
- [LOW/mechanical-consistency] `MuseAmp/Interface/Search/SearchViewController+Search.swift:41` — Scattered semicolon-joined statements diverge from repo formatting
- [LOW/naming] `MuseAmp/Interface/Settings/ConfigurableInfoView.swift:12` — valueLabel names a button and use(menu:) hides its effect
- [LOW/named-constants] `MuseAmp/Interface/Settings/ServerProfileImportCoordinator.swift:52` — Subsonic-config UTI and export file name are inline string literals
- [LOW/seams-duplication] `MuseAmp/Interface/Settings/SettingsViewController.swift:107` — Downloads explain copy duplicated between makeDownloadsObject and refreshDownloadsExplain
- [LOW/seams-duplication] `MuseAmp/Interface/Sync/SyncContentPickerViewController.swift:189` — Disk-artwork load closure duplicated inside the cell provider without a stale-reuse guard
- [LOW/seams-duplication] `MuseAmp/Interface/Sync/SyncTransferProgressViewController.swift:368` — popToRoleSelection duplicated verbatim from SyncServerStatusViewController
- [LOW/function-design] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Audit.swift:11` — auditSnapshot() is declared async with no await and hides an event side effect behind a noun name
- [LOW/function-design] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Audit.swift:38` — libraryScanner() factory invoked once per audited file inside the reduce closure
- [LOW/named-constants] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Commands.swift:114` — NSError codes 0/1/2/4/5 are unexplained magic numbers across five throw sites
- [LOW/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:123` — Dead @DatabaseActor wrappers removeTrack(trackID:)/removeAlbum(albumID:)
- [LOW/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:78` — Lyrics-resolution expression computed twice in ingestAudioFile
- [LOW/error-boundaries] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/DatabaseManager+Writes.swift:74` — artworkCacheChanged/lyricsCacheChanged events fire even when the try? cache write failed
- [LOW/error-boundaries] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/CacheCoordinator.swift:34` — removeTrackCaches swallows artwork deletion failure without logging
- [LOW/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/IndexStore.swift:202` — clearTracks() has no callers
- [LOW/named-constants] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/LibraryScanner.swift:94` — Magic 0.5-second modification-date tolerance
- [LOW/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Internal/StateStore.swift:324` — Meta-table accessor trio duplicated verbatim across both stores with inline key strings
- [LOW/seams-duplication] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Logging/DatabaseLogger.swift:52` — DBLog static shim is a pure pass-through over DatabaseLogger's own methods
- [LOW/error-boundaries] `MuseAmpDatabaseKit/Sources/MuseAmpDatabaseKit/Storage/LyricsCacheStore.swift:23` — lyrics(for:) logs a warning on every routine cache miss
- [LOW/state-modeling] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/AudioSession/AudioSessionManager.swift:15` — Optional stored callback properties that are only ever read back within the same call
- [LOW/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/AudioSession/AudioSessionManager.swift:118` — teardown() is never called by anything
- [LOW/naming] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/MediaCenter/MediaCenterCoordinator.swift:152` — SessionMediaCenterBackend logs under the component name MediaCenterCoordinator
- [LOW/state-modeling] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/MediaCenter/RemoteCommandManager.swift:126` — updateLikeCommand never clears localizedShortTitle when nil
- [LOW/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/MediaCenter/RemoteCommandManager.swift:131` — register/unregister maintain parallel hand-written command lists
- [LOW/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Observation.swift:110` — End-of-queue sequence (didReachEndOfQueue + stop) duplicated at five sites
- [LOW/named-constants] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Playback.swift:84` — Magic preferredTimescale 600 repeated across three files
- [LOW/abstraction-levels] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Playback.swift:202` — preloadNextItem builds a full snapshot to read one upcoming item
- [LOW/seams-duplication] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer+Restoration.swift:39` — Session/observer bring-up preamble duplicated from startPlayback
- [LOW/named-constants] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer.swift:200` — Default Like title literal duplicated
- [LOW/repository-conventions] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer.swift:76` — timeUpdateInterval default (0.1) contradicts AGENTS.md documented default (0.25s)
- [LOW/naming] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Player/MusicPlayer.swift:98` — Boolean property currentItemLiked lacks is-prefix
- [LOW/early-return] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:246` — insert(_:at:) uses two mutually exclusive if-blocks and a self-contradictory comment
- [LOW/named-constants] `MuseAmpPlayerKit/Sources/MuseAmpPlayerKit/Queue/PlaybackQueue.swift:152` — Inline 3.0-second restart threshold in rewind()
- [LOW/naming] `MuseAmpTV/Application/TVAppContext+Bootstrap.swift:136` — configureImageRequestAuthorization does not configure authorization
- [LOW/seams-duplication] `MuseAmpTV/Application/TVAppContext+Session.swift:14` — Pairing code generation reimplements SyncPasswordGenerator inline
- [LOW/function-design] `MuseAmpTV/Application/TVAppContext+Session.swift:66` — Repeat-mode policy duplicated and twin if/!if on one boolean
- [LOW/early-return] `MuseAmpTV/Application/TVAppContext+Session.swift:146` — Dead `return started` always returns true
- [LOW/seams-duplication] `MuseAmpTV/Application/TVAppContext+Session.swift:199` — tvSessionPlaybackTrack re-implements AudioTrackRecord.playbackTrack(paths:) with subtle drift
- [LOW/named-constants] `MuseAmpTV/Application/TVAppContext.swift:36` — Inline 5.0-second user-interaction window
- [LOW/named-constants] `MuseAmpTV/Backend/Sync/TVSessionStateAdapter.swift:688` — Unexplained placeholder port 1 in receiver advertisement
- [LOW/seams-duplication] `MuseAmpTV/Interface/Common/Interface.swift:9` — TV Interface animation wrapper is a verbatim subset copy instead of a symlink
- [LOW/named-constants] `MuseAmpTV/Interface/Common/TVTransportButton.swift:56` — Focus/idle alpha literals repeated across four sites
- [LOW/file-organization] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricEdgeFadeView.swift:33` — Empty layoutSubviews override and uncommented no-op traitCollectionDidChange
- [LOW/repository-conventions] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricTimelineView.swift:203` — Direct UIView.transition in applySnapshot
- [LOW/repository-conventions] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricTimelineView.swift:375` — Classic UITableViewDataSource instead of mandated diffable data source
- [LOW/class-design] `MuseAmpTV/Interface/NowPlaying/Lyrics/TVLyricTimelineView.swift:64` — Internal subjects and deadline exposed without external consumers
- [LOW/named-constants] `MuseAmpTV/Interface/NowPlaying/TVNowPlayingContentView.swift:54` — Hardcoded 128pt spacers bypass the layout-constants enum
- [LOW/named-constants] `MuseAmpTV/Interface/NowPlaying/TVNowPlayingController.swift:191` — Seek step and scrub cooldown literals duplicated
- [LOW/seams-duplication] `MuseAmpTV/Interface/NowPlaying/TVNowPlayingLyricsCoordinator.swift:47` — Two near-identical cached-lyrics branches; cache paths skip task cancellation
- [LOW/file-organization] `MuseAmpTV/Interface/Pairing/TVQRPairingView.swift:184` — Dead private helper isMacDevice
- [LOW/seams-duplication] `MuseAmpTV/Interface/Pairing/TVQRPairingView.swift:194` — makeQRCodeImage CIQRCodeGenerator helper duplicated across targets
- [LOW/repository-conventions] `MuseAmpTV/Interface/Root/TVRootBackgroundView.swift:32` — Unbounded dictionary cache where AGENTS prescribes LRUCache
- [LOW/file-organization] `MuseAmpTV/Interface/Root/TVRootViewController.swift:59` — Stored state scattered mid-file across the root controller
- [LOW/abstraction-levels] `SubsonicClientKit/Sources/SubsonicClientKit/Models/Artwork.swift:37` — Unexplained size-query filtering inside resolvedURLString
- [LOW/mechanical-consistency] `SubsonicClientKit/Sources/SubsonicClientKit/Models/CatalogArtist.swift:10` — CatalogArtist omits Identifiable unlike its sibling catalog models
- [LOW/named-constants] `SubsonicClientKit/Sources/SubsonicClientKit/ResponseCache.swift:25` — Stale window 7 * 24 * 3600 inlined as a default parameter
- [LOW/seams-duplication] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:409` — loadFreshDataFromDisk and loadStaleDataFromDisk are near-identical copies
- [LOW/named-constants] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:324` — Bare Subsonic error codes 40/41 in auth-fallback predicate
- [LOW/state-modeling] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:604` — mapSong hardcodes hasLyrics: true for every song
- [LOW/error-boundaries] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:470` — Per-song enrichment failures vanish with no trace
- [LOW/function-design] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:475` — Results array seeded by repeating the first song as filler
- [LOW/seams-duplication] `SubsonicClientKit/Sources/SubsonicClientKit/SubsonicMusicService.swift:77` — search() artwork builder uses weak-self/baseURL capture dance unlike sibling closures
