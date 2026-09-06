import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable {
    case english = "en"
    case arabic = "ar"
    
    var title: String {
        switch self {
        case .english: return "English"
        case .arabic: return "العربية"
        }
    }
    
    var flag: String {
        switch self {
        case .english: return "🇺🇸" // Or 🇬🇧
        case .arabic: return "🇸🇦"
        }
    }
    
    var layoutDirection: LayoutDirection {
        switch self {
        case .english: return .leftToRight
        case .arabic: return .rightToLeft
        }
    }
    
    var other: AppLanguage {
        self == .english ? .arabic : .english
    }
}

public enum SwitcherStyle: String, CaseIterable, Identifiable {
    case slide = "Slide to Translate"
    case orbit = "Yin-Yang Orbit"
    case hold = "Liquid Press & Hold"
    case flip = "3D Card Flip"
    case pillToggle = "Pill Toggle"
    public var id: String { rawValue }
}

public enum RevealStyle: String, CaseIterable, Identifiable {
    case ripple = "Liquid Ripple"
    case curtain = "Curtain Draw"
    case textZoom = "Typography Zoom"
    case iris = "Iris Unveil"
    public var id: String { rawValue }
}

public enum LoaderStyle: String, CaseIterable, Identifiable {
    case pulse = "Pulse Globe"
    case rotatingFlags = "Rotating Flags"
    case matrix = "Translation Matrix"
    case morphing = "Liquid Morph"
    public var id: String { rawValue }
}

@MainActor
public class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    
    @Published public var currentLanguage: AppLanguage = .english
    @Published public var switcherStyle: SwitcherStyle = .slide
    @Published public var revealStyle: RevealStyle = .ripple
    @Published public var loaderStyle: LoaderStyle = .pulse
    
    @Published public var isReloading: Bool = false
    @Published public var showRevealAnimation: Bool = false
    @Published public var loadingMessage: String = ""
    
    public init() {}
    
    public func switchLanguage(to newLanguage: AppLanguage) async {
        isReloading = true
        showRevealAnimation = false
        
        let messages = [
            "Connecting to server...",
            "Fetching localized strings...",
            "Applying new language layout...",
            "Almost ready..."
        ]
        
        // Simulate API fetch with progressive messages
        for message in messages {
            loadingMessage = message
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        
        currentLanguage = newLanguage
        
        // Trigger reveal animation (loader stays on screen but its mask animates away)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
            showRevealAnimation = true
        }
        
        // Wait for reveal animation to finish
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Remove from hierarchy without opacity animation because it's already masked out
        isReloading = false
        showRevealAnimation = false
    }
}
