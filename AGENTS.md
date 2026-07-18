# manga Agent Guide

## Project Shape

`manga` is a Swift Package Manager macOS CBZ manga viewer. It is a standard `NSApplication` (not accessory). The entry point is `Sources/manga/App.swift`.

The deployment target is macOS 15.0 or newer.

Core files:

- `App.swift`: `@main` struct, `AppDelegate` for lifecycle, command-line / NSOpenPanel / Finder file opening.
- `ViewerWindow.swift`: `CBZBook` (unzip extraction), `MangaWindowController`, `MangaViewController` (NSScrollView + layout), `PageContainerView` (flipped vertical stack of NSImageViews).

## Build And Run

- `make build` compiles the debug binary, ad-hoc signs, and clears quarantine.
- `make dev` runs `make build` then launches the debug binary (shows NSOpenPanel).
- `swift build` is the underlying SPM build command.

To test with a specific file:

```sh
make build && .build/debug/manga "/path/to/file.cbz"
```

## CBZ Handling

CBZ files are ZIP archives containing images. Extraction uses `/usr/bin/unzip` (no external Swift dependencies). Supported image formats: `.jpg`, `.jpeg`, `.png`, `.webp`.

Entries are sorted with `localizedStandardCompare` for natural sort order. Extraction happens to a temp directory under the system temporary path, cleaned up when the window closes or the `CBZBook` is deallocated.

## Image Preloading

Images are loaded synchronously in `MangaViewController.viewDidLoad` via `NSImage(contentsOfFile:)`. `NSImage` is lazy by default — pixel data is decoded on first draw, not at load time. Each `NSImageView` is layer-backed (`wantsLayer = true`). When Core Animation composites a page for the first time, it decodes the image and caches the GPU texture in the layer. Subsequent scrolls past the same page reuse the cached texture without re-decoding.

All pages are held in memory (no virtualization or discard).

## GPU Cache Attempt (Abandoned)

An attempt was made to pre-decode images into BGRA8 (`CGImageAlphaInfo.premultipliedFirst | CGBitmapInfo.byteOrder32Little`), the native GPU texture format for `CALayer`, by redrawing through a custom `CGContext`. The idea was to eliminate all format conversion on the GPU upload path. This was abandoned because:

1. The extra `CGContext` redraw doubled memory during decode (~660 MB transient for a 44-page chapter) and produced visible blank renders.
2. The format conversion that Core Animation performs internally is fast enough that eliminating it provided no observable benefit.
3. The `CGImageSource`-based decode already avoids scroll jank without the memory penalty.

The code is preserved below for reference if the approach is revisited with a smaller working set or a Metal-based upload path.

```swift
// Decode to BGRA8, the native GPU format for CALayer compositing.
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
    | CGImageAlphaInfo.premultipliedFirst.rawValue
guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else { return nil }
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
let decoded = context.makeImage()
```

## Viewer Layout

Pages are rendered as `NSImageView` subviews (each `wantsLayer = true`) inside a `PageContainerView`. The container overrides `isFlipped` to return `true`, placing origin (0, 0) at top-left so the first page appears at the top of the scroll view.

Images scale proportionally to fit the container width via `NSImageView.imageScaling = .scaleProportionallyUpOrDown`. Vertical layout with no gaps between pages. Scrolling is smooth and continuous — no page snapping.

Window resizes trigger relayout of all pages via `viewDidLayout()` on the view controller. The `PageContainerView.relayout()` method reads `enclosingScrollView.contentSize.width` to determine the new page width and recalculates every image view frame.

## Startup Flow

1. `AppDelegate` opens a CBZ file (command-line arg, NSOpenPanel, or Finder association).
2. A `CBZBook` is created, which runs `/usr/bin/unzip` synchronously in `init` to extract to a temp directory.
3. `MangaWindowController.init` sizes the window and installs the view controller.
4. `MangaViewController.viewDidLoad` loads all images from the temp directory and builds the scroll view.
5. The window is shown via `showWindow(nil)` from `AppDelegate`.
6. On `close()`, the temp directory is removed.

## Editing Notes

Keep changes small and local. This is a compact AppKit codebase. No external dependencies beyond Foundation and AppKit. Prefer preserving existing direct style over adding abstractions.
