import SwiftUI

struct InstrumentConfigPopup: View {
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
    
    // NEW: Riff transfer state
    @State private var selectedKey: String = "gsharp"
    @State private var riffStyleStrength: Float = 0.65
    
    // Magenta state
    struct StyleEntry: Identifiable {
        let id = UUID()
        var text: String
        var weight: Double
    }
    
    @State private var magentaStyles: [StyleEntry] = [StyleEntry(text: "", weight: 1.0)]
    @State private var magentaLoopWeight: Double = 1.0 // 0–1
    @State private var magentaBars: Int = 4 // 4 or 8
    @State private var magentaTemperature: Double = 1.2 // 0–4
    @State private var magentaTopK: Int = 30 // 0–1024
    @State private var magentaGuidance: Double = 1.5 // 0–10
    
    private var canUseMagenta: Bool {
        audioManager.playerManager?.drumAudioURL != nil &&
        audioManager.playerManager?.instrumentAudioURL != nil
    }
    
    @State private var magentaKeepJamming: Bool = false   // NEW
    
    // Mode selection
    @State private var selectedMode: GenerationMode = .generate
    
    enum GenerationMode {
        case generate
        case styleTransfer
        case riffTransfer // keep for future use
        case magenta
    }
    
    // Computed properties
    private var canUseStyleTransfer: Bool {
        return audioManager.playerManager?.drumAudioURL != nil &&
               audioManager.playerManager?.instrumentAudioURL != nil
    }
    
    private var availableKeys: [String] {
        return ["c", "csharp", "d", "dsharp", "e", "f", "fsharp", "g", "gsharp", "a", "asharp", "b"]
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            if isVisible {
                Color.black.opacity(0.7)
                    .ignoresSafeArea() // <- modern API
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isVisible = false
                        }
                    }
                    .transition(.opacity)
            }

            // Main popup
            if isVisible {
                VStack(spacing: 20) {
                    headerView
                    mainContent
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
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)

                // Attach the syncing here so it’s unambiguously the popup’s lifecycle
                .onAppear {
                    let shared = audioManager.magentaConfig
                    self.magentaStyles = shared.styles.map { StyleEntry(text: $0.text, weight: $0.weight) }
                    self.magentaLoopWeight = shared.loopWeight
                    self.magentaBars = shared.bars
                    self.magentaTemperature = shared.temperature
                    self.magentaTopK = shared.topK
                    self.magentaGuidance = shared.guidanceWeight
                }
                .onDisappear {
                    let shared = audioManager.magentaConfig
                    shared.styles = self.magentaStyles.map { .init(text: $0.text, weight: $0.weight) }
                    shared.loopWeight = self.magentaLoopWeight
                    shared.bars = self.magentaBars
                    shared.temperature = self.magentaTemperature
                    shared.topK = self.magentaTopK
                    shared.guidanceWeight = self.magentaGuidance
                }
            }
        }
    }

    
    private var borderColor: Color {
        switch selectedMode {
        case .generate: return .purple
        case .styleTransfer: return .orange
        case .riffTransfer: return .green
        case .magenta: return .pink
        }
    }
    
    // MARK: - Header
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
    
    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 16) {
            // BPM Display
            bpmDisplaySection
            
            // Mode Toggle Section (3 modes now!)
            modeToggleSection
            
            // Prompt Section
            if selectedMode == .magenta {
                magentaStylesSection // new: rows of [TextField + 0-1 Slider], + add-row, loop_weight, bars, Advanced
            } else {
                promptSection
            }
            
            // Mode-specific sections
            if selectedMode == .styleTransfer {
                styleTransferSection
            } else if selectedMode == .riffTransfer {
                riffTransferSection
            }
            
            if selectedMode != .magenta {
                barsSection
            }
            
            if selectedMode != .magenta {
                advancedToggle
                if showAdvanced { advancedSection }
            }
            
            // Generate Button
            generateButton
            
            // Error Display
            if let errorMessage = audioManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Mode Toggle Section (3 modes!)
    private var modeToggleSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Generate Mode
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = .generate
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "pianokeys")
                            .font(.title3)
                        Text("Generate")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(selectedMode == .generate ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedMode == .generate ? Color.purple.opacity(0.3) : Color.gray.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedMode == .generate ? Color.purple : Color.gray.opacity(0.5), lineWidth: 2)
                            )
                    )
                }
                
                // Style Transfer Mode
                Button(action: {
                    if canUseStyleTransfer {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedMode = .styleTransfer
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "paintbrush.fill")
                            .font(.title3)
                        Text("Style Transfer")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(selectedMode == .styleTransfer ? .white : (canUseStyleTransfer ? .orange : .gray))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedMode == .styleTransfer ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedMode == .styleTransfer ? Color.orange : (canUseStyleTransfer ? Color.orange.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: 2)
                            )
                    )
                }
                .disabled(!canUseStyleTransfer)
                
                // NEW: Riff Transfer Mode
                Button(action: {
                    if canUseMagenta {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedMode = .magenta
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.title3)
                        Text("Magenta")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(selectedMode == .magenta ? .white : (canUseMagenta ? .pink : .gray))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedMode == .magenta ? Color.pink.opacity(0.3) : Color.gray.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedMode == .magenta ? Color.pink : (canUseMagenta ? Color.pink.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: 2)
                            )
                    )
                }
                .disabled(!canUseMagenta)
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

// MARK: - Magenta Styles Section
private var magentaStylesSection: some View {
    VStack(spacing: 12) {

        // Styles list
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Styles & Weights")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    magentaStyles.append(StyleEntry(text: "", weight: 1.0))
                    if magentaStyles.count > 4 { magentaStyles.removeLast() } // optional cap
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.pink)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink.opacity(0.6), lineWidth: 1))
                }
                .disabled(magentaStyles.count >= 4) // allow 2–4 entries; tweak as you like
            }

            ForEach($magentaStyles) { $entry in
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("e.g. acid house, trumpet, lofi", text: $entry.text)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.subheadline)

                        // Remove row
                        if magentaStyles.count > 1 {
                            Button {
                                if let idx = magentaStyles.firstIndex(where: { $0.id == entry.id }) {
                                    magentaStyles.remove(at: idx)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.pink)
                            }
                        }
                    }

                    HStack {
                        Text("Weight")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Slider(value: $entry.weight, in: 0...1, step: 0.01)
                        Text(String(format: "%.2f", entry.weight))
                            .font(.caption2)
                            .foregroundColor(.pink)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.pink.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pink.opacity(0.25), lineWidth: 1))
            }
        }

        // Loop influence
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Loop Influence")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", magentaLoopWeight))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.pink)
            }
            Slider(value: $magentaLoopWeight, in: 0...1, step: 0.01)
        }

        // Bars (4 or 8)
        VStack(alignment: .leading, spacing: 8) {
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
        
        // Keep jamming toggle
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("jam")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: $magentaKeepJamming)
                    .labelsHidden()
                    .tint(.pink)
            }
            Text("When enabled, the main button will start a continuous Magenta session.")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding(.top, 4)

        // Advanced (Magenta-specific)
        DisclosureGroup {
            VStack(spacing: 12) {
                HStack {
                    Text("Temperature")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.2f", magentaTemperature))
                        .font(.caption2)
                        .foregroundColor(.pink)
                }
                Slider(value: $magentaTemperature, in: 0...4.0, step: 0.05)

                HStack {
                    Text("Top-K")
                        .font(.caption)
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

                HStack {
                    Text("Guidance Weight")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.2f", magentaGuidance))
                        .font(.caption2)
                        .foregroundColor(.pink)
                }
                Slider(value: $magentaGuidance, in: 0...10.0, step: 0.05)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Text("Advanced (Magenta)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
    .transition(.asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
    ))
}
    
    // MARK: - Style Transfer Section (existing)
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
    
    // MARK: - NEW: Riff Transfer Section
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
        case .magenta:       return "Styles & Weights" // or "" if hiding promptSection
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
    
    // MARK: - Advanced Toggle & Section (existing)
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
            (selectedMode != .magenta &&
             prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
            (selectedMode == .styleTransfer && !canUseStyleTransfer)
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
    
    // MARK: - Actions
    private func randomizePrompt() {
        withAnimation(.easeInOut(duration: 0.2)) {
            prompt = InstrumentPrompts.getCleanInstrumentPrompt()
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
                let req = LoopAudioManager.PendingJamRequest(
                    bpm: globalBPM,
                    barsPerChunk: magentaBars, // 4 or 8
                    styles: magentaStyles.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                    styleWeights: magentaStyles.map(\.weight),
                    loopWeight: magentaLoopWeight,
                    temperature: magentaTemperature,
                    topK: magentaTopK,
                    guidanceWeight: magentaGuidance
                )
                audioManager.requestStartMagentaJam(
                    bpm: req.bpm,
                    barsPerChunk: req.barsPerChunk,
                    styles: req.styles,
                    styleWeights: req.styleWeights,
                    loopWeight: req.loopWeight,
                    temperature: req.temperature,
                    topK: req.topK,
                    guidanceWeight: req.guidanceWeight
                )
                // close popup immediately; main view will now show "Stop Jamming"
                //dismiss() // however you dismiss the popup (Binding/Environment)
            } else {
                // existing one-shot generateInstrumentMagenta(...)
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
