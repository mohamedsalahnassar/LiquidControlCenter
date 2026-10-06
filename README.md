# LiquidControlCenter

An app-owned Control Center with live full-screen blur, Liquid Glass surfaces, mixed-size grids, expanding controls, and finger-tracking presentation. Inspired by iOS 26 and tuned against frame-by-frame screen recordings.

**iOS 16+ · Swift 6.3+ · SwiftUI and UIKit · Glass by LiquidGlassKit · Public APIs**

## Try the sample

Open `Examples/ControlCenterDemo/ControlCenterDemo.xcodeproj`, select **ControlCenterDemo**, and run on an iPhone or iPad simulator. The project is checked in; XcodeGen is only needed after changing `project.yml`.

The sample includes connectivity, media, vertical brightness/volume, focus, utility controls, and three pages. All state is local to the sample. Its settings let you switch to three columns, preview fallback materials, and exercise reduced motion and transparency. Controls demonstrate app actions; they do not modify system Wi-Fi, Bluetooth, recording, or other protected system settings.

For a physical device, choose your development team and override `CODE_SIGNING_ALLOWED` to `YES` in the sample project’s build settings. Signing is disabled by default for simulator use.

## Integrate

Add the package with Swift Package Manager (or the included `LiquidControlCenter.podspec` for CocoaPods-based hosts such as React Native), then link the **LiquidControlCenter** product. No app delegate, global window, screen wrapper, or custom navigation container is required.

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

To let people pull the center open with a finger, like the system, add `.liquidControlCenterPullDown()` to a descendant of the view carrying `.liquidControlCenter`, typically a header. The center tracks the finger and completes or cancels based on position and flick velocity.

Keep the modifier mounted while the center is shown. It uses a transparent UIKit `overFullScreen` presentation, preserving the presenting view for live visual-effect sampling. It covers navigation and tab bars even when attached to a small subview. When attached inside a sheet, it presents over that sheet.

### UIKit, React Native, and Flutter hosts

Hosts without a SwiftUI view tree use `LiquidControlCenterController` directly. The SwiftUI modifier is built on the same controller.

```swift
final class HomeViewController: UIViewController {
    private var quiet = false
    private lazy var center = LiquidControlCenterController(pages: makePages())

    override func viewDidLoad() {
        super.viewDidLoad()
        center.addPullDownGesture(to: headerView)   // optional finger-tracking presentation
        center.onDismiss = { /* analytics, state sync */ }
    }

    @objc func openControls() { center.present(from: self) }

    private func makePages() -> [ControlCenterPage] {
        [ControlCenterPage("main", title: "Quick settings", systemImage: "switch.2") {
            ControlTile("quiet", label: "Quiet mode", tint: quiet ? .indigo : nil, action: { [weak self] in
                guard let self else { return }
                quiet.toggle()
                center.pages = makePages()   // push new state into the presented tiles
            }) { [quiet] _ in
                ControlCenterLabel("Quiet mode", systemImage: quiet ? "moon.fill" : "moon")
            }
        }]
    }
}
```

`present(from:)` falls back to the top-most view controller of the key window when no presenter is given, which suits a native module bridged into a React Native or Flutter app. `dismiss()` is safe to call at any time and `isPresented` reports the requested state. The sample's `--uikit-host` launch argument shows a complete UIKit screen.

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
configuration.allowsInteractiveDismissal = true
configuration.motion = .init(response: 0.5, dampingFraction: 0.84,
                             stagger: 0.026, dismissalDuration: 0.34)
```

Pass this as `configuration:` to the modifier (or set it on `LiquidControlCenterController`). Settings also cover title, horizontal padding, backdrop dimming, background-tap dismissal, swipe-to-dismiss, haptics, and visual fallback/accessibility previews. Invalid numeric configuration values are bounded or replaced with defaults.

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

Tap a page icon or swipe vertically on the trailing rail. You can also swipe horizontally anywhere to page: the grid follows your finger, resists at the first and last page, and settles with a directional slide. Paging is mirrored in right-to-left layouts. Each page independently packs its controls. Conditional tiles, arrays, and loops work in `ControlCenterBuilder`. Page deletion falls back to the first available page; the same tile ID may be reused on different pages.

### Motion and accessibility

Everything visible derives from a single presentation progress: the live backdrop blur, the dimming, the header and page rail, and every tile. They share one spring and cannot drift apart. That removes the ghosting where tiles lingered over an already-sharp app, and the pop when the host disappeared before the tiles finished.

- **Backdrop.** The blur radius is scrubbed with a paused `UIViewPropertyAnimator`, evaluated every animation frame, while the effect view stays at full alpha. The blur leads the tiles slightly, like the system.
- **Tiles.** Tiles unfold downward row by row with a short, bounded stagger. They settle with the opening spring's small overshoot. Closing is critically damped, so it never bounces.
- **Gestures.** Swipe up anywhere outside an interactive control to dismiss. Content follows the finger, and the release decision projects momentum, so a flick closes and a slow, short drag springs back. Pulling down past the top resists with a rubber band. Interactive springs hand the finger's velocity to the release spring, so there is no visible hitch on release. Sliders and buttons keep priority over these gestures.
- **Interruption.** Any animation can be interrupted: reopen during a close, grab during an open, or collapse mid-expansion. Generation tokens stop obsolete completions from dismissing a reopened center.
- **Expansion.** Expansion is one continuous morph. The tile's own surface grows into the panel, its corner radius eases from capsule to rounded rectangle, the compact face crossfades into the expanded content, and the expanded content is laid out once at its final size so text never reflows. The grid dims without blur, because blurring live glass costs an offscreen pass every frame.

Reduce Motion replaces spatial transitions with fades. Reduce Transparency uses opaque surfaces. Buttons expose VoiceOver actions, expanded content has an accessible collapse button, Escape dismisses, and vertical sliders support accessibility adjustment. A stationary hold does not change a vertical slider's value; dragging adjusts it from its starting value. App content remains responsible for its own labels, Dynamic Type layout, contrast, and touch targets.

### Compatibility

- **OS:** iOS 16 and later, iPhone and iPad, all orientations. iOS 16 uses timed animation completions in place of the iOS 17 completion API.
- **Glass:** tiles and the center's own controls are drawn by [LiquidGlassKit](https://github.com/mohamedsalahnassar/LiquidGlassKit): native Liquid Glass on iOS 26 and later, its material fallback on iOS 16–25. Native glass is tinted only when a tile sets `tint` and has no outline, so it follows the system's own glass appearance, which iOS 26.4 renders darker than iOS 27. The material fallback carries the tile's tint and a hairline rim. `forceFallback` exercises the material path on modern systems. `forceReducedMotion` and `forceReducedTransparency` enable those treatments without changing users' system preferences.
- **Toolchain:** Swift 6.3 or later, because LiquidGlassKit's manifest requires it. This package's own manifest declares tools version 6.0.
- **Dependencies:** LiquidGlassKit, pinned to revision `c1dd227…` because upstream has no release tags. Replace the revision with a version tag before publishing a semantic-version release of this package.
- **Package managers:** Swift Package Manager, plus a podspec for CocoaPods-based cross-platform hosts. LiquidGlassKit has no pod, so CocoaPods builds make the same native-or-material choice directly (see `GlassSurface.swift`) and look the same.

The macOS platform declaration supports running the pure layout and motion unit tests with `swift test`. The presentation UI is iOS-only.

## Tests

```sh
swift test
xcodebuild -project Examples/ControlCenterDemo/ControlCenterDemo.xcodeproj \
  -scheme ControlCenterDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -parallel-testing-enabled NO test
```

Select an installed simulator if that destination is unavailable. The sample scheme includes Swift Testing unit tests and XCTest UI tests. Unit tests cover packing, collisions, RTL, decoding, invalid input, slider normalization, presentation interruption, the reveal curve, gesture projection, rubber-banding, and velocity tracking. UI tests exercise real integration, including swipe-to-dismiss and the UIKit host, and keep screenshot attachments in the test result.

Pass `--motion-loop` to the sample to open and close the center every two seconds, which is handy for recording and comparing motion frame by frame.

See [Design](Documentation/Design.md) for references and design decisions.

## Scope

This library recreates the presentation and extensible control surface using public APIs. It is not the system Control Center and does not expose private system toggles. Apple’s private shaders, exact spring constants, status indicators, system power menu, and drag-to-edit control gallery are not reproduced. Arrangement and control behavior are app-defined. The system’s edge gesture remains owned by iOS; open this center with your app’s button, or with `liquidControlCenterPullDown()` / `addPullDownGesture(to:)` on your own views.
