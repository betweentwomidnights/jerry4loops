import SwiftUI
import AVFoundation

struct LoopJamView: View {
    @StateObject private var audioManager = LoopAudioManager()
    @StateObject private var playerManager = EngineLoopPlayerManager()
    
    // Global BPM state
    @State private var globalBPM: Int = 120
    
    // UI state
    @State private var showDrumConfig: Bool = false
    @State private var showInstrumentConfig: Bool = false
    @State private var showMagentaConfig: Bool = false
    
    @State private var isGloballyPlaying: Bool = false
    
    @State private var showDrumSaveDialog: Bool = false
    @State private var showInstrumentSaveDialog: Bool = false
    @State private var drumSaveName: String = ""
    @State private var instrumentSaveName: String = ""
    
    @State private var showLoopGrid: Bool = false
    
    private var isJamming: Bool {
        audioManager.jamState.isActive
    }
    private var jamBusy: Bool {
        audioManager.jamState.isBusy
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Global BPM Header
                globalBPMSection
                
                
                
                // Drum Generator Section
                drumGeneratorSection
                
                Spacer()
                
                // Instrument Generator Section
                instrumentGeneratorSection
                
            
                
                // Global Transport Controls
                globalTransportControls
                
                Spacer(minLength: 50)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            
            // Loop Grid Slide-out (positioned on the left side)
                    VStack {
                        Spacer()
                        HStack {
                            LoopGridSlideOut(
                                isExpanded: $showLoopGrid,
                                globalBPM: globalBPM,
                                audioManager: audioManager,
                                playerManager: playerManager
                            )
                            Spacer()
                        }
                        Spacer()
                    }
                    .zIndex(5) // Keep above main content
            
            // Drum Save Dialog
            .sheet(isPresented: $showDrumSaveDialog) {
                SaveLoopDialog(
                    isPresented: $showDrumSaveDialog,
                    loopName: $drumSaveName,
                    loopType: "Drums",
                    metadata: playerManager.drumLoopMetadata,
                    onSave: { name in
                        audioManager.saveDrumLoopPermanently(withName: name)
                    }
                )
            }

            // Instrument Save Dialog
            .sheet(isPresented: $showInstrumentSaveDialog) {
                SaveLoopDialog(
                    isPresented: $showInstrumentSaveDialog,
                    loopName: $instrumentSaveName,
                    loopType: "Instruments",
                    metadata: playerManager.instrumentLoopMetadata,
                    onSave: { name in
                        audioManager.saveInstrumentLoopPermanently(withName: name)
                    }
                )
            }
            
            // Drum Configuration Popup
            DrumConfigPopup(
                isVisible: $showDrumConfig,
                audioManager: audioManager,
                globalBPM: globalBPM
            )
            
            // Instrument Configuration Popup
            InstrumentConfigPopup(
                isVisible: $showInstrumentConfig,
                audioManager: audioManager,
                globalBPM: globalBPM
            )
            
            MagentaConfigPopup(
                isVisible: $showMagentaConfig,
                audioManager: audioManager,
                globalBPM: globalBPM
            )
        }
        .onAppear {
            // Connect audio manager with player manager for coordination
            audioManager.connectPlayerManager(playerManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .drumLoopGenerated)) { notification in
            if let audioURL = notification.userInfo?["audioURL"] as? URL,
               let userInfo = notification.userInfo {
                // Convert [AnyHashable : Any] to [String : Any]
                let metadata = Dictionary(uniqueKeysWithValues:
                    userInfo.compactMap { key, value in
                        if let stringKey = key as? String {
                            return (stringKey, value)
                        }
                        return nil
                    }
                )
                print("🥁 Received drum loop with metadata: \(metadata.keys)")
                playerManager.loadDrumLoop(audioURL, metadata: metadata)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .drumLoopSwitched)) { notification in
            if let newAudioURL = notification.userInfo?["newAudioURL"] as? URL {
                print("🔄 UI: Drum loop switched to \(newAudioURL.lastPathComponent)")
                // UI automatically updates via @Published properties
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .instrumentLoopSwitched)) { notification in
            if let newAudioURL = notification.userInfo?["newAudioURL"] as? URL {
                print("🔄 UI: Instrument loop switched to \(newAudioURL.lastPathComponent)")
                // UI automatically updates via @Published properties
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .instrumentLoopGenerated)) { notification in
            if let audioURL = notification.userInfo?["audioURL"] as? URL,
               let userInfo = notification.userInfo {
                // Convert [AnyHashable : Any] to [String : Any]
                let metadata = Dictionary(uniqueKeysWithValues:
                    userInfo.compactMap { key, value in
                        if let stringKey = key as? String {
                            return (stringKey, value)
                        }
                        return nil
                    }
                )
                print("🎹 Received instrument loop with metadata: \(metadata.keys)")
                playerManager.loadInstrumentLoop(audioURL, metadata: metadata)
            }
        }
        // MARK: - Add to onReceive notifications in body (ADDITION)
        .onReceive(NotificationCenter.default.publisher(for: .bpmChanged)) { notification in
            if let newBPM = notification.userInfo?["newBPM"] as? Int {
                print("🎵 UI received BPM change notification: \(newBPM)")
                // UI will automatically update via @Published properties
            }
        }
    }
    
    // MARK: - Global BPM Section (UPDATED)
    private var globalBPMSection: some View {
        VStack(spacing: 4) {
            
            Text("GLOBAL BPM")
                .font(.caption)
                .foregroundColor(.gray)
            
            GlobalBPMWheel(
                bpm: $globalBPM,
                isLocked: isGloballyPlaying
            )
            .onChange(of: globalBPM) { newBPM in
                if !isGloballyPlaying {
                    // Only allow BPM changes when stopped
                    handleBPMChange(newBPM)
                }
            }
            
            // BPM Status Text
            Group {
                if isGloballyPlaying {
                    Text("🔒 BPM locked during playback")
                        .font(.caption2)
                        .foregroundColor(.orange.opacity(0.8))
                } else if globalBPM != 120 {
                    Text("Fresh session • All loops cleared")
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.8))
                } else {
                    Text("Ready to jam")
                        .font(.caption2)
                        .foregroundColor(.green.opacity(0.8))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isGloballyPlaying)
            .animation(.easeInOut(duration: 0.2), value: globalBPM)
        }
    }

    // MARK: - BPM Change Handler (NEW)
    private func handleBPMChange(_ newBPM: Int) {
        print("🎵 BPM changed to \(newBPM) - starting fresh session")
        
        // Update player manager
        playerManager.updateBPM(newBPM)
        
        // Clear all current audio state
        clearCurrentSession()
        
        // Notify LoopGridSlideOut to clear its slots
        NotificationCenter.default.post(
            name: .bpmChanged,
            object: nil,
            userInfo: ["newBPM": newBPM]
        )
        
        // Visual feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }

    // MARK: - Session Clearing (NEW)
    private func clearCurrentSession() {
        // Stop any playback
        playerManager.stopAll()
        isGloballyPlaying = false
        
        // Clear player manager state
        playerManager.drumAudioURL = nil
        playerManager.instrumentAudioURL = nil
        playerManager.drumLoopMetadata = nil
        playerManager.instrumentLoopMetadata = nil
        
        print("🧹 Session cleared - ready for new BPM")
    }

    
    // MARK: - Drum Generator Section
    private var drumGeneratorSection: some View {
        VStack(spacing: 16) {
            // Title and Generate/Save Buttons
            HStack {
                Text("DRUMS")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: {
                            showDrumConfig = true
                        }) {
                            Image(systemName: "waveform")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                            .opacity(audioManager.isGenerating ? 0.5 : 1.0)
                        }
                        .disabled(audioManager.isGenerating)
                    }
                    
                    Button(action: {
                        // Set default name based on current drum metadata
                        if let metadata = playerManager.drumLoopMetadata {
                            let bpm = metadata["detected_bpm"] as? Int ?? globalBPM
                            let bars = metadata["bars"] as? Int ?? 1
                            drumSaveName = "Drums \(bpm)bpm \(bars)bars"
                        } else {
                            drumSaveName = "Drums \(globalBPM)bpm"
                        }
                        showDrumSaveDialog = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                    .disabled(playerManager.drumAudioURL == nil)
                }
            }
            
            // Waveform Display
            DrumWaveformView(
                audioURL: playerManager.drumAudioURL,
                isPlaying: $isGloballyPlaying,
                playerManager: playerManager
            )
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(playerManager.drumNextLoopQueued ? Color.orange : Color.red, lineWidth: 2)
                    )
            )
            
            // Filter and Reverb Controls Row
            HStack(spacing: 20) {
                // Filter Knob
                FilterKnob(
                    frequency: $playerManager.filterFrequency,
                    onFrequencyChange: { freq in
                        playerManager.setFilterFrequency(freq)
                    }
                )
                
                // Reverb Knob
                ReverbKnob(
                    reverbAmount: $playerManager.reverbAmount,
                    onReverbChange: { amount in
                        playerManager.setReverbAmount(amount)
                    }
                )
                
                Button(action: {}) {
                    Image(systemName: "waveform.path")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding()
                        .background(playerManager.isStuttering ? Color.orange : Color.yellow)
                        .cornerRadius(8)
                }
                .scaleEffect(playerManager.isStuttering ? 1.1 : 1.0)
                .onLongPressGesture(
                    minimumDuration: 0,
                    maximumDistance: .infinity,
                    pressing: { pressing in
                        if pressing {
                            playerManager.startStutter()
                        } else {
                            playerManager.stopStutter()
                        }
                    },
                    perform: {}
                )
                
                Spacer()
                
                // Enhanced Status Text with Live Coding Indicators
                VStack(alignment: .trailing, spacing: 4) {
                    if audioManager.isGenerating {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(0.8)
                            
                            if playerManager.isPlaying {
                                Text("Live coding: Next loop generating...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Generating drums...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    } else if playerManager.drumNextLoopQueued {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Next loop ready")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Text("Will switch at loop end")
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.7))
                    } else if playerManager.drumAudioURL == nil {
                        Text("No drum loop loaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Drum loop ready • \(globalBPM) BPM")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    // Additional live coding status
                    if playerManager.isPlaying && !audioManager.isGenerating && !playerManager.drumNextLoopQueued {
                        Text("🎵 Live coding ready")
                            .font(.caption2)
                            .foregroundColor(.blue.opacity(0.8))
                    }
                }
            }
        }
    }
    
    // MARK: - Instrument Generator Section
    private var instrumentGeneratorSection: some View {
        VStack(spacing: 16) {
            // Title and Generate/Save Buttons
            HStack {
                Text("INSTRUMENTS")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 12) {
                    if isJamming && !jamBusy {
                        Button(action: {
                            // hardcoded first-pass reseed (2 bars anchor)
                            audioManager.requestReseedSplice(anchorBars: 2.0)
                            let haptic = UIImpactFeedbackGenerator(style: .rigid)
                            haptic.impactOccurred()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("RESEED")
                            }
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.pink)
                            .cornerRadius(8)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                    Button(action: {
                        switch audioManager.jamState {
                        case .idle, .error:
                            showInstrumentConfig = true
                        case .running:
                            showMagentaConfig = true     // <- open MagentaConfigPopup instead of stopping
                        case .starting, .stopping:
                            break
                        }
                    }) {
                        Image(systemName: isJamming ? "slider.horizontal.3" : "pianokeys")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(isJamming ? Color.pink : Color.purple)
                        .cornerRadius(8)
                        .opacity(jamBusy ? 0.7 : 1.0)
                    }
                    .disabled(audioManager.isGenerating || jamBusy)
                    
                    Button(action: {
                        // Set default name based on current instrument metadata
                        if let metadata = playerManager.instrumentLoopMetadata {
                            let bpm = metadata["detected_bpm"] as? Int ?? globalBPM
                            let bars = metadata["bars"] as? Int ?? 1
                            instrumentSaveName = "Instruments \(bpm)bpm \(bars)bars"
                        } else {
                            instrumentSaveName = "Instruments \(globalBPM)bpm"
                        }
                        showInstrumentSaveDialog = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                    .disabled(playerManager.instrumentAudioURL == nil)
                }
            }
            
            InstrumentWaveformView(
                audioURL: playerManager.instrumentAudioURL,
                isPlaying: $isGloballyPlaying,
                playerManager: playerManager
            )
                .frame(height: 100)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(playerManager.instrumentNextLoopQueued ? Color.orange : Color.purple, lineWidth: 2)
                        )
                )
            
            HStack(spacing: 20) {
                // Instrument Filter Knob
                FilterKnob(
                    frequency: $playerManager.instrumentFilterFrequency,
                    onFrequencyChange: { freq in
                        playerManager.setInstrumentFilterFrequency(freq)
                    }
                )
                
                // LFO Checkbox
                        HStack(spacing: 6) {
                            Button(action: {
                                playerManager.setInstrumentLFOEnabled(!playerManager.instrumentLFOEnabled)
                            }) {
                                Image(systemName: playerManager.instrumentLFOEnabled ? "checkmark.square.fill" : "square")
                                    .foregroundColor(playerManager.instrumentLFOEnabled ? .purple : .gray)
                            }
                            
                            Text("LFO")
                                .font(.caption2)
                                .foregroundColor(playerManager.instrumentLFOEnabled ? .purple : .gray)
                        }
                
                // Instrument Reverb Knob
                ReverbKnob(
                    reverbAmount: $playerManager.instrumentReverbAmount,
                    onReverbChange: { amount in
                        playerManager.setInstrumentReverbAmount(amount)
                    }
                )
                
                Spacer()
                
                // Enhanced Status Text with Live Coding Indicators
                VStack(alignment: .trailing, spacing: 4) {
                    if audioManager.isGenerating {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(0.8)
                            
                            if playerManager.isPlaying {
                                Text("Live coding: Next loop generating...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Generating instruments...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    } else if playerManager.instrumentNextLoopQueued {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("Next loop ready")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Text("Will switch at loop end")
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.7))
                    } else if playerManager.instrumentAudioURL == nil {
                        Text("No instrument loop loaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Instrument loop ready • \(globalBPM) BPM")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    
                    // Additional live coding status
                    if playerManager.isPlaying && !audioManager.isGenerating && !playerManager.instrumentNextLoopQueued {
                        Text("🎹 Live coding ready")
                            .font(.caption2)
                            .foregroundColor(.purple.opacity(0.8))
                    }
                }
            }
        }
    }
    
    // MARK: - Global Transport Controls
    private var globalTransportControls: some View {
        HStack(spacing: 20) {
            // Play/Stop Button
            Button(action: toggleGlobalPlayback) {
                Image(systemName: isGloballyPlaying ? "stop.fill" : "play.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(isGloballyPlaying ? Color.red : Color.green)
                    )
            }
            .disabled(playerManager.drumAudioURL == nil)
            
            // Enhanced status indicator
            if isGloballyPlaying {
                VStack(spacing: 2) {
                    Text("PLAYING")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    Text("\(globalBPM) BPM")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    if playerManager.drumNextLoopQueued || playerManager.instrumentNextLoopQueued {
                        Text("Next: Ready")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else if audioManager.isGenerating {
                        Text("Next: Generating...")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
    }
    
    //MARK: - Save Dialog
    
    // Save Dialog Component
    struct SaveLoopDialog: View {
        @Binding var isPresented: Bool
        @Binding var loopName: String
        let loopType: String
        let metadata: [String: Any]?
        let onSave: (String) -> Void
        
        var body: some View {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Save \(loopType) Loop")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top)
                    
                    // Show metadata preview
                    if let metadata = metadata {
                        VStack(alignment: .leading, spacing: 8) {
                            if let originalPrompt = metadata["original_prompt"] as? String {
                                Text("Prompt: \(originalPrompt)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack {
                                if let bpm = metadata["detected_bpm"] as? Int {
                                    Text("\(bpm) BPM")
                                }
                                if let bars = metadata["bars"] as? Int {
                                    Text("• \(bars) bars")
                                }
                                if let duration = metadata["loop_duration_seconds"] as? Double {
                                    Text("• \(String(format: "%.1f", duration))s")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Loop Name")
                            .font(.headline)
                        
                        TextField("Enter name for this loop", text: $loopName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onAppear {
                                // Select all text when dialog appears
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                                }
                            }
                    }
                    
                    Spacer()
                    
                    // Save/Cancel buttons
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        
                        Button("Save") {
                            onSave(loopName.trimmingCharacters(in: .whitespacesAndNewlines))
                            isPresented = false
                        }
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.green)
                        .cornerRadius(8)
                        .disabled(loopName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding()
                .navigationBarHidden(true)
            }
            .presentationDetents([.medium])
        }
    }
    
    // MARK: - Actions
    private func toggleGlobalPlayback() {
        if isGloballyPlaying {
            playerManager.stopAll()
        } else {
            playerManager.startLooping()
        }
        isGloballyPlaying.toggle()
    }
}

// MARK: - Real Instrument Waveform View
struct InstrumentWaveformView: View {
    let audioURL: URL?
    @Binding var isPlaying: Bool
    let playerManager: EngineLoopPlayerManager
    
    @State private var totalSamples: Int = 0
    
    var body: some View {
        ZStack {
            if let audioURL = audioURL {
                FilteredWaveformWrapper(
                    audioURL: audioURL,
                    totalSamples: $totalSamples,
                    waveformId: "instruments", // Different ID from drums
                    waveformColor: Color.purple,    // Purple theme
                    onSeek: { time in
                        // Could add instrument seeking later
                        print("🎹 Instrument seek to \(time)s")
                    }
                )
                .background(Color.black)
                .cornerRadius(6)
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.largeTitle)
                        .foregroundColor(.purple.opacity(0.5))
                    
                    Text("No instrument loop loaded")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(6)
            }
            
            // Play indicator overlay
            if isPlaying && audioURL != nil {
                VStack {
                    HStack {
                        Image(systemName: "pianokeys")
                            .foregroundColor(.purple.opacity(0.8))
                            .font(.caption)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }
}

struct GlobalBPMWheel: View {
    @Binding var bpm: Int
    let isLocked: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var startingBPM: Int = 120
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(bpm)")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(isLocked ? .gray : .white)
                .frame(width: 80, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isLocked ? Color.gray.opacity(0.2) : Color.gray.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isLocked ? Color.gray.opacity(0.5) : Color.red, lineWidth: 2)
                )
                .offset(y: isLocked ? 0 : dragOffset * 0.1)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isLocked else { return }
                            
                            dragOffset = value.translation.height
                            
                            let sensitivity: CGFloat = 0.5
                            let change = Int(-value.translation.height * sensitivity)
                            let newBPM = max(60, min(200, startingBPM + change))
                            
                            if newBPM != bpm {
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                bpm = newBPM
                            }
                        }
                        .onEnded { _ in
                            guard !isLocked else { return }
                            
                            startingBPM = bpm
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                )
        }
        .opacity(isLocked ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isLocked)
    }
}

#Preview {
    LoopJamView()
}
