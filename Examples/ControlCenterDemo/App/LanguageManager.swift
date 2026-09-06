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
    public var id: String { rawValue }
}

public enum RevealStyle: String, CaseIterable, Identifiable {
    case ripple = "Liquid Ripple"
    case curtain = "Curtain Draw"
    case textZoom = "Typography Zoom"
    case iris = "Iris Unveil"
    public var id: String { rawValue }
}

@MainActor
public class LanguageManager: ObservableObject {
    public static let shared = LanguageManager()
    
    @Published public var currentLanguage: AppLanguage = .english
    @Published public var switcherStyle: SwitcherStyle = .slide
    @Published public var revealStyle: RevealStyle = .ripple
    
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
        
        // Trigger reveal animation
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showRevealAnimation = true
            isReloading = false
        }
        
        // Reset reveal state after animation finishes
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        showRevealAnimation = false
    }
}
