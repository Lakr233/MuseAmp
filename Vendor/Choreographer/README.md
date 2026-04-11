# Choreographer

A simple cross-platform library for handling VSync events.

## Supported Platforms

- macOS (10.15+)
- iOS (13.0+)

## Getting Started

In your `Package.swift` manifest file, add the following dependency to your dependencies argument:

```swift
.package(url: "https://github.com/unixzii/Choreographer.git", branch: "main"),
```

Add the dependency to any targets you've declared in your manifest:

```swift
.target(
    name: "MyTarget",
    dependencies: [
        .product(name: "Choreographer", package: "Choreographer"),
    ]
),
```

## Basic Usage

`VSyncObserver` is the primary class in Choreographer to observe VSync signals. You simply create it with the platform-dependent parameters, and you are ready to go.

```swift
import Choreographer

let observer = try VSyncObserver(screen: theScreen)
observer.frameUpdateHandler = { context in
    // Handle the frame update.
    // ...
    // You can also access the target timestamp via `context.targetTimestamp`.
}
```

When you no longer need the observer, you should invalidate it to release the system resources:

```swift
try observer.invalidate()
```

## License

Licensed under MIT License, see [LICENSE](./LICENSE) for more information.
