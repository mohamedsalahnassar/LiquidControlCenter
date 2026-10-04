# Design and reference notes

## Sources

- [Apple: Use and customize Control Center, iOS 26](https://support.apple.com/guide/iphone/use-and-customize-control-center-iph59095ec58/ios): four-column mixed-span grid, circular buttons, large rounded groups, vertical sliders, hold-to-expand, bottom-edge dismissal, group navigation.
- [Apple: Meet Liquid Glass, WWDC25 session 219](https://developer.apple.com/videos/play/wwdc2025/219/): Dynamics chapter at 1:29; Adaptivity at 6:00. Primary motion and material reference.
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): glass containers and native effect composition.
- [LiquidGlassKit source](https://github.com/mohamedsalahnassar/LiquidGlassKit/blob/c1dd2276164446c1df417f96984749ab8e6d465a/Sources/LiquidGlassKit/LiquidGlassKit.swift): the original glass shim. Its manifest requires Swift tools 6.3, which forced every consumer onto the newest Xcode. The small part used here (native glass on iOS 26, material before) now lives in `GlassSurface.swift`, guarded by a compiler check.

Reference media is held locally in ignored `.artifacts/references`, not redistributed with the library.

## Implementation contract

- Public APIs only. This is an app-owned control center; actions and data belong to its host app.
- A transparent UIKit over-full-screen host retains the presenting view for live backdrop sampling and covers navigation/tab chrome even when the modifier is attached to a nested SwiftUI screen.
- One presentation progress drives everything. The backdrop blur is scrubbed through a paused `UIViewPropertyAnimator` inside an `Animatable` view, so it follows the same SwiftUI spring as the tiles, frame by frame, and can track a finger. The visual-effect view always stays at full alpha. Tiles derive opacity, scale, and offset from the progress with a bounded per-row delay.
- Opening, closing, and both interactive gestures use the same pipeline. While tracking, interactive springs keep up with the finger, and the release spring inherits their velocity. Release decisions project momentum.
- A deterministic first-fit grid supports heterogeneous spans and optional preferred positions. Collisions resolve predictably. Stable tile IDs preserve identity during updates.
- Expansion is an explicit morph driven by one animatable value: frame from the recorded tile frame to the panel, corner radius, compact→expanded content crossfade, and the collapse button. `matchedGeometryEffect` was dropped because it did not reliably find its source inside the custom grid `Layout`, which made the panel pop in at full size. Background controls become noninteractive while a tile is expanded.
- Reduce Motion replaces spatial motion with fades. Reduce Transparency uses opaque surfaces. Layout is bounded, scrollable, safe-area aware, and mirrored in right-to-left environments.
- SwiftUI mirrors placement itself (`Layout`, `.position`, `.offset`) but reports geometry as it appears on screen (geometry readers, gestures). Grid frames therefore run from the leading edge and SwiftUI mirrors them once; recorded tile frames (the expansion origin) and drag translations go through `LayoutMirroring` before they place anything. `RightToLeftTests` render through SwiftUI to hold both halves of that contract.
- Native Control Center uses private effects and unpublished animation tuning. Timing here is an adjustable approximation, not a claim of pixel or physics parity.

## Motion verification (October 2026)

Motion was compared by recording the simulator (`simctl io recordVideo`) and extracting frames at 30 fps. Before the rewrite, closing removed the blur in about 0.1 s while tiles stayed half-opaque over the sharp app, and the host disappeared with tiles still visible. Opening reached full blur before the tiles were legible. After the rewrite, blur, dimming, chrome, and tiles move together, and nothing is visible when the host is removed. The sample's `--motion-loop` argument reproduces the recording setup.

## Commit plan

1. Package and documented reference baseline.
2. Tested grid, configuration, and presentation state.
3. Full-screen presentation, glass tiles, expansion, and reusable controls.
4. Runnable sample, simulator validation, and integration documentation.

## User-supplied references (6 September 2026)

The two provided screenshots show both four-column mixed controls and two-column wide controls. The first is the primary appearance target: dark live blur, subtle light rims, white/red selected rotation and silent controls, generous pill radii.

The supplied [iOS 26.1 recording](https://www.reddit.com/r/iOSBeta/comments/1oeneta/ios_261_db4_animation_lags_when_swiping_out_of/) was inspected from the user's local MP4, including 65 ms frame intervals around 3.15–3.87 seconds (opening) and 1.20–1.92 seconds (closing). During opening, controls become legible rapidly, settle with a small positional overshoot, and remain anchored to their grid. The source post concerns residual ghosting during closing; that defect is not an intentional target. Apple’s WWDC video was also sampled for material and expansion behavior. These observations inform tuning; the recording does not expose exact touch input or spring parameters.
