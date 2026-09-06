import SwiftUI
import LiquidControlCenter

struct LanguageExpandedView: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Change Language")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Switching to \(languageManager.currentLanguage.other.title)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            switch languageManager.switcherStyle {
            case .slide:
                SlideSwitcher(context: context)
            case .orbit:
                OrbitSwitcher(context: context)
            case .hold:
                HoldSwitcher(context: context)
            case .flip:
                FlipSwitcher(context: context)
            case .pillToggle:
                PillToggleSwitcher(context: context)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Slide Switcher
struct SlideSwitcher: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var offset: CGFloat = 0
    @State private var isConfirmed = false
    
    private let trackWidth: CGFloat = 280
    private let pillWidth: CGFloat = 100
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: trackWidth, height: 60)
                
                HStack {
                    Spacer()
                    Text("Slide to \(languageManager.currentLanguage.other.title) ->")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.trailing, 24)
                }
                .frame(width: trackWidth)
                
                Capsule()
                    .fill(Color.white)
                    .frame(width: pillWidth, height: 52)
                    .padding(4)
                    .overlay(Text(languageManager.currentLanguage.other.flag).font(.title2))
                    .offset(x: offset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isConfirmed else { return }
                                if value.translation.width > 0 {
                                    offset = min(value.translation.width, trackWidth - pillWidth - 8)
                                }
                            }
                            .onEnded { value in
                                guard !isConfirmed else { return }
                                if offset > (trackWidth / 2) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        offset = trackWidth - pillWidth - 8
                                        isConfirmed = true
                                    }
                                    Task { await triggerChange() }
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = 0 }
                                }
                            }
                    )
            }
            
            DisclaimerText(visible: offset > 20)
        }
    }
    
    private func triggerChange() async {
        context.dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await languageManager.switchLanguage(to: languageManager.currentLanguage.other)
    }
}

// MARK: - Orbit Switcher
struct OrbitSwitcher: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var isOrbited = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                OrbView(language: languageManager.currentLanguage, isActive: !isOrbited)
                    .offset(x: isOrbited ? 60 : -40)
                    .scaleEffect(isOrbited ? 0.6 : 1.0)
                    .zIndex(isOrbited ? 0 : 1)
                
                OrbView(language: languageManager.currentLanguage.other, isActive: isOrbited)
                    .offset(x: isOrbited ? -40 : 60)
                    .scaleEffect(isOrbited ? 1.0 : 0.6)
                    .zIndex(isOrbited ? 1 : 0)
                    .onTapGesture {
                        guard !isOrbited else { return }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            isOrbited = true
                        }
                        Task { await triggerChange() }
                    }
            }
            .frame(height: 100)
            
            DisclaimerText(visible: isOrbited)
        }
    }
    
    private func triggerChange() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        context.dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await languageManager.switchLanguage(to: languageManager.currentLanguage.other)
    }
}

struct OrbView: View {
    let language: AppLanguage
    let isActive: Bool
    var body: some View {
        Circle()
            .fill(isActive ? Color.blue : Color.white.opacity(0.2))
            .frame(width: 80, height: 80)
            .overlay(
                VStack(spacing: 4) {
                    Text(language.flag).font(.title)
                    Text(language.title).font(.caption2).foregroundColor(.white).bold()
                }
            )
            .shadow(radius: isActive ? 10 : 0)
    }
}

// MARK: - Hold Switcher
struct HoldSwitcher: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var progress: CGFloat = 0.0
    @State private var isConfirmed = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                
                Circle()
                    .fill(isConfirmed ? Color.green : Color.blue)
                    .frame(width: 80, height: 80)
                    .overlay(Text(languageManager.currentLanguage.other.flag).font(.largeTitle))
                    .scaleEffect(isConfirmed ? 1.1 : (progress > 0 ? 0.95 : 1.0))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isConfirmed else { return }
                        withAnimation(.linear(duration: 0.1)) {
                            progress += 0.05
                            if progress >= 1.0 {
                                progress = 1.0
                                isConfirmed = true
                                Task { await triggerChange() }
                            }
                        }
                    }
                    .onEnded { _ in
                        guard !isConfirmed else { return }
                        withAnimation { progress = 0 }
                    }
            )
            
            DisclaimerText(visible: progress > 0.1)
        }
    }
    
    private func triggerChange() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        context.dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await languageManager.switchLanguage(to: languageManager.currentLanguage.other)
    }
}

// MARK: - Flip Switcher
struct FlipSwitcher: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var flipped = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                FlipCard(language: languageManager.currentLanguage.other)
                    .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 1 : 0)
                
                FlipCard(language: languageManager.currentLanguage)
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .opacity(flipped ? 0 : 1)
            }
            .frame(width: 160, height: 100)
            .onTapGesture {
                guard !flipped else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    flipped = true
                }
                Task { await triggerChange() }
            }
            
            DisclaimerText(visible: flipped)
        }
    }
    
    private func triggerChange() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        context.dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await languageManager.switchLanguage(to: languageManager.currentLanguage.other)
    }
}

struct FlipCard: View {
    let language: AppLanguage
    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.1))
            .overlay(
                VStack {
                    Text(language.flag).font(.largeTitle)
                    Text(language.title).font(.headline).foregroundColor(.white)
                }
            )
    }
}

// MARK: - Disclaimer
struct DisclaimerText: View {
    let visible: Bool
    var body: some View {
        Text("App will restart to apply the new language.")
            .font(.caption2)
            .foregroundColor(.white.opacity(0.5))
            .multilineTextAlignment(.center)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut, value: visible)
    }
}

// MARK: - ControlTile Extension
extension ControlTile {
    static func languageTile(languageManager: LanguageManager) -> ControlTile {
        ControlTile("language-switch", size: .wide, label: "Language") { context in
            HStack(spacing: 8) {
                Text(languageManager.currentLanguage.flag)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(languageManager.currentLanguage.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.1))
        }
        .expanded(height: 280) { context in
            LanguageExpandedView(context: context)
                .environmentObject(languageManager)
        }
    }
}

// MARK: - Pill Toggle Switcher
struct PillToggleSwitcher: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var dragOffset: CGFloat = 0
    @State private var isConfirmed = false
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Capsule()
                    .fill(Color(white: 0.95))
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 5)
                    .overlay(
                        Capsule().stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .frame(width: 180, height: 70)
                
                HStack {
                    Text("EN")
                        .font(.title2.weight(.black))
                        .foregroundColor(languageManager.currentLanguage == .english ? Color(red: 0.2, green: 0.25, blue: 0.35) : Color(white: 0.8))
                        .frame(maxWidth: .infinity)
                    
                    Text("AR")
                        .font(.title2.weight(.black))
                        .foregroundColor(languageManager.currentLanguage == .arabic ? Color(red: 0.2, green: 0.25, blue: 0.35) : Color(white: 0.8))
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 160)
                
                // The thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    .overlay(
                        Text(languageManager.currentLanguage.flag)
                            .font(.system(size: 38))
                    )
                    .offset(x: languageManager.currentLanguage == .english ? -55 : 55)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: languageManager.currentLanguage)
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                if (languageManager.currentLanguage == .english && value.translation.width > 30) ||
                                    (languageManager.currentLanguage == .arabic && value.translation.width < -30) {
                                    Task {
                                        withAnimation {
                                            languageManager.currentLanguage = languageManager.currentLanguage.other
                                        }
                                        await triggerChange()
                                    }
                                }
                            }
                    )
            }
            .padding(.top, 20)
            
            DisclaimerText(visible: true)
        }
    }
    
    private func triggerChange() async {
        try? await Task.sleep(nanoseconds: 800_000_000)
        context.dismiss()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await languageManager.switchLanguage(to: languageManager.currentLanguage.other)
    }
}
