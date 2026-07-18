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

The initial page batch is loaded synchronously. Later pages are loaded on a background queue through `CGImageSourceCreateThumbnailAtIndex`, which decodes and downsamples each image to a maximum width of 2400 pixels before it reaches AppKit. This avoids retaining full-resolution manga pages and keeps decoding off the main thread.

The retained page window is capped at 48 pages. When the window advances, pages are evicted from the opposite end. Forward and backward prefetches load up to 8 pages at a time. A new chapter starts by prefetching backward and then forward so scrolling in either direction is ready immediately. Completed prefetches are applied immediately; virtualization keeps this update small enough to avoid making the user wait at the document edge.

`PageContainerView` virtualizes its layer-backed `NSImageView` children. It keeps views for the visible pages plus two viewport-heights of overscan, recycles views that leave that range, and assigns images only when a view enters the range. Page geometry remains based on the retained page window, while offscreen views are not kept in the view hierarchy.

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

## Performance

Keep image decoding, downsampling, and archive access off the main thread. Use ImageIO thumbnail creation rather than loading full-resolution images through `NSImage(contentsOfFile:)`. The 48-page retained window is the memory bound; do not increase it casually because decoded pixel memory is substantially larger than compressed CBZ data.

Keep page view virtualization and view recycling separate from page loading. Loading a page should not create a permanent `NSImageView`, and scrolling should not rebuild the entire page view stack. Prefetch in batches and use the scroll direction and remaining-page threshold to stay ahead of fast scrolling. Completed batches must be applied immediately so the document never ends at an uncommitted prefetch boundary.

The abandoned BGRA8 redraw experiment below is not a preferred optimization. It added substantial transient memory pressure without a measurable scrolling benefit.

## Viewer Layout

Pages are rendered as recycled `NSImageView` subviews (each `wantsLayer = true`) inside a `PageContainerView`. The container overrides `isFlipped` to return `true`, placing origin (0, 0) at top-left so the first page appears at the top of the scroll view.

Images scale proportionally to fit the container width via `NSImageView.imageScaling = .scaleProportionallyUpOrDown`. Vertical layout with no gaps between pages. Scrolling is smooth and continuous — no page snapping.

Window resizes trigger relayout of retained page geometry via `viewDidLayout()` on the view controller. The `PageContainerView.relayout()` method reads `enclosingScrollView.contentSize.width` to determine the new page width, recalculates page frames, and updates only the visible and overscanned image views.

## Startup Flow

1. `AppDelegate` opens a CBZ file (command-line arg, NSOpenPanel, or Finder association).
2. A `CBZBook` is created, which runs `/usr/bin/unzip` synchronously in `init` to extract to a temp directory.
3. `MangaWindowController.init` sizes the window and installs the view controller.
4. `MangaViewController.viewDidLoad` loads all images from the temp directory and builds the scroll view.
5. The window is shown via `showWindow(nil)` from `AppDelegate`.
6. On `close()`, the temp directory is removed.

## Editing Notes

Keep changes small and local. This is a compact AppKit codebase. No external dependencies beyond Foundation and AppKit. Prefer preserving existing direct style over adding abstractions.
