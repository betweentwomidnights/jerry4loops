import SwiftUI
import AVFoundation

struct LoopJamView: View {
    @StateObject private var audioManager = LoopAudioManager()
    @StateObject private var playerManager = EngineLoopPlayerManager()
    
    // Global BPM state
    @State private var globalBPM: Int = 120
    
    // Only these BPMs are battle-tested for MagentaRT right now.
    private var isMagentaFriendlyBPM: Bool { globalBPM == 100 || globalBPM == 120 }
    
    private enum AlignmentStatus { case excellent, okay, risky }

    private func magentaAlignment(for bpm: Int, bars: Int = 4, fps: Double = 25.0, beatsPerBar: Double = 4.0) -> AlignmentStatus {
        let framesPerBar   = fps * 60.0 * beatsPerBar / Double(bpm)        // 6000 / bpm
        let framesPerChunk = framesPerBar * Double(bars)                    // e.g., 4 bars

        // distance (in frames) to the nearest integer frame
        let barRemainder   = abs(framesPerBar.rounded()   - framesPerBar)
        let chunkRemainder = abs(framesPerChunk.rounded() - framesPerChunk)

        // take the worst-case remainder; if either bar or chunk is "off", we warn
        let worst = max(barRemainder, chunkRemainder)

        // Tune these thresholds to your taste after a bit of field testing:
        if worst < 0.05 {            // < 0.05 frame (~2 ms) is effectively perfect
            return .excellent
        } else if worst < 0.35 {     // small rounding; generally fine in practice
            return .okay
        } else {                     // noticeable rounding; might drift at slice boundaries
            return .risky
        }
    }
    
    
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
    
    @State private var pendingDrumSnapshot: LoopAudioManager.LoopSnapshot?
    @State private var pendingInstrumentSnapshot: LoopAudioManager.LoopSnapshot?
    
    @State private var showStudioMenu: Bool = false
    
    @StateObject private var modelService = ModelService(
        baseURL: "https://thecollabagepatch-magenta-retry.hf.space"
    )
    
    @State private var showRecordingSave: Bool = false
    @State private var pendingRecordingURL: URL?
    @State private var pendingRecordingName: String = ""
    
    @State private var showRecordings: Bool = false
    @StateObject private var recordings = RecordingLibrary()
    
    @State private var recContextDrum: URL?
    @State private var recContextInstr: URL?
    
    @State private var showCountdown = false
    @State private var countdownBeatsRemaining = 4   // 4→3→2→1
    @State private var countdownTimer: Timer?
    
    @State private var armedSpin = false   // simple spinner for the armed state

    
    @State private var transportArmed = false
    
    private func beginCountdownAndRecord() {
        // Guard: must have content to play
        guard hasLoops else { return }

        countdownTimer?.invalidate()
        countdownBeatsRemaining = 4   // show "4" first
        showCountdown = true

        let beatSeconds = 60.0 / Double(globalBPM)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: beatSeconds, repeats: true) { t in
            // Drive one step per beat; only stop the timer when we’re done
            tickCountdown(then: {
                // This closure is now called ONLY when countdown completes
                t.invalidate()
            })
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    private func tickCountdown(then onFinished: (() -> Void)? = nil) {
        if countdownBeatsRemaining > 1 {
            // 4→3→2 (no timer invalidation here)
            countdownBeatsRemaining -= 1
        } else {
            // Reached "1" → start playback and recording
            countdownTimer?.invalidate()
            countdownTimer = nil
            showCountdown = false

            playerManager.startLooping()
            transportArmed = true  // <-- makes the main button show Stop immediately

            // Small lead so the audible start is captured
            let coldStartLead = 0.05
            DispatchQueue.main.asyncAfter(deadline: .now() + coldStartLead) {
                do { try playerManager.startRecording() }
                catch { print("❌ startRecording:", error) }
            }

            onFinished?()
        }
    }

    private var hasLoops: Bool {
        (playerManager.drumAudioURL != nil) || (playerManager.instrumentAudioURL != nil)
    }
    
    private func cancelOverlayCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        showCountdown = false
    }

    private func armToNextDownbeat() {
        // Ask the engine to arm recording; we don’t show numbers anymore.
        _ = playerManager.armRecordingAtNextDrumBoundary()
        armedSpin = true
    }

    private func cancelArming() {
        armedSpin = false
        // If you added this method in EngineLoopPlayerManager, call it:
        playerManager.cancelArming()
    }

    
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            if showCountdown {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    Text("\(countdownBeatsRemaining)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding()
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .transition(.opacity)
                }
                .zIndex(50)
            }
            
            // 2) Inside ZStack (top overlay)
            VStack {
                HStack(spacing: 10) {
                    // Left: Studio menu (unchanged)
                    Button {
                        withAnimation(.spring()) { showStudioMenu = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("Open studio controls")

                    Spacer()

                    // Right: RECORD / STOP
                    Button {
                        if playerManager.isRecording {
                            // STOP immediately → save dialog
                            cancelOverlayCountdown()
                            cancelArming()
                            playerManager.stopRecording { url in
                                guard let url = url else { return }
                                pendingRecordingURL = url
                                pendingRecordingName = url.deletingPathExtension().lastPathComponent
                                showRecordingSave = true
                            }
                        } else if playerManager.recordingArmedUntilHostTime != nil {
                            // Tap while ARMED → cancel arming
                            cancelArming()
                        } else if playerManager.isPlaying {
                            // Transport running → arm to next downbeat (no numeric countdown)
                            armToNextDownbeat()
                        } else {
                            // Transport idle → use big overlay countdown, then auto-play + record
                            beginCountdownAndRecord()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.35))

                            if playerManager.recordingArmedUntilHostTime != nil {
                                // ARMED indicator (animated)
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                    .rotationEffect(.degrees(armedSpin ? 360 : 0))
                                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: armedSpin)
                            } else if playerManager.isRecording {
                                Image(systemName: "stop.fill")
                                    .font(.title2)
                                    .foregroundColor(.red)
                            } else {
                                Image(systemName: "record.circle")
                                    .font(.title2)
                                    .foregroundColor(hasLoops ? .red : .gray)
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .disabled(!hasLoops && !playerManager.isRecording)

                    // New: recordings drawer toggle
                    Button {
                        withAnimation(.spring()) { showRecordings.toggle() }
                        if showRecordings { recordings.refresh() }
                    } label: {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("Show recordings")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                Spacer()
            }
            .zIndex(20)
            
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
            
                    .sheet(isPresented: $showDrumSaveDialog) {
                        SaveLoopDialog(
                            isPresented: $showDrumSaveDialog,
                            loopName: $drumSaveName,
                            loopType: "Drums",
                            metadata: pendingDrumSnapshot?.metadata,     // use SNAPSHOT metadata
                            onSave: { name in
                                if let snap = pendingDrumSnapshot {
                                    audioManager.commitSnapshot(snap, withName: name)
                                    pendingDrumSnapshot = nil
                                }
                            },
                            onCancel: {
                                if let snap = pendingDrumSnapshot {
                                    audioManager.discardSnapshot(snap)
                                    pendingDrumSnapshot = nil
                                }
                            }
                        )
                    }
                    .onChange(of: showDrumSaveDialog) { presented in
                        // If the sheet was dismissed without saving, discard the snapshot
                        if !presented, let snap = pendingDrumSnapshot {
                            audioManager.discardSnapshot(snap)
                            pendingDrumSnapshot = nil
                        }
                    }

            // Instrument Save Dialog
                    .sheet(isPresented: $showInstrumentSaveDialog) {
                        SaveLoopDialog(
                            isPresented: $showInstrumentSaveDialog,
                            loopName: $instrumentSaveName,
                            loopType: "Instruments",
                            metadata: pendingInstrumentSnapshot?.metadata,     // use SNAPSHOT metadata
                            onSave: { name in
                                if let snap = pendingInstrumentSnapshot {
                                    audioManager.commitSnapshot(snap, withName: name)
                                    pendingInstrumentSnapshot = nil
                                }
                            },
                            onCancel: {
                                if let snap = pendingInstrumentSnapshot {
                                    audioManager.discardSnapshot(snap)
                                    pendingInstrumentSnapshot = nil
                                }
                            }
                        )
                    }
                    .onChange(of: showInstrumentSaveDialog) { presented in
                        // If the sheet was dismissed without saving, discard the snapshot
                        if !presented, let snap = pendingInstrumentSnapshot {
                            audioManager.discardSnapshot(snap)
                            pendingInstrumentSnapshot = nil
                        }
                    }
                    .onChange(of: playerManager.isPlaying) { now in
                        transportArmed = now // when engine says playing=false, clear our armed flag too
                    }
            
                    
                    .sheet(isPresented: $showRecordingSave) {
                        SaveRecordingDialog(
                            isPresented: $showRecordingSave,
                            defaultName: $pendingRecordingName,
                            onSave: { name in
                                guard let src = pendingRecordingURL else { return }

                                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                                let recs = docs.appendingPathComponent("recorded_jams", isDirectory: true)
                                try? FileManager.default.createDirectory(at: recs, withIntermediateDirectories: true)

                                var dest = recs.appendingPathComponent(name)
                                if dest.pathExtension.lowercased() != "wav" {
                                    dest.deletePathExtension()
                                    dest.appendPathExtension("wav")
                                }
                                do {
                                    if FileManager.default.fileExists(atPath: dest.path) {
                                        try FileManager.default.removeItem(at: dest)
                                    }
                                    try FileManager.default.moveItem(at: src, to: dest)
                                    print("✅ Saved recording to \(dest.lastPathComponent)")
                                    recordings.refresh() // ← update drawer
                                } catch {
                                    print("❌ Save/move failed: \(error)")
                                }
                            },
                            onCancel: {
                                // Optional: keep the temp file or clean it up
                                try? FileManager.default.removeItem(at: pendingRecordingURL!)
                            }
                        )
                    }
            
            if showStudioMenu {
                StudioMenuPanel(isVisible: $showStudioMenu)
                    .environmentObject(modelService)
                    .environmentObject(audioManager) 
                    .padding(.top, 56)
                    .padding(.leading, 14)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(28) // just under the recordings drawer's 30, above main content
            }
            
            // Recordings overlay
            if showRecordings {
                RecordingsDrawer(isVisible: $showRecordings,   // ← pass the binding
                                 library: recordings)
                    .padding(.top, 56)
                    .padding(.trailing, 14)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(30)
                    .onDisappear { recordings.items.removeAll() }
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
            .environmentObject(modelService)
            
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
        .onReceive(playerManager.$recordingArmedUntilHostTime) { ht in
            // When arming completes (ht becomes nil), stop the armed spinner.
            if ht == nil { armedSpin = false }
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
        .onDisappear {
            // cancel any cold-start overlay countdown
            cancelOverlayCountdown()
            // cancel the “armed” state/spinner + clear engine gate
            cancelArming()
            // reset the transport UI hint
            transportArmed = false
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
                } else {
                    let status = magentaAlignment(for: globalBPM)  // <— compute once

                    switch status {
                    case .excellent:
                        Text("Ready to jam")
                            .font(.caption2)
                            .foregroundColor(.green.opacity(0.85))

                    case .okay:
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle.fill")
                            Text("Heads up: MagentaRT at \(globalBPM) BPM uses tiny rounding. Usually fine.")
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .layoutPriority(1)
                        }
                        .font(.caption2)
                        .foregroundColor(.yellow)

                    case .risky:
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text("Warning: if you plan on using MagentaRT, jam chunks may not line up at \(globalBPM) BPM. Try 100 or 120.")
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .layoutPriority(1)
                        }
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: globalBPM)
            .animation(.easeInOut(duration: 0.2), value: isGloballyPlaying)
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
                        // Freeze the *current* loop immediately
                        pendingDrumSnapshot = audioManager.makeSnapshot(for: .drums)

                        // Default name from the SNAPSHOT metadata (not live UI)
                        if let metadata = pendingDrumSnapshot?.metadata {
                            let bpm = metadata["detected_bpm"] as? Int ?? globalBPM
                            let bars = metadata["bars"] as? Int ?? 1
                            drumSaveName = "Drums \(bpm)bpm \(bars)bars"
                            showDrumSaveDialog = true
                        }
                    }) {
                        HStack(spacing: 6) { Image(systemName: "square.and.arrow.down") }
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.green).cornerRadius(8)
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
            HStack(spacing: 15) {
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
                    Image(systemName: "tornado")
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
                    if audioManager.isDrumGenerating {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(0.8)
                            
                            if playerManager.isPlaying {
                                Text("Next loop generating...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Generating...")
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
                        Text("No loop loaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Loop ready • \(globalBPM)bpm")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    // Additional live coding status
                    if playerManager.isPlaying && !audioManager.isDrumGenerating && !playerManager.drumNextLoopQueued {
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
                        // Freeze the *current* INSTRUMENT loop immediately
                        pendingInstrumentSnapshot = audioManager.makeSnapshot(for: .instruments)

                        // Default name from the SNAPSHOT metadata (not live UI)
                        if let metadata = pendingInstrumentSnapshot?.metadata {
                            let bpm  = metadata["detected_bpm"] as? Int ?? globalBPM
                            let bars = metadata["bars"] as? Int ?? 1
                            instrumentSaveName = "Instruments \(bpm)bpm \(bars)bars"
                        } else {
                            // Fallback name if metadata is missing
                            instrumentSaveName = "Instruments \(globalBPM)bpm"
                        }

                        showInstrumentSaveDialog = (pendingInstrumentSnapshot != nil)
                    }) {
                        HStack(spacing: 6) { Image(systemName: "square.and.arrow.down") }
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(.black)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.green).cornerRadius(8)
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
            
            HStack(spacing: 15) {
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
                    if audioManager.isInstrumentGenerating {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                                .scaleEffect(0.8)
                            
                            if playerManager.isPlaying {
                                Text("Next loop generating...")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Generating...")
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
                        Text("No loop loaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                    } else {
                        Text("Loop ready • \(globalBPM)bpm")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    
                    // Additional live coding status
                    if playerManager.isPlaying && !audioManager.isInstrumentGenerating && !playerManager.instrumentNextLoopQueued {
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
                let willPlay = playerManager.isPlaying || transportArmed
                Image(systemName: willPlay ? "stop.fill" : "play.fill")
                    .font(.title)
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle().fill(willPlay ? Color.red : Color.green)
                    )
            }
            .disabled(playerManager.drumAudioURL == nil && !(playerManager.isPlaying || transportArmed))
            
            // Enhanced status indicator
            if playerManager.isPlaying || transportArmed {
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
        var onCancel: (() -> Void)? = nil
        
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
                            onCancel?()
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
        // If we’re recording, STOP recording and transport, then show save dialog.
        if playerManager.isRecording {
            cancelOverlayCountdown()
            cancelArming()

            playerManager.stopRecording { url in
                guard let url = url else { return }
                pendingRecordingURL = url
                pendingRecordingName = url.deletingPathExtension().lastPathComponent
                showRecordingSave = true
            }

            playerManager.stopAll()
            transportArmed = false
            return
        }

        // Otherwise, normal play/stop toggle (respect “armed” visual state).
        if playerManager.isPlaying || transportArmed {
            cancelOverlayCountdown()
            cancelArming()
            playerManager.stopAll()
            transportArmed = false
        } else {
            playerManager.startLooping()
            transportArmed = true  // flip main button to Stop immediately
        }
    }
}

struct SaveRecordingDialog: View {
    @Binding var isPresented: Bool
    @Binding var defaultName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Save Recording").font(.headline)
                TextField("Recording name", text: $defaultName)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                        }
                    }
                Spacer()
                HStack {
                    Button("Cancel") { onCancel(); isPresented = false }
                        .frame(maxWidth: .infinity).padding().background(Color.gray.opacity(0.2)).cornerRadius(8)
                    Button("Save") { onSave(defaultName.trimmingCharacters(in: .whitespacesAndNewlines)); isPresented = false }
                        .frame(maxWidth: .infinity).padding().background(Color.green).foregroundColor(.white).cornerRadius(8)
                        .disabled(defaultName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
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
