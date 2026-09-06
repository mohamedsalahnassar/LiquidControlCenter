# Design and reference notes

## Sources

- [Apple: Use and customize Control Center, iOS 26](https://support.apple.com/guide/iphone/use-and-customize-control-center-iph59095ec58/ios): four-column mixed-span grid, circular buttons, large rounded groups, vertical sliders, hold-to-expand, bottom-edge dismissal, group navigation.
- [Apple: Meet Liquid Glass, WWDC25 session 219](https://developer.apple.com/videos/play/wwdc2025/219/): Dynamics chapter at 1:29; Adaptivity at 6:00. Primary motion and material reference.
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): glass containers and native effect composition.
- [LiquidGlassKit source](https://github.com/mohamedsalahnassar/LiquidGlassKit/blob/c1dd2276164446c1df417f96984749ab8e6d465a/Sources/LiquidGlassKit/LiquidGlassKit.swift): audited source rather than README claims. Current manifest requires Swift 6.3 and iOS 16; no release tags exist.

Reference media is held locally in ignored `.artifacts/references`, not redistributed with the library.

## Implementation contract

- Public APIs only. This is an app-owned control center; actions and data belong to its host app.
- A transparent UIKit over-full-screen host retains the presenting view for live backdrop sampling and covers navigation/tab chrome even when the modifier is attached to a nested SwiftUI screen.
- The backdrop animates its visual effect itself, rather than fading the alpha of a UIVisualEffectView. Tiles use a separate interruptible SwiftUI spring and short bounded stagger.
- A deterministic first-fit grid supports heterogeneous spans and optional preferred positions. Collisions resolve predictably. Stable tile IDs preserve identity during updates.
- Expandable content originates at the compact tile frame, with its own content transition. Background controls become noninteractive while a tile is expanded.
- Reduce Motion replaces spatial motion with fades. Reduce Transparency uses opaque surfaces. Layout is bounded, scrollable, safe-area aware, and mirrored in right-to-left environments.
- Native Control Center uses private effects and unpublished animation tuning. Timing here is an adjustable approximation, not a claim of pixel or physics parity.

## Commit plan

1. Package and documented reference baseline.
2. Tested grid, configuration, and presentation state.
3. Full-screen presentation, glass tiles, expansion, and reusable controls.
4. Runnable sample, simulator validation, and integration documentation.
