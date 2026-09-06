import SwiftUI
import LiquidControlCenter

@main
struct ControlCenterDemoApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("--integration-harness") {
                IntegrationHarness()
            } else {
                DemoScreen()
                    .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-type") ? .accessibility3 : .large)
            }
        }
    }
}

struct DemoScreen: View {
    @StateObject private var languageManager = LanguageManager.shared
    
    @State private var presented = false
    @State private var fallback = ProcessInfo.processInfo.arguments.contains("--fallback")
    @State private var reduceMotion = ProcessInfo.processInfo.arguments.contains("--reduce-motion")
    @State private var reduceTransparency = ProcessInfo.processInfo.arguments.contains("--reduce-transparency")
    @State private var compact = false
    @State private var spacing: CGFloat = 14
    @State private var horizontalPadding: CGFloat = 28
    @State private var maximumWidth: CGFloat = 430
    @State private var dimmingOpacity: Double = 0.22
    @State private var airplane = false
    @State private var wifi = true
    @State private var bluetooth = true
    @State private var cellular = true
    @State private var focus = false
    @State private var locked = true
    @State private var silent = true
    @State private var lowPower = false
    @State private var recording = false
    @State private var darkMode = true
    @State private var recognition = false
    @State private var torch = false
    @State private var playing = false
    @State private var brightness = 0.68
    @State private var volume = 0.42
    @State private var showSettings = false
    @State private var showCamera = false
    @State private var note = ""

    private var configuration: ControlCenterConfiguration {
        var config = ControlCenterConfiguration()
        config.forceFallback = fallback
        config.columns = compact ? 3 : 4
        config.forceReducedMotion = reduceMotion
        config.forceReducedTransparency = reduceTransparency
        config.spacing = spacing
        config.horizontalPadding = horizontalPadding
        config.maximumWidth = maximumWidth
        config.dimmingOpacity = dimmingOpacity
        return config
    }

    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                wallpaper
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        HStack {
                            Label("STUDIO / 01", systemImage: "circle.hexagongrid.fill")
                                .font(.caption.weight(.bold)).tracking(2)
                            Spacer()
                            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                                .accessibilityLabel("Demo settings")
                                .frame(width: 44, height: 44)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(languageManager.currentLanguage == .english ? "Everything.\nWithin reach." : "كل شيء.\nفي متناول يدك.")
                                .font(.system(size: 48, weight: .semibold, design: .rounded)).tracking(-2)
                            Text(languageManager.currentLanguage == .english ? "Your space, your controls." : "مساحتك، عناصر تحكمك.")
                                .font(.title3).foregroundStyle(.white.opacity(0.7))
                        }
                        Button { presented = true } label: {
                            HStack {
                                Image(systemName: "switch.2")
                                Text(languageManager.currentLanguage == .english ? "Open Control Center" : "افتح مركز التحكم")
                                Spacer()
                                Image(systemName: "arrow.down.right")
                            }
                            .font(.body.weight(.semibold))
                            .padding(22)
                            .background(.white.opacity(0.16), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 1))
                        }
                        .accessibilityIdentifier("demo.open")
                        HStack(spacing: 14) {
                            summaryCard(languageManager.currentLanguage == .english ? "Atmosphere" : "الجو العام", value: "\(Int(brightness * 100))%", icon: "sun.max.fill", color: .orange)
                            summaryCard(languageManager.currentLanguage == .english ? "Sound" : "الصوت", value: "\(Int(volume * 100))%", icon: "waveform", color: .cyan)
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                RoundedRectangle(cornerRadius: 18).fill(.orange.gradient)
                                    .frame(width: 64, height: 64)
                                    .overlay(Image(systemName: "waveform").font(.title))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(languageManager.currentLanguage == .english ? "A little room to breathe" : "مساحة صغيرة للتنفس").font(.headline)
                                    Text(languageManager.currentLanguage == .english ? "Evening sessions · Demo audio" : "جلسات مسائية · صوت تجريبي").font(.caption).opacity(0.65)
                                }
                            }
                            HStack {
                                Text(playing ? (languageManager.currentLanguage == .english ? "Playing in your space" : "يعمل في مساحتك") : (languageManager.currentLanguage == .english ? "Ready when you are" : "جاهز عندما تكون"))
                                    .font(.subheadline).opacity(0.8)
                                Spacer()
                                Button { playing.toggle() } label: {
                                    Image(systemName: playing ? "pause.fill" : "play.fill")
                                        .frame(width: 44, height: 44)
                                }
                            }
                        }
                        .padding(22).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 28))
                        Text(languageManager.currentLanguage == .english ? "Touch and hold a control to explore more. Changes stay in sync with this screen." : "المس مع الاستمرار لاكتشاف المزيد. التغييرات تتزامن مع هذه الشاشة.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.6))
                        if !note.isEmpty { Text(note).font(.footnote) }
                    }
                    .padding(26)
                }
            }
            .environment(\.layoutDirection, languageManager.currentLanguage.layoutDirection)
            .foregroundStyle(.white)
            .toolbar(.hidden, for: .navigationBar)
            .liquidControlCenter(isPresented: $presented, pages: pages, configuration: configuration)
            .sheet(isPresented: $showSettings) { settings }
            .sheet(isPresented: $showCamera) {
                VStack(spacing: 24) {
                    Image(systemName: "camera.aperture").font(.system(size: 70))
                    Text("Your app action goes here").font(.title2.bold())
                    Text("The demo uses local state. Connect controls to your own services.").multilineTextAlignment(.center)
                    Button("Done") { showCamera = false }.buttonStyle(.borderedProminent)
                }.padding(32)
            }
            } // Close NavigationStack here
            
            // Full Screen Loader
            if languageManager.isReloading {
                FullScreenLoaderView()
                    .environmentObject(languageManager)
                    .transition(.opacity)
                    .zIndex(100)
            }
            
            // Reveal Animation
            if languageManager.showRevealAnimation {
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    switch languageManager.revealStyle {
                    case .ripple:
                        Circle()
                            .fill(Color.blue)
                            .scaleEffect(languageManager.showRevealAnimation ? 50 : 0)
                            .opacity(languageManager.showRevealAnimation ? 0 : 1)
                            .animation(.easeOut(duration: 0.8), value: languageManager.showRevealAnimation)
                    case .curtain:
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.black)
                                .offset(x: languageManager.showRevealAnimation ? -500 : 0)
                            Rectangle()
                                .fill(Color.black)
                                .offset(x: languageManager.showRevealAnimation ? 500 : 0)
                        }
                        .animation(.easeInOut(duration: 0.8), value: languageManager.showRevealAnimation)
                    case .textZoom:
                        Text(languageManager.currentLanguage.title)
                            .font(.system(size: 80, weight: .black))
                            .foregroundColor(.white)
                            .scaleEffect(languageManager.showRevealAnimation ? 100 : 1)
                            .opacity(languageManager.showRevealAnimation ? 0 : 1)
                            .animation(.easeIn(duration: 0.8), value: languageManager.showRevealAnimation)
                    case .iris:
                        Color.black.ignoresSafeArea()
                            .mask {
                                Rectangle()
                                    .overlay(
                                        Circle()
                                            .scaleEffect(languageManager.showRevealAnimation ? 50 : 0)
                                            .blendMode(.destinationOut)
                                    )
                            }
                            .animation(.easeOut(duration: 0.8), value: languageManager.showRevealAnimation)
                    }
                }
                .ignoresSafeArea()
                .zIndex(101)
                .allowsHitTesting(false)
            }
        }
        .environmentObject(languageManager)
        .preferredColorScheme(.dark)
        .task {
            if ProcessInfo.processInfo.arguments.contains("--show-control-center") { presented = true }
        }
    }

    private var wallpaper: some View {
        ZStack {
            Color(red: 0.03, green: 0.09, blue: 0.16)
            GeometryReader { geo in
                Ellipse().fill(Color.cyan.opacity(0.65))
                    .frame(width: geo.size.width * 1.2, height: 520)
                    .blur(radius: 85).offset(x: -220, y: 220)
                Ellipse().fill(Color.indigo.opacity(0.8))
                    .frame(width: 370, height: 620).blur(radius: 65).offset(x: 200, y: -100)
                Ellipse().fill(Color.orange.opacity(0.45))
                    .frame(width: 260, height: 320).blur(radius: 70).offset(x: 170, y: 620)
            }
        }.ignoresSafeArea()
    }

    private func summaryCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: icon).font(.title2).foregroundStyle(color)
            Text(value).font(.system(size: 32, weight: .medium, design: .rounded))
            Text(title).font(.caption).opacity(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 28))
    }

    private var pages: [ControlCenterPage] {
        [ControlCenterPage("favorites", title: "Favorites", systemImage: "heart.fill") {
            ControlTile("connectivity", size: .large, label: "Connectivity") { context in
                connectivity(expanded: false)
                    .padding(13)
                    .overlay(alignment: .topTrailing) {
                        Button(action: context.expand) { Color.clear.frame(width: 22, height: 22) }
                            .accessibilityLabel("Expand Connectivity")
                    }
            }.expanded(height: 390) { _ in
                VStack(alignment: .leading, spacing: 22) {
                    Text("Connectivity").font(.title2.bold())
                    connectivity(expanded: true)
                    Text("Connections are demo states owned by this app.").font(.footnote).opacity(0.6)
                }
            }
            mediaTile
            toggleTile("rotation", title: "Rotation Lock", image: "lock.rotation", value: $locked, tint: .white)
            toggleTile("silent", title: "Silent Mode", image: silent ? "bell.slash.fill" : "bell.fill", value: $silent, tint: .white)
            ControlTile("brightness", size: .tall, label: "Brightness") { _ in
                ControlCenterSlider("Brightness", value: $brightness, systemImage: "sun.max.fill")
            }.expanded(height: 410) { _ in
                VStack(spacing: 24) {
                    Text("Brightness").font(.title2.bold())
                    ControlCenterSlider("Brightness", value: $brightness, systemImage: "sun.max.fill")
                        .frame(width: 110, height: 240)
                        .background(.white.opacity(0.12), in: Capsule()).clipShape(Capsule())
                    Text("\(Int(brightness * 100))% · Studio lights").font(.subheadline)
                }.frame(maxWidth: .infinity)
            }
            ControlTile("volume", size: .tall, label: "Volume") { _ in
                ControlCenterSlider("Volume", value: $volume, systemImage: "speaker.wave.2.fill")
            }.expanded(height: 360) { _ in
                VStack(spacing: 24) {
                    Text("Volume").font(.title2.bold())
                    ControlCenterSlider("Volume", value: $volume, systemImage: "speaker.wave.2.fill")
                        .frame(width: 110, height: 220)
                        .background(.white.opacity(0.12), in: Capsule()).clipShape(Capsule())
                }.frame(maxWidth: .infinity)
            }
            ControlTile("focus", size: .wide, label: "Focus", tint: focus ? .indigo : nil, action: { focus.toggle() }) { _ in
                ControlCenterLabel("Focus", systemImage: "moon.fill", subtitle: focus ? "On" : nil, showsTitle: true)
            }.expanded(height: 320) { _ in
                VStack(alignment: .leading, spacing: 20) {
                    Text("Focus").font(.title2.bold())
                    Toggle("Do Not Disturb", isOn: $focus)
                    Label("Personal", systemImage: "person.fill")
                    Label("Work", systemImage: "briefcase.fill")
                    Label("Sleep", systemImage: "bed.double.fill")
                }.font(.title3)
            }
            toggleTile("flashlight", title: "Flashlight", image: torch ? "flashlight.on.fill" : "flashlight.off.fill", value: $torch, tint: .orange.opacity(0.6))
            ControlTile("mirroring", label: "Screen Mirroring") { context in
                Button(action: context.expand) { ControlCenterLabel("Screen Mirroring", systemImage: "rectangle.on.rectangle") }.buttonStyle(.plain)
            }.expanded(height: 250) { _ in
                VStack(spacing: 24) {
                    Image(systemName: "rectangle.on.rectangle").font(.largeTitle)
                    Text("Screen Mirroring").font(.title2.bold())
                    Text("Add your app’s available displays here.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
            }
            ControlTile("camera", label: "Camera") { context in
                Button {
                    context.dismiss()
                    note = "Camera action received."
                } label: { ControlCenterLabel("Camera", systemImage: "camera.fill") }.buttonStyle(.plain)
            }
            toggleTile("battery", title: "Low Power Mode", image: "battery.100", value: $lowPower, tint: .yellow)
            toggleTile("record", title: "Screen Recording", image: "record.circle", value: $recording, tint: .white)
            toggleTile("appearance", title: "Dark Mode", image: "circle.lefthalf.filled", value: $darkMode, tint: .white.opacity(0.2))
            toggleTile("recognition", title: "Music Recognition", image: "waveform", value: $recognition, tint: .blue)
            ControlTile("timer", label: "Timer") { context in
                Button(action: context.expand) { ControlCenterLabel("Timer", systemImage: "timer") }.buttonStyle(.plain)
            }.expanded(height: 240) { context in
                VStack(spacing: 24) {
                    Text("A moment for yourself").font(.title2.bold())
                    Text("05:00").font(.system(size: 52, weight: .light, design: .rounded))
                    Button("Start timer") { note = "Five-minute timer action received."; context.dismiss() }
                        .buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity)
            }
        }, ControlCenterPage("music", title: "Now Playing", systemImage: "music.note") {
            mediaTile
            ControlTile("music-volume", size: .wide, label: "Volume") { _ in
                HStack { Image(systemName: "speaker.wave.2.fill"); Slider(value: $volume) }.padding(20)
            }
        }, ControlCenterPage("home", title: "Your Space", systemImage: "house.fill") {
            ControlTile("lights", size: .wide, label: "Studio Lights", tint: .orange.opacity(0.3), action: { brightness = brightness > 0 ? 0 : 0.8 }) { _ in
                ControlCenterLabel("Studio", systemImage: "lightbulb.fill", subtitle: "\(Int(brightness * 100))%", showsTitle: true)
            }
            toggleTile("quiet", title: "Quiet Mode", image: "moon.fill", value: $focus, tint: .indigo)
        }, ControlCenterPage("settings", title: "Settings", systemImage: "gearshape.fill") {
            ControlTile.languageTile(languageManager: languageManager)
        }]
    }

    private func toggleTile(_ id: String, title: String, image: String, value: Binding<Bool>, tint: Color) -> ControlTile {
        ControlTile(id, label: title, tint: value.wrappedValue ? tint : nil, action: { value.wrappedValue.toggle() }) { _ in
            ControlCenterLabel(title, systemImage: image)
                .foregroundStyle(value.wrappedValue && (id == "rotation" || id == "silent" || id == "record") ? Color.red : .white)
                .accessibilityValue(value.wrappedValue ? "On" : "Off")
        }
    }

    private var mediaTile: ControlTile {
        ControlTile("media", size: .large, label: "Now Playing") { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RoundedRectangle(cornerRadius: 12).fill(.orange.gradient).frame(width: 42, height: 42)
                        .overlay(Image(systemName: "waveform").font(.title3))
                    Spacer()
                    Button(action: context.expand) { Image(systemName: "airplayaudio").frame(width: 36, height: 36) }
                        .accessibilityLabel("Expand Now Playing")
                }
                Spacer(minLength: 0)
                Text(playing ? "Evening Sessions" : "Not Playing").font(.subheadline.weight(.semibold)).lineLimit(1)
                HStack {
                    Image(systemName: "backward.fill").opacity(0.4)
                    Spacer()
                    Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 44, height: 36) }
                        .accessibilityLabel(playing ? "Pause" : "Play")
                    Spacer()
                    Image(systemName: "forward.fill").opacity(0.4)
                }
            }.padding(16).buttonStyle(.plain)
        }.expanded(height: 430) { _ in
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 30).fill(.orange.gradient).frame(width: 170, height: 170)
                    .overlay(Image(systemName: "waveform").font(.system(size: 60)))
                Text("Evening Sessions").font(.title2.bold())
                Text("A little room to breathe").foregroundStyle(.secondary)
                Button { playing.toggle() } label: { Image(systemName: playing ? "pause.fill" : "play.fill").font(.largeTitle) }
                    .accessibilityLabel(playing ? "Pause" : "Play")
                Slider(value: $volume).accessibilityLabel("Playback Volume")
            }.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func connectivity(expanded: Bool) -> some View {
        if expanded {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                connection("Airplane Mode", image: "airplane", value: $airplane, color: .orange, expanded: true)
                connection("Cellular Data", image: "antenna.radiowaves.left.and.right", value: $cellular, color: .green, expanded: true)
                connection("Wi-Fi", image: "wifi", value: $wifi, color: .blue, expanded: true)
                connection("Bluetooth", image: "wave.3.right", value: $bluetooth, color: .blue, expanded: true)
            }
        } else {
            GeometryReader { geometry in
                let side = max(36, (geometry.size.width - 10) / 2)
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        connectionCircle("Airplane Mode", image: "airplane", value: $airplane, color: .orange, side: side)
                        Button {} label: {
                            Image(systemName: "airplayaudio").font(.system(size: 24))
                                .frame(width: side, height: side)
                                .background(.blue.opacity(0.8), in: Circle())
                        }.accessibilityLabel("AirDrop")
                    }
                    HStack(spacing: 10) {
                        connectionCircle("Wi-Fi", image: "wifi", value: $wifi, color: .blue, side: side)
                        VStack(spacing: 5) {
                            HStack(spacing: 5) {
                                connectionCircle("Cellular Data", image: "antenna.radiowaves.left.and.right", value: $cellular, color: .green, side: (side - 5) / 2)
                                connectionCircle("Bluetooth", image: "wave.3.right", value: $bluetooth, color: .blue, side: (side - 5) / 2)
                            }
                            HStack(spacing: 5) {
                                Image(systemName: "personalhotspot").frame(width: (side - 5) / 2, height: (side - 5) / 2).background(.white.opacity(0.1), in: Circle())
                                Image(systemName: "globe").frame(width: (side - 5) / 2, height: (side - 5) / 2).background(.white.opacity(0.1), in: Circle())
                            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                        }.frame(width: side, height: side)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func connectionCircle(_ title: String, image: String, value: Binding<Bool>, color: Color, side: CGFloat) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Image(systemName: image).font(.system(size: side > 35 ? 24 : 12, weight: .medium))
                .frame(width: side, height: side)
                .background(value.wrappedValue ? color : .white.opacity(0.16), in: Circle())
        }.accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "On" : "Off")
    }

    private func connection(_ title: String, image: String, value: Binding<Bool>, color: Color, expanded: Bool) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            VStack(spacing: 8) {
                Image(systemName: image).font(.system(size: expanded ? 26 : 22, weight: .medium))
                    .frame(maxWidth: .infinity).frame(height: expanded ? 64 : 48)
                    .background(value.wrappedValue ? color : .white.opacity(0.16), in: Capsule())
                if expanded { Text(title).font(.caption.weight(.semibold)) }
            }
        }
        .buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value.wrappedValue ? "On" : "Off")
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Toggle("Preview fallback materials", isOn: $fallback)
                    Toggle("Three-column arrangement", isOn: $compact)
                    Toggle("Reduce motion", isOn: $reduceMotion)
                    Toggle("Reduce transparency", isOn: $reduceTransparency)
                }
                Section("Layout Configuration") {
                    VStack(alignment: .leading) {
                        Text("Spacing: \(Int(spacing))")
                        Slider(value: $spacing, in: 4...32, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("Horizontal Padding: \(Int(horizontalPadding))")
                        Slider(value: $horizontalPadding, in: 0...60, step: 1)
                    }
                    VStack(alignment: .leading) {
                        Text("Maximum Width: \(Int(maximumWidth))")
                        Slider(value: $maximumWidth, in: 300...800, step: 10)
                    }
                    VStack(alignment: .leading) {
                        Text("Dimming Opacity: \(String(format: "%.2f", dimmingOpacity))")
                        Slider(value: $dimmingOpacity, in: 0...1, step: 0.05)
                    }
                }
                Section("Creative Options") {
                    Picker("Language Switcher Style", selection: $languageManager.switcherStyle) {
                        ForEach(SwitcherStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    Picker("Loader Style", selection: $languageManager.loaderStyle) {
                        ForEach(LoaderStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    Picker("Reveal Animation", selection: $languageManager.revealStyle) {
                        ForEach(RevealStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }

                Section {
                    Text("All controls in this sample use local app state. The same bindings drive the tiles, expanded views, and dashboard.")
                }
            }
            .navigationTitle("Demo settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }
    }
}

struct FullScreenLoaderView: View {
    @EnvironmentObject var languageManager: LanguageManager
    @State private var animate = false
    
    var body: some View {
        ZStack {
            switch languageManager.loaderStyle {
            case .pulse:
                RadialGradient(colors: [Color.blue.opacity(0.4), Color.black], center: .center, startRadius: 10, endRadius: 500)
                    .ignoresSafeArea()
            case .rotatingFlags:
                ZStack {
                    Color.black.ignoresSafeArea()
                    Circle().fill(Color.orange.opacity(0.15)).blur(radius: 50).frame(width: 300, height: 300).offset(x: animate ? 100 : -100, y: animate ? -100 : 100)
                    Circle().fill(Color.green.opacity(0.15)).blur(radius: 50).frame(width: 300, height: 300).offset(x: animate ? -100 : 100, y: animate ? 100 : -100)
                }.ignoresSafeArea()
            case .matrix:
                Color(red: 0.05, green: 0.1, blue: 0.05).ignoresSafeArea()
            case .morphing:
                LinearGradient(colors: [Color.indigo.opacity(0.4), Color.black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            
            switch languageManager.loaderStyle {
            case .pulse:
                pulseGlobe
            case .rotatingFlags:
                rotatingFlags
            case .matrix:
                translationMatrix
            case .morphing:
                liquidMorph
            }
            
            VStack {
                Spacer()
                Text(languageManager.loadingMessage)
                    .font(.title3.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.bottom, 60)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                    .id(languageManager.loadingMessage)
            }
        }
        .onAppear { animate = true }
    }
    
    private var pulseGlobe: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(0.1))
                .scaleEffect(animate ? 2.0 : 0.5)
                .opacity(animate ? 0 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: animate)
            
            Image(systemName: "globe")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .scaleEffect(animate ? 1.1 : 0.9)
                .animation(.easeInOut(duration: 1).repeatForever(), value: animate)
        }
    }
    
    private var rotatingFlags: some View {
        ZStack {
            Text(AppLanguage.english.flag)
                .font(.system(size: 50))
                .offset(y: -40)
            Text(AppLanguage.arabic.flag)
                .font(.system(size: 50))
                .offset(y: 40)
        }
        .rotationEffect(.degrees(animate ? 360 : 0))
        .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: animate)
    }
    
    private var translationMatrix: some View {
        HStack(spacing: 20) {
            ForEach(0..<5) { i in
                Text(animate ? "A" : "ع")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.green.opacity(animate ? 1 : 0.2))
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.1), value: animate)
            }
        }
    }
    
    private var liquidMorph: some View {
        ZStack {
            Circle()
                .fill(Color.cyan)
                .frame(width: 80, height: 80)
                .offset(x: animate ? -30 : 30)
            
            Circle()
                .fill(Color.indigo)
                .frame(width: 80, height: 80)
                .offset(x: animate ? 30 : -30)
                .blendMode(.screen)
        }
        .animation(.easeInOut(duration: 1.2).repeatForever(), value: animate)
    }
}
