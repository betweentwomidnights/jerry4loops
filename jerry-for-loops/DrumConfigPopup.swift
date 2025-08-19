import SwiftUI

struct DrumConfigPopup: View {
    @Binding var isVisible: Bool
    let audioManager: LoopAudioManager
    let globalBPM: Int
    
    // Configuration state
    @State private var prompt: String = "hard hitting trap drums"
    @State private var steps: Int = 8
    @State private var cfgScale: Double = 1.0
    @State private var seed: Int = -1
    @State private var useRandomSeed: Bool = true
    @State private var bars: Int? = nil // Auto-calculate by default
    @State private var showAdvanced: Bool = false
    
    // NEW: Style transfer specific state
    @State private var styleStrength: Float = 0.8
    @State private var showStyleTransferMode: Bool = false
    
    // Computed property to check if style transfer is available
    private var canUseStyleTransfer: Bool {
        return audioManager.playerManager?.drumAudioURL != nil &&
               audioManager.playerManager?.instrumentAudioURL != nil
    }
    
    var body: some View {
        ZStack {
            // Background overlay
            if isVisible {
                Color.black.opacity(0.7)
                    .edgesIgnoringSafeArea(.all)
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
                                .stroke(showStyleTransferMode ? Color.orange : Color.red, lineWidth: 2)
                        )
                )
                .frame(maxWidth: 360) // Slightly wider for style transfer content
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(showStyleTransferMode ? "DRUM STYLE TRANSFER" : "DRUM LOOP CONFIG")
                    .font(.headline)
                    .foregroundColor(.white)
                
                if showStyleTransferMode {
                    Text("Using current loop mix")
                        .font(.caption)
                        .foregroundColor(.orange.opacity(0.8))
                }
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
    
    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: 16) {
            // BPM Display (read-only)
            bpmDisplaySection
            
            // Mode Toggle Section
            modeToggleSection
            
            // Prompt Section
            promptSection
            
            // Bars Selection
            barsSection
            
            // Style Transfer Specific Controls
            if showStyleTransferMode {
                styleTransferSection
            }
            
            // Advanced Settings Toggle
            advancedToggle
            
            // Advanced Settings
            if showAdvanced {
                advancedSection
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
    
    // MARK: - Mode Toggle Section (NEW)
    private var modeToggleSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Standard Generation
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showStyleTransferMode = false
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.title2)
                        Text("Generate")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(showStyleTransferMode ? .gray : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(showStyleTransferMode ? Color.gray.opacity(0.2) : Color.red.opacity(0.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(showStyleTransferMode ? Color.gray.opacity(0.5) : Color.red, lineWidth: 2)
                            )
                    )
                }
                
                // Style Transfer
                Button(action: {
                    if canUseStyleTransfer {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showStyleTransferMode = true
                        }
                    }
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "paintbrush.fill")
                            .font(.title2)
                        Text("Style Transfer")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(showStyleTransferMode ? .white : (canUseStyleTransfer ? .orange : .gray))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(showStyleTransferMode ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(showStyleTransferMode ? Color.orange : (canUseStyleTransfer ? Color.orange.opacity(0.5) : Color.gray.opacity(0.3)), lineWidth: 2)
                            )
                    )
                }
                .disabled(!canUseStyleTransfer)
            }
            
            // Style transfer availability indicator
            if !canUseStyleTransfer {
                Text("Style transfer requires both drum and instrument loops")
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Style Transfer Section (NEW)
    private var styleTransferSection: some View {
        VStack(spacing: 12) {
            // Style strength control
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
            
            // Style transfer explanation
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
                
                Text("• Combines your current drum + instrument loops\n• Uses this mix as the foundation for new drums\n• Higher strength = more transformation")
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
            Text(showStyleTransferMode ? "Target Drum Style" : "Drum Style")
                .font(.subheadline)
                .foregroundColor(.white)
            
            HStack(spacing: 12) {
                TextField("describe your drums...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.subheadline)
                
                // Randomize button
                Button(action: randomizePrompt) {
                    Image(systemName: "dice")
                        .font(.title2)
                        .foregroundColor(showStyleTransferMode ? .orange : .red)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(showStyleTransferMode ? .orange : .red, lineWidth: 1)
                        )
                }
            }
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
                            .background(bars == barCount ? (showStyleTransferMode ? Color.orange : Color.red) : Color.gray.opacity(0.3))
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
    
    // MARK: - Advanced Toggle
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
    
    // MARK: - Advanced Section
    private var advancedSection: some View {
        VStack(spacing: 16) {
            // Steps and CFG
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
                    min: 0.5,
                    max: 6.0,
                    step: 0.1
                )
            }
            
            // Seed Section
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
                            .background(useRandomSeed ? (showStyleTransferMode ? Color.orange : Color.red) : Color.gray.opacity(0.3))
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
                                .foregroundColor(showStyleTransferMode ? .orange : .red)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.gray.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(showStyleTransferMode ? .orange : .red, lineWidth: 1)
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
                        .stroke((showStyleTransferMode ? Color.orange : Color.red).opacity(0.3), lineWidth: 1)
                )
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    // MARK: - Generate Button
    private var generateButton: some View {
        Button(action: generateDrumLoop) {
            HStack {
                if audioManager.isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text(showStyleTransferMode ? "Style Transferring..." : "Generating...")
                } else {
                    if showStyleTransferMode {
                        Image(systemName: "paintbrush.fill")
                        Text("STYLE TRANSFER DRUMS")
                    } else {
                        Text("GENERATE DRUM LOOP")
                    }
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(audioManager.isGenerating ? Color.gray : (showStyleTransferMode ? Color.orange : Color.red))
            .cornerRadius(12)
        }
        .disabled(audioManager.isGenerating ||
                 prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                 (showStyleTransferMode && !canUseStyleTransfer))
    }
    
    // MARK: - Actions
    private func randomizePrompt() {
        withAnimation(.easeInOut(duration: 0.2)) {
            prompt = BeatPrompts.getRandomDrumPrompt()
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
    
    private func generateDrumLoop() {
        // Hide keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        if showStyleTransferMode {
            // Use style transfer generation
            audioManager.generateDrumStyleTransfer(
                prompt: prompt,
                bpm: globalBPM,
                styleStrength: styleStrength,
                steps: steps,
                cfgScale: cfgScale,
                seed: useRandomSeed ? -1 : seed,
                bars: bars
            )
        } else {
            // Use regular generation
            audioManager.generateDrumLoop(
                prompt: prompt,
                bpm: globalBPM,
                steps: steps,
                cfgScale: cfgScale,
                seed: useRandomSeed ? -1 : seed,
                bars: bars
            )
        }
        
        // Close popup after starting generation
        withAnimation(.easeInOut(duration: 0.3)) {
            isVisible = false
        }
    }
}

// **MARK: - Style Strength Slider (IMPROVED)**
struct StyleStrengthSlider: View {
    @Binding var value: Float
    @State private var isDragging: Bool = false
    @State private var startValue: Float = 0
    
    private let minValue: Float = 0.1
    private let maxValue: Float = 1.0
    
    // Sensitivity factor - lower values = less sensitive
    private let sensitivity: Float = 0.5
    
    var body: some View {
        GeometryReader { geometry in
            let sliderWidth = geometry.size.width
            let knobPosition = CGFloat((value - minValue) / (maxValue - minValue)) * sliderWidth
            
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)
                    .cornerRadius(3)
                
                // Active track
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: knobPosition, height: 6)
                    .cornerRadius(3)
                
                // Knob
                Circle()
                    .fill(Color.orange)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .offset(x: knobPosition - 10)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: isDragging)
                    .gesture(
                        DragGesture()
                            .onChanged { gestureValue in
                                if !isDragging {
                                    isDragging = true
                                    startValue = value
                                }
                                
                                // Apply sensitivity dampening
                                let dragAmount = Float(gestureValue.translation.width) * sensitivity
                                let valueRange = maxValue - minValue
                                let dragAsPercentage = dragAmount / Float(sliderWidth)
                                let valueDelta = dragAsPercentage * valueRange
                                
                                let newValue = startValue + valueDelta
                                value = max(minValue, min(maxValue, newValue))
                            }
                            .onEnded { _ in
                                isDragging = false
                                
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                    )
            }
        }
        .frame(height: 20)
    }
}

// MARK: - Slider Control (Existing, keeping for compatibility)
struct SliderControl: View {
    let label: String
    @Binding var value: Int
    let min: Int
    let max: Int
    let step: Int
    
    init(label: String, value: Binding<Int>, min: Int, max: Int, step: Int) {
        self.label = label
        self._value = value
        self.min = min
        self.max = max
        self.step = step
    }
    
    init(label: String, value: Binding<Double>, min: Double, max: Double, step: Double) {
        self.label = label
        self._value = Binding<Int>(
            get: { Int(value.wrappedValue * 10) },
            set: { value.wrappedValue = Double($0) / 10.0 }
        )
        self.min = Int(min * 10)
        self.max = Int(max * 10)
        self.step = Int(step * 10)
    }
    
    @State private var dragOffset: CGFloat = 0
    @State private var startingValue: Int = 0
    
    private var displayValue: String {
        if label.contains("CFG") {
            return String(format: "%.1f", Double(value) / 10.0)
        } else {
            return "\(value)"
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text(displayValue)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 100, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red, lineWidth: 1)
                )
                .offset(y: dragOffset * 0.1)
                .gesture(
                    DragGesture()
                        .onChanged { dragValue in
                            dragOffset = dragValue.translation.height
                            
                            let sensitivity: CGFloat = 2.0
                            let totalChange = -dragValue.translation.height / sensitivity
                            let steppedChange = Int(totalChange / CGFloat(step)) * step
                            let newValue = Swift.max(min, Swift.min(max, startingValue + steppedChange))
                            
                            if newValue != value {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                value = newValue
                            }
                        }
                        .onEnded { _ in
                            startingValue = value
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                )
        }
    }
}

#Preview {
    DrumConfigPopup(
        isVisible: .constant(true),
        audioManager: LoopAudioManager(),
        globalBPM: 120
    )
}
