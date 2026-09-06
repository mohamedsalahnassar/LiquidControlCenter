# LiquidControlCenter

An app-owned SwiftUI Control Center with live full-screen blur, LiquidGlassKit surfaces, mixed-size grids, and expanding controls. Inspired by iOS 26 and tuned against screenshots and frame-by-frame screen recordings.

**iOS 16+ · Swift 6.3+ · SwiftUI · Public APIs**

## Try the sample

Open `Examples/ControlCenterDemo/ControlCenterDemo.xcodeproj`, select **ControlCenterDemo**, and run on an iPhone or iPad simulator. The project is checked in; XcodeGen is only needed after changing `project.yml`.

The sample includes connectivity, media, vertical brightness/volume, focus, utility controls, and three pages. All state is local to the sample. Its settings let you switch to three columns, preview fallback materials, and exercise reduced motion and transparency. Controls demonstrate app actions; they do not modify system Wi-Fi, Bluetooth, recording, or other protected system settings.

For a physical device, choose your development team and override `CODE_SIGNING_ALLOWED` to `YES` in the sample project’s build settings. Signing is disabled by default for simulator use.

## Integrate

Add this folder as a local Swift package in Xcode, then link the **LiquidControlCenter** product. No app delegate, global window, screen wrapper, or custom navigation container is required.

```swift
import SwiftUI
import LiquidControlCenter

struct MyScreen: View {
    @State private var showControls = false
    @State private var quiet = false
    @State private var volume = 0.5

    var body: some View {
        Button("Controls") { showControls = true }
            .liquidControlCenter(isPresented: $showControls) {
                ControlTile("quiet", label: "Quiet mode",
                            tint: quiet ? .indigo : nil,
                            action: { quiet.toggle() }) { _ in
                    ControlCenterLabel("Quiet mode", systemImage: "moon.fill")
                }
                .expanded(height: 240) { context in
                    VStack(spacing: 24) {
                        Toggle("Quiet mode", isOn: $quiet)
                        Button("Done", action: context.collapse)
                    }
                }

                ControlTile("volume", size: .tall, label: "Volume") { _ in
                    ControlCenterSlider("Volume", value: $volume,
                                        systemImage: "speaker.wave.2.fill")
                }
            }
    }
}
```

Keep the modifier mounted while the center is shown. It uses a transparent UIKit `overFullScreen` presentation, preserving the presenting view for live visual-effect sampling. It covers navigation and tab bars even when attached to a small subview. When attached inside a sheet, it presents over that sheet.

### Tile content and actions

- Use stable, unique string IDs. The first duplicate wins deterministically.
- `.small` is 1×1, `.wide` is 2×1, `.tall` is 1×2, and `.large` is 2×2. Custom spans support up to 12×12 cells.
- Use `action:` for a simple button tile. Omit it when your content contains buttons, sliders, or other controls, to avoid nested buttons.
- For fully custom tile views (without the default glass surface and button wrapping), initialize the tile with `isCustomView: true`.
- Add `.expanded(height:)` to opt into touch-and-hold expansion. `context.expand()`, `context.collapse()`, and `context.dismiss()` are also available to your content.
- Keep shared state in your app’s bindings or models. Compact and expanded views are distinct view trees; local `@State` in one face is not transferred to the other.
- Content is clipped to its allocated tile shape. Put large or detailed content in the scrollable expanded face.
- `isEnabled: false` blocks interaction and dims the control. Removing or disabling an expanded tile collapses it safely.
- The UIKit hosting boundary forwards locale, layout direction, and Dynamic Type. Explicitly inject app-specific environment objects/values into custom content: `MyControls().environmentObject(model)`.
- Type erasure is confined to the heterogeneous tile-content boundary. Packing, identity, and presentation state are concrete types.

### Arrangement

Tiles pack into the first available space in declaration order. A preferred position is optional:

```swift
ControlTile("player", size: .large,
            position: .init(column: 2, row: 0), label: "Player") { context in
    Button("Expand player", action: context.expand)
}
```

Coordinates are zero-based and mirrored in right-to-left layouts. Preferred positions are handled in declaration order; collisions fall back to first-fit packing. On narrow screens, the grid reduces its column count to preserve 44-point cells, and oversized spans are clamped. Long grids scroll. Persist `ControlTileSize` and `ControlTilePosition` using Codable if your app offers a layout editor; decoded values are validated.

```swift
var configuration = ControlCenterConfiguration()
configuration.columns = 4
configuration.spacing = 14
configuration.horizontalPadding = 28
configuration.maximumWidth = 430
configuration.dimmingOpacity = 0.22
configuration.dismissOnBackgroundTap = true
configuration.motion = .init(response: 0.48, dampingFraction: 0.82,
                             stagger: 0.018)
```

Pass this as `configuration:` to the modifier. Settings also cover title, horizontal padding, backdrop dimming, background-tap dismissal, haptics, and visual fallback/accessibility previews. Invalid numeric configuration values are bounded or replaced with defaults.

### Multiple pages

```swift
let pages = [
    ControlCenterPage("favorites", title: "Favorites", systemImage: "heart.fill") {
        favoriteTiles // [ControlTile]
    },
    ControlCenterPage("home", title: "Home", systemImage: "house.fill") {
        homeTiles
    }
]
// On your screen:
// .liquidControlCenter(isPresented: $showControls, pages: pages)
```

Tap a page icon or swipe vertically on the trailing rail. You can also swipe left or right anywhere on the background to navigate between pages. Each page independently packs its controls. Conditional tiles, arrays, and loops work in `ControlCenterBuilder`. Page deletion falls back to the first available page; the same tile ID may be reused on different pages.

### Motion and accessibility

The backdrop interpolates the actual `UIBlurEffect`; the visual-effect view stays at full alpha. Tiles fade and settle using a configurable spring with a short, capped stagger. Dismissal uses a faster fade; obsolete completion callbacks cannot dismiss a reopened center. Expanded faces share geometry with their compact controls and use a separate glass container to avoid accidental merging with nearby controls.

Reduce Motion replaces spatial transitions with fades. Reduce Transparency uses opaque surfaces. Buttons expose VoiceOver actions, expanded content has an accessible collapse button, Escape dismisses, and vertical sliders support accessibility adjustment. A stationary hold does not change a vertical slider’s value; dragging adjusts from its starting value. App content remains responsible for its own labels, Dynamic Type layout, contrast, and touch targets.

### Compatibility

On iOS 26+, tile surfaces use LiquidGlassKit’s native Liquid Glass path. On iOS 16–25, they use its material fallback. `forceFallback` allows exercising the fallback renderer on modern systems. `forceReducedMotion` and `forceReducedTransparency` can enable those accessibility treatments without disabling users’ system preferences.

The current upstream LiquidGlassKit manifest requires Swift 6.3, despite its README advertising an older toolchain. The dependency is pinned to audited revision `c1dd227…`; upstream has no release tags. Before publishing a semantic-version release of this package, replace that revision requirement with an upstream version tag. No source from LiquidGlassKit is vendored or modified here.

The macOS platform declaration supports running the pure layout/state unit tests with `swift test`; the presentation UI is iOS-only.

## Tests

```sh
swift test
xcodebuild -project Examples/ControlCenterDemo/ControlCenterDemo.xcodeproj \
  -scheme ControlCenterDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -parallel-testing-enabled NO test
```

Select an installed simulator if that destination is unavailable. The sample scheme includes Swift Testing unit tests and XCTest UI tests. Unit tests cover packing, collisions, RTL, decoding, invalid input, slider normalization, and presentation interruption. UI tests exercise real integration and preserve screenshot attachments in the test result.

See [Validation](Documentation/Validation.md) for actual results and [Design](Documentation/Design.md) for references and design decisions.

## Scope

This library recreates the presentation and extensible control surface using public APIs. It is not the system Control Center and does not expose private system toggles. Apple’s private shaders, exact spring constants, status indicators, system power menu, and drag-to-edit control gallery are not reproduced. Arrangement and control behavior are app-defined. The system’s edge gesture remains owned by iOS; open this center with your app’s button or gesture.
