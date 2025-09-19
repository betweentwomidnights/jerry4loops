import SwiftUI

@MainActor
final class BackendHealthVM: ObservableObject {
    @Published var healthy: Bool? = nil
    @Published var message: String? = nil
    @Published var config: ModelConfigResponse? = nil
    @Published var checking = false

    func check(using service: ModelService) async {
        checking = true; defer { checking = false }
        let res = await service.getHealth()
        healthy = res.ok
        message = res.message
        guard res.ok else { return }
        do { config = try await service.getConfig() } catch { message = error.localizedDescription }
    }
}

struct InstrumentConfigPopup: View {
    @EnvironmentObject private var service: ModelService
    @StateObject private var backend = BackendHealthVM()
    @Binding var isVisible: Bool
    let audioManager: LoopAudioManager
    let globalBPM: Int
    
    // Configuration state
    @State private var prompt: String = "ambient piano chords"
    @State private var steps: Int = 8
    @State private var cfgScale: Double = 1.0
    @State private var seed: Int = -1
    @State private var useRandomSeed: Bool = true
    @State private var bars: Int? = nil
    @State private var showAdvanced: Bool = false
    
    // Style transfer state
    @State private var styleStrength: Float = 0.65
    
    // Riff transfer state
    @State private var selectedKey: String = "gsharp"
    @State private var riffStyleStrength: Float = 0.65
    
    // Magenta state
    struct StyleEntry: Identifiable {
        let id = UUID()
        var text: String
        var weight: Double
    }
    
    @State private var magentaStyles: [StyleEntry] = [StyleEntry(text: "", weight: 1.0)]
    @State private var magentaLoopWeight: Double = 1.0
    @State private var magentaBars: Int = 4
    @State private var magentaTemperature: Double = 1.2
    @State private var magentaTopK: Int = 30
    @State private var magentaGuidance: Double = 1.5
    @State private var magentaKeepJamming: Bool = false
    
    // Mode selection
    @State private var selectedMode: GenerationMode = .generate
    
    enum GenerationMode {
        case generate
        case styleTransfer
        case riffTransfer
        case magenta
    }
    
    // Computed properties
    private var canUseStyleTransfer: Bool {
        return audioManager.playerManager?.drumAudioURL != nil &&
               audioManager.playerManager?.instrumentAudioURL != nil
    }
    
    private var canUseMagenta: Bool {
        audioManager.playerManager?.drumAudioURL != nil &&
        audioManager.playerManager?.instrumentAudioURL != nil
    }
    
    private var availableKeys: [String] {
        return ["c", "csharp", "d", "dsharp", "e", "f", "fsharp", "g", "gsharp", "a", "asharp", "b"]
    }
    
    // Layout calculations
    private let topSafeArea: CGFloat = 100  // Space for top UI elements
    private let bottomSafeArea: CGFloat = 50  // Space for home indicator
    private let maxPopupHeight: CGFloat = UIScreen.main.bounds.height - 150
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background overlay
                if isVisible {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isVisible = false
                            }
                        }
                        .transition(.opacity)
                }

                // Main popup
                if isVisible {
                    popupContent(in: geometry)
                        .scaleEffect(isVisible ? 1.0 : 0.8)
                        .opacity(isVisible ? 1.0 : 0.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
                        .onAppear {
                            syncMagentaConfig()
                        }
                        .onDisappear {
                            saveMagentaConfig()
                        }
                }
            }
        }
    }
    
    private func popupContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Fixed header section
            fixedHeaderSection
            
            // Dynamic content area based on mode
            if selectedMode == .magenta {
                magentaContentLayout(in: geometry)
            } else {
                standardContentLayout
            }
            
            // Fixed footer section (always visible)
            fixedFooterSection
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 2)
                )
        )
        .frame(maxWidth: 380)
        .frame(maxHeight: maxPopupHeight)
        .task { await backend.check(using: service) }
        .onChange(of: selectedMode) { newMode in
            if newMode == .magenta {
                Task { await backend.check(using: service) }
            }
        }
    }
    
    // MARK: - Fixed Header Section
    private var fixedHeaderSection: some View {
        VStack(spacing: 20) {
            // Header with close button
            headerView
            
            // BPM display
            bpmDisplaySection
            
            // Mode toggle
            modeToggleSection
        }
    }
    
    // MARK: - Standard Content Layout (non-Magenta modes)
    private var standardContentLayout: some View {
        VStack(spacing: 16) {
            // Prompt section
            promptSection
            
            // Mode-specific sections
            if selectedMode == .styleTransfer {
                styleTransferSection
            } else if selectedMode == .riffTransfer {
                riffTransferSection
            }
            
            // Bars section
            barsSection
            
            // Advanced toggle and content
            advancedToggle
            if showAdvanced {
                advancedSection
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showAdvanced)
    }
    
    // MARK: - Magenta Content Layout (with scrolling)
    private func magentaContentLayout(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Fixed top section (backend status)
            magentaStatusBlock
                .padding(.bottom, 12)
            
            // Scrollable middle section
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        // Styles and weights
                        magentaStylesSection
                            .id("styles")
                        
                        // Loop influence
                        magentaLoopInfluenceSection
                            .id("loop-influence")
                        
                        // Advanced Magenta settings
                        magentaAdvancedSection
                    }
                    .padding(.horizontal, 4) // Small padding for scroll indicators
                    .padding(.bottom, 8) // Extra bottom padding to ensure advanced section is fully visible
                }
                .frame(maxHeight: calculateScrollAreaHeight(in: geometry))
                .onChange(of: showAdvanced) { isAdvanced in
                    if isAdvanced {
                        // Add a small delay to allow the DisclosureGroup to expand first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo("advanced", anchor: .center)
                            }
                        }
                    }
                }
            }
            
            // Fixed bottom section (bars and jam toggle) - moved from scrollable area
            magentaFixedBottomSection
                .padding(.top, 12)
        }
    }
    
    // MARK: - Fixed Footer Section
    private var fixedFooterSection: some View {
        VStack(spacing: 16) {
            // Generate button
            generateButton
            
            // Error messages
            if let errorMessage = audioManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Layout Calculations
    private func calculateScrollAreaHeight(in geometry: GeometryProxy) -> CGFloat {
        let availableHeight = geometry.size.height
        let fixedContentHeight: CGFloat = 400 // Estimated height of fixed sections
        let scrollAreaHeight = availableHeight - fixedContentHeight
        return max(scrollAreaHeight, 200) // Minimum scroll area height
    }
    
    // MARK: - Border Color
    private var borderColor: Color {
        switch selectedMode {
        case .generate: return .purple
        case .styleTransfer: return .orange
        case .riffTransfer: return .green
        case .magenta: return .pink
        }
    }
    
    // MARK: - Header View
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundColor(headerSubtitleColor)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private var headerTitle: String {
        switch selectedMode {
        case .generate: return "INSTRUMENT LOOP CONFIG"
        case .styleTransfer: return "INSTRUMENT STYLE TRANSFER"
        case .riffTransfer: return "INSTRUMENT RIFF TRANSFER"
        case .magenta: return "JAM W/MAGENTA"
        }
    }
    
    private var headerSubtitle: String {
        switch selectedMode {
        case .generate: return ""
        case .styleTransfer: return "Using current loop mix"
        case .riffTransfer: return "Using personal riff library"
        case .magenta: return "transform combined audio using magentaRT"
        }
    }
    
    private var headerSubtitleColor: Color {
        switch selectedMode {
        case .generate: return .clear
        case .styleTransfer: return .orange.opacity(0.8)
        case .riffTransfer: return .green.opacity(0.8)
        case .magenta: return .pink.opacity(0.8)
        }
    }
    
    // MARK: - BPM Display Section
    private var bpmDisplaySection: some View {
        VStack(spacing: 4) {
            Text("BPM (Global)")
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("\(globalBPM)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green, lineWidth: 1)
                        )
                )
        }
    }
    
    // MARK: - Mode Toggle Section
    private var modeToggleSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Generate Mode
                modeButton(
                    mode: .generate,
                    icon: "pianokeys",
                    label: "Generate",
                    isEnabled: true,
                    color: .purple
                )
                
                // Style Transfer Mode
                modeButton(
                    mode: .styleTransfer,
                    icon: "paintbrush.fill",
                    label: "Style Transfer",
                    isEnabled: canUseStyleTransfer,
                    color: .orange
                )
                
                // Magenta Mode
                modeButton(
                    mode: .magenta,
                    icon: "wand.and.stars",
                    label: "Magenta",
                    isEnabled: canUseMagenta,
                    color: .pink
                )
            }
            
            // Mode availability indicators
            if selectedMode == .styleTransfer && !canUseStyleTransfer {
                Text("Style transfer requires both drum and instrument loops")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if selectedMode == .riffTransfer {
                Text("Uses your personal riff library for style transfer")
                    .font(.caption2)
                    .foregroundColor(.green.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func modeButton(mode: GenerationMode, icon: String, label: String, isEnabled: Bool, color: Color) -> some View {
        Button(action: {
            if isEnabled {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedMode = mode
                }
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .foregroundColor(selectedMode == mode ? .white : (isEnabled ? color : .gray))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedMode == mode ? color.opacity(0.3) : Color.gray.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedMode == mode ? color : (isEnabled ? color.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: 2)
                    )
            )
        }
        .disabled(!isEnabled)
    }
    
    // MARK: - Prompt Section
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(promptTitle)
                .font(.subheadline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                TextField("describe your instruments...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.subheadline)
                
                Button(action: randomizePrompt) {
                    Image(systemName: "dice")
                        .font(.title2)
                        .foregroundColor(promptButtonColor)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(promptButtonColor, lineWidth: 1)
                        )
                }
            }
        }
    }
    
    private var promptTitle: String {
        switch selectedMode {
        case .generate:      return "Instrument Style"
        case .styleTransfer: return "Target Instrument Style"
        case .riffTransfer:  return "Target Style from Riffs"
        case .magenta:       return "Styles & Weights"
        }
    }
    
    private var promptButtonColor: Color {
        switch selectedMode {
        case .generate: return .purple
        case .styleTransfer: return .orange
        case .riffTransfer: return .green
        case .magenta: return .pink
        }
    }
    
    // MARK: - Style Transfer Section
    private var styleTransferSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Style Strength")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(Int(styleStrength * 100))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                
                StyleStrengthSlider(value: $styleStrength)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange.opacity(0.7))
                        .font(.caption)
                    
                    Text("How it works:")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.9))
                        .fontWeight(.bold)
                }
                
                Text("• Combines your current drum + instrument loops\n• Uses this mix as the foundation for new instruments\n• Higher strength = more transformation")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
                    .lineLimit(nil)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    // MARK: - Riff Transfer Section
    private var riffTransferSection: some View {
        VStack(spacing: 12) {
            // Key selector
            VStack(alignment: .leading, spacing: 8) {
                Text("Musical Key")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(availableKeys, id: \.self) { key in
                        Button(action: {
                            selectedKey = key
                        }) {
                            Text(keyDisplayName(key))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(selectedKey == key ? .black : .white)
                                .frame(minWidth: 35, minHeight: 28)
                                .background(selectedKey == key ? Color.green : Color.gray.opacity(0.3))
                                .cornerRadius(6)
                        }
                    }
                }
            }
            
            // Riff style strength
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Riff Strength")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(Int(riffStyleStrength * 100))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                StyleStrengthSlider(value: $riffStyleStrength)
            }
            
            // Riff transfer explanation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "guitars")
                        .foregroundColor(.green.opacity(0.7))
                        .font(.caption)
                    
                    Text("Personal Riff Library:")
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.9))
                        .fontWeight(.bold)
                }
                
                Text("• Uses your actual compositions as the foundation\n• Randomly selects from riffs in the chosen key\n• Stretches to match target BPM automatically\n• Much more musical than basic generation!")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
                    .lineLimit(nil)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    private func keyDisplayName(_ key: String) -> String {
        switch key {
        case "csharp": return "C#"
        case "dsharp": return "D#"
        case "fsharp": return "F#"
        case "gsharp": return "G#"
        case "asharp": return "A#"
        default: return key.uppercased()
        }
    }
    
    // MARK: - Bars Section
    private var barsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loop Length")
                .font(.subheadline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                ForEach([nil, 1, 2, 4, 8], id: \.self) { barCount in
                    Button(action: {
                        bars = barCount
                    }) {
                        Text(barCount == nil ? "AUTO" : "\(barCount!)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(bars == barCount ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(bars == barCount ? borderColor : Color.gray.opacity(0.3))
                            .cornerRadius(6)
                    }
                }
                
                Spacer()
                
                Text("bars")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    
    // MARK: - Advanced Toggle & Section
    private var advancedToggle: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.25)) {
                showAdvanced.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Text("Advanced Settings")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    private var advancedSection: some View {
        VStack(spacing: 16) {
            HStack {
                SliderControl(
                    label: "Steps",
                    value: $steps,
                    min: 4,
                    max: 25,
                    step: 1
                )
                
                Spacer()
                
                SliderControl(
                    label: "CFG Scale",
                    value: $cfgScale,
                    min: 0.1,
                    max: 6.0,
                    step: 0.1
                )
            }
            
            HStack {
                Text("Seed")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: {
                        useRandomSeed.toggle()
                        if useRandomSeed {
                            seed = -1
                        }
                    }) {
                        Text("Random")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(useRandomSeed ? borderColor : Color.gray.opacity(0.3))
                            .cornerRadius(6)
                    }
                    
                    if !useRandomSeed {
                        TextField("0", value: $seed, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.caption)
                            .frame(width: 80)
                            .multilineTextAlignment(.center)
                        
                        Button(action: randomizeSeed) {
                            Image(systemName: "dice")
                                .font(.caption)
                                .foregroundColor(borderColor)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor.opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    // MARK: - Magenta Status Block
    private var magentaStatusBlock: some View {
        Group {
            if backend.healthy == false {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Magenta backend is offline.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text("Open the Studio menu to verify the backend URL and wake the HF Space, then tap Recheck.")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.9))

                    Button {
                        Task { await backend.check(using: service) }
                    } label: {
                        HStack(spacing: 6) {
                            if backend.checking { ProgressView().scaleEffect(0.9) }
                            Text("Recheck")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1))

            } else if let c = backend.config {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "server.rack")
                        Text(c.repo ?? "—").lineLimit(1)
                        if let step = c.selected_step { Text("• step \(step)") }
                        Spacer()
                        if c.warmup_done {
                            Label("warmed", systemImage: "bolt.fill").foregroundColor(.green)
                        } else if c.loaded {
                            Label("cold", systemImage: "snowflake").foregroundColor(.orange)
                        }
                        Button {
                            Task { await backend.check(using: service) }
                        } label: {
                            if backend.checking { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh model status")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if c.loaded && !c.warmup_done {
                        Text("Heads-up: first Magenta chunk may be rough until warmup finishes.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

            } else {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                    Text("Tap Recheck to fetch current Magenta model status.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task { await backend.check(using: service) }
                    } label: {
                        if backend.checking { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    // MARK: - Magenta Styles Section (Scrollable)
    private var magentaStylesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Styles & Weights")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    magentaStyles.append(StyleEntry(text: "", weight: 1.0))
                    if magentaStyles.count > 4 { magentaStyles.removeLast() }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundColor(.pink)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.pink.opacity(0.6), lineWidth: 1))
                }
                .disabled(magentaStyles.count >= 4)
            }

            ForEach($magentaStyles) { $entry in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("e.g. acid house, trumpet, lofi", text: $entry.text)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.caption)
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                entry.text = MagentaPrompts.getNextCyclingStyle()
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Image(systemName: "dice")
                                .font(.caption2)
                                .foregroundColor(.pink)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.pink, lineWidth: 1)
                                )
                        }

                        if magentaStyles.count > 1 {
                            Button {
                                if let idx = magentaStyles.firstIndex(where: { $0.id == entry.id }) {
                                    magentaStyles.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.pink)
                            }
                        }
                    }

                    HStack {
                        Text("Weight")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Slider(value: $entry.weight, in: 0...1, step: 0.01)
                            .frame(height: 20)
                        Text(String(format: "%.2f", entry.weight))
                            .font(.caption2)
                            .foregroundColor(.pink)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink.opacity(0.25), lineWidth: 1))
            }
        }
        .disabled(backend.healthy != true || !(backend.config?.loaded ?? false))
    }
    
    // MARK: - Magenta Loop Influence Section (Scrollable)
    private var magentaLoopInfluenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Loop Influence")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", magentaLoopWeight))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.pink)
            }
            Slider(value: $magentaLoopWeight, in: 0...1, step: 0.01)
                .frame(height: 20)
        }
    }
    
    // MARK: - Magenta Advanced Section (Scrollable)
    private var magentaAdvancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(spacing: 8) {
                HStack {
                    Text("Temperature")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.2f", magentaTemperature))
                        .font(.caption2)
                        .foregroundColor(.pink)
                }
                Slider(value: $magentaTemperature, in: 0...4.0, step: 0.05)
                    .frame(height: 20)

                HStack {
                    Text("Top-K")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(magentaTopK)")
                        .font(.caption2)
                        .foregroundColor(.pink)
                }
                Slider(value: Binding(
                    get: { Double(magentaTopK) },
                    set: { magentaTopK = Int($0.rounded()) }
                ), in: 0...1024, step: 1)
                    .frame(height: 20)

                HStack {
                    Text("Guidance Weight")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.2f", magentaGuidance))
                        .font(.caption2)
                        .foregroundColor(.pink)
                }
                Slider(value: $magentaGuidance, in: 0...10.0, step: 0.05)
                    .frame(height: 20)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text("Advanced (Magenta)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: showAdvanced)
            }
        }
        .padding(.vertical, 6)
        .id("advanced")
    }
    
    // MARK: - Magenta Fixed Bottom Section (Non-scrollable)
    private var magentaFixedBottomSection: some View {
        VStack(spacing: 12) {
            // Bars and Jam toggle on same row
            HStack {
                // Bars section (left side)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bars")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    HStack(spacing: 8) {
                        ForEach([4, 8], id: \.self) { count in
                            Button {
                                magentaBars = count
                            } label: {
                                Text("\(count)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(magentaBars == count ? .black : .white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(magentaBars == count ? Color.pink : Color.gray.opacity(0.3))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Jam toggle section (right side)
                VStack(alignment: .trailing, spacing: 6) {
                    Text("jam")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Toggle("", isOn: $magentaKeepJamming)
                        .labelsHidden()
                        .tint(.pink)
                }
            }
            
            // Jam description (full width below)
            Text("When enabled, the main button will start a continuous Magenta session.")
                .font(.caption2)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.pink.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
    }
    
    // MARK: - Generate Button
    private var generateButton: some View {
        Button(action: generateInstrumentLoop) {
            HStack {
                if audioManager.isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text(generatingText)
                } else {
                    generateButtonIcon
                    Text(generateButtonText)
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(audioManager.isGenerating ? Color.gray : borderColor)
            .cornerRadius(12)
        }
        .disabled(
            audioManager.isGenerating ||
            (selectedMode != .magenta && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (selectedMode == .styleTransfer && !canUseStyleTransfer) ||
            (selectedMode == .magenta && (backend.healthy != true || !(backend.config?.loaded ?? false)))
        )
    }
    
    private var generateButtonText: String {
        switch selectedMode {
        case .generate:      return "GENERATE INSTRUMENT LOOP"
        case .styleTransfer: return "STYLE TRANSFER INSTRUMENTS"
        case .riffTransfer:  return "RIFF TRANSFER INSTRUMENTS"
        case .magenta:       return magentaKeepJamming ? "START JAMMING" : "GENERATE NEW LOOP"
        }
    }
    
    private var generatingText: String {
        switch selectedMode {
        case .generate:      return "Generating..."
        case .styleTransfer: return "Style Transferring..."
        case .riffTransfer:  return "Riff Transferring..."
        case .magenta:       return magentaKeepJamming ? "Starting Jam..." : "Generating..."
        }
    }
    
    @ViewBuilder
    private var generateButtonIcon: some View {
        switch selectedMode {
        case .generate:
            EmptyView()
        case .styleTransfer:
            Image(systemName: "paintbrush.fill")
        case .riffTransfer:
            Image(systemName: "guitars.fill")
        case .magenta:
            EmptyView()
        }
    }
    
    // MARK: - Config Sync Methods
    private func syncMagentaConfig() {
        let shared = audioManager.magentaConfig
        self.magentaStyles = shared.styles.map { StyleEntry(text: $0.text, weight: $0.weight) }
        self.magentaLoopWeight = shared.loopWeight
        self.magentaBars = shared.bars
        self.magentaTemperature = shared.temperature
        self.magentaTopK = shared.topK
        self.magentaGuidance = shared.guidanceWeight
    }
    
    private func saveMagentaConfig() {
        let shared = audioManager.magentaConfig
        shared.styles = self.magentaStyles.map { .init(text: $0.text, weight: $0.weight) }
        shared.loopWeight = self.magentaLoopWeight
        shared.bars = self.magentaBars
        shared.temperature = self.magentaTemperature
        shared.topK = self.magentaTopK
        shared.guidanceWeight = self.magentaGuidance
    }
    
    // MARK: - Action Methods
    private func randomizePrompt() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedMode == .magenta {
                if !magentaStyles.isEmpty {
                    magentaStyles[0].text = MagentaPrompts.getNextCyclingStyle()
                } else {
                    magentaStyles.append(StyleEntry(text: MagentaPrompts.getNextCyclingStyle(), weight: 1.0))
                }
            } else {
                prompt = InstrumentPrompts.getCleanInstrumentPrompt()
            }
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func randomizeSeed() {
        seed = Int.random(in: 0...1000000)
        useRandomSeed = false
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func generateInstrumentLoop() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        switch selectedMode {
        case .generate:
            audioManager.generateInstrumentLoop(
                prompt: prompt,
                bpm: globalBPM,
                steps: steps,
                cfgScale: cfgScale,
                seed: useRandomSeed ? -1 : seed,
                bars: bars
            )
            
        case .styleTransfer:
            audioManager.generateInstrumentStyleTransfer(
                prompt: prompt,
                bpm: globalBPM,
                styleStrength: styleStrength,
                steps: steps,
                cfgScale: cfgScale,
                seed: useRandomSeed ? -1 : seed,
                bars: bars
            )
            
        case .riffTransfer:
            audioManager.generateInstrumentRiffTransfer(
                prompt: prompt,
                key: selectedKey,
                bpm: globalBPM,
                styleStrength: riffStyleStrength,
                steps: steps,
                cfgScale: cfgScale,
                seed: useRandomSeed ? -1 : seed,
                bars: bars
            )
        case .magenta:
            if magentaKeepJamming {
                audioManager.requestStartMagentaJam(
                    bpm: globalBPM,
                    barsPerChunk: magentaBars,
                    styles: magentaStyles.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                    styleWeights: magentaStyles.map(\.weight),
                    loopWeight: magentaLoopWeight,
                    temperature: magentaTemperature,
                    topK: magentaTopK,
                    guidanceWeight: magentaGuidance
                )
            } else {
                audioManager.generateInstrumentMagenta(
                    bpm: globalBPM,
                    bars: magentaBars,
                    styles: magentaStyles.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                    styleWeights: magentaStyles.map(\.weight),
                    loopWeight: magentaLoopWeight,
                    temperature: magentaTemperature,
                    topK: magentaTopK,
                    guidanceWeight: magentaGuidance
                )
            }
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isVisible = false
        }
    }
}

#Preview {
    InstrumentConfigPopup(
        isVisible: .constant(true),
        audioManager: LoopAudioManager(),
        globalBPM: 120
    )
}
