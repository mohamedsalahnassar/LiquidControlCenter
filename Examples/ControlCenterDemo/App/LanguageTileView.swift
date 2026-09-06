import SwiftUI
import LiquidControlCenter

struct LanguageExpandedView: View {
    let context: ControlTileContext
    @EnvironmentObject var languageManager: LanguageManager
    
    @State private var offset: CGFloat = 0
    @State private var isConfirmed = false
    
    private let trackWidth: CGFloat = 280
    private let pillWidth: CGFloat = 100
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Change Language")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Switching to \(languageManager.currentLanguage.other.title)")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            // Slide to translate track
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: trackWidth, height: 60)
                
                // Track Text
                HStack {
                    Spacer()
                    Text("Slide to \(languageManager.currentLanguage.other.title) ->")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.trailing, 24)
                }
                .frame(width: trackWidth)
                
                // The Slider Pill
                Capsule()
                    .fill(Color.white)
                    .frame(width: pillWidth, height: 52)
                    .padding(4)
                    .overlay(
                        Text(languageManager.currentLanguage.other.flag)
                            .font(.title2)
                    )
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
                                    // Confirmed
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        offset = trackWidth - pillWidth - 8
                                        isConfirmed = true
                                    }
                                    
                                    // Trigger language change
                                    Task {
                                        context.collapse()
                                        // Wait for collapse animation
                                        try? await Task.sleep(nanoseconds: 300_000_000)
                                        await languageManager.switchLanguage(to: languageManager.currentLanguage.other)
                                    }
                                } else {
                                    // Snap back
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
            
            Text("App will restart to apply the new language.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .opacity(offset > 20 ? 1 : 0)
                .animation(.easeInOut, value: offset)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ControlTile {
    static func languageTile(languageManager: LanguageManager) -> ControlTile {
        ControlTile("language-switch", size: .wide, label: "Language") { context in
            HStack(spacing: 12) {
                Text(languageManager.currentLanguage.flag)
                    .font(.title)
                VStack(alignment: .leading) {
                    Text("Language")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text(languageManager.currentLanguage.title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.1))
        }
        .expanded(height: 240) { context in
            LanguageExpandedView(context: context)
        }
    }
}
