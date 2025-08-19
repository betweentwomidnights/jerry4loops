import Foundation
import AVFoundation

class EngineLoopPlayerManager: NSObject, ObservableObject {
    @Published var drumAudioURL: URL?
    @Published var isPlaying: Bool = false
    @Published var currentBPM: Int = 120
    @Published var isGeneratingNext: Bool = false
    @Published var drumNextLoopQueued: Bool = false
    @Published var instrumentNextLoopQueued: Bool = false
    @Published var filterFrequency: Float = 20000.0 // 20kHz = no filtering
    @Published var reverbAmount: Float = 0.0 // 0-100% reverb
    
    @Published var instrumentAudioURL: URL?
    @Published var instrumentFilterFrequency: Float = 20000.0
    @Published var instrumentReverbAmount: Float = 0.0
    
    // Current loop metadata
    @Published var drumLoopMetadata: [String: Any]?
    @Published var instrumentLoopMetadata: [String: Any]?
    
    // Stutter effect
    @Published var isStuttering: Bool = false
    private let stutterPlayerNode = AVAudioPlayerNode()
    private var stutterBuffer: AVAudioPCMBuffer?
    
    // LFO Properties
    @Published var instrumentLFOEnabled: Bool = false
    private var lfoTimer: Timer?
    private var lfoStartTime: Date?
    private let lfoMinFrequency: Float = 500.0
    
    // MARK: - SIMPLIFIED BEAT-BASED TIMING SYSTEM
    
    // Master timing - everything syncs to this beat grid
    private var masterStartTime: Date?
    private var masterBeatTimer: Timer?
    
    // Beat calculations (all timing based on beats, not seconds)
    private var beatsPerSecond: Double { Double(currentBPM) / 60.0 }
    private var secondsPerBeat: Double { 60.0 / Double(currentBPM) }
    
    // Current loop lengths in beats (calculated once when loaded)
    private var drumLoopBeats: Int = 16  // Default 4 bars = 16 beats
    private var instrumentLoopBeats: Int = 16
    
    // Pending loop switches (queued for next beat boundary)
    private var pendingDrumSwitch: PendingLoopSwitch?
    private var pendingInstrumentSwitch: PendingLoopSwitch?
    
    // Quantized switch grid: 1.0 = every beat, 0.5 = every half-beat, 0.25 = quarter-beat, etc.
    private var drumSwitchGridBeats: Double = 1.0
    private var instrumentSwitchGridBeats: Double = 1.0

    // Keep a small lead so scheduling never lands in the past
    private let minScheduleLeadSeconds: Double = 0.010
    
    private struct PendingLoopSwitch {
        let audioFile: AVAudioFile
        let url: URL
        let metadata: [String: Any]?
        let targetBeat: Int  // Beat number when this should switch
        var preparedBuffer: AVAudioPCMBuffer?  // <— new
    }
    
    // MARK: - Engine clock timing (sample-accurate)
    private var masterStartHostTime: UInt64?
    private let scheduleSafetyLeadSeconds: Double = 0.050  // 50ms safety lead

    private var outputSampleRate: Double {
        audioEngine.outputNode.outputFormat(forBus: 0).sampleRate
    }
    private var framesPerBeat: Double {
        outputSampleRate * (60.0 / Double(currentBPM))
    }
    
    // Current output hostTime from the render clock
    private func engineNowHostTime() -> UInt64? {
        audioEngine.outputNode.lastRenderTime?.hostTime
    }

    // Convert seconds to a hostTime delta
    private func hostTimeDelta(forSeconds seconds: Double) -> UInt64 {
        AVAudioTime.hostTime(forSeconds: seconds)
    }

    // Absolute hostTime for a point "seconds from now"
    private func hostTimeForSecondsFromNow(_ seconds: Double) -> UInt64? {
        guard let now = engineNowHostTime() else { return nil }
        return now &+ hostTimeDelta(forSeconds: seconds)
    }

    // Absolute hostTime for a given beat offset from master start
    private func hostTimeForBeat(_ beat: Double) -> UInt64? {
        guard let master = masterStartHostTime else { return nil }
        let secs = beat * secondsPerBeat
        return master &+ hostTimeDelta(forSeconds: secs)
    }

    // Absolute hostTime for NEXT boundary of a given loop length (in beats)
    private func hostTimeForNextLoopBoundary(loopBeats: Int) -> (hostTime: UInt64, targetBeat: Int)? {
        let current = getCurrentBeat()
        let currentInt = Int(floor(current))
        let beatsIntoLoop = currentInt % loopBeats
        let beatsUntilLoopEnd = loopBeats - beatsIntoLoop
        let targetBeat = currentInt + beatsUntilLoopEnd
        guard let ht = hostTimeForBeat(Double(targetBeat)) else { return nil }
        return (ht, targetBeat)
    }

    // Schedule a node+buffer to start exactly at a hostTime (loops or one-shot)
    private func scheduleLoop(node: AVAudioPlayerNode,
                              buffer: AVAudioPCMBuffer,
                              startHostTime: UInt64,
                              loop: Bool = true,
                              initialVolume: Float = 1.0) {
        node.stop()
        node.volume = initialVolume
        node.scheduleBuffer(buffer, at: nil, options: loop ? .loops : [], completionHandler: nil)
        node.play(at: AVAudioTime(hostTime: startHostTime))
    }

    // Kick off a crossfade right at (or just after) a host boundary
    private func crossfadeAtHostTime(_ boundaryHostTime: UInt64,
                                     from oldNode: AVAudioPlayerNode,
                                     to newNode: AVAudioPlayerNode,
                                     durationMs: Double) {
        guard let now = engineNowHostTime() else {
            // Fallback: start immediately if we can't read the engine clock
            crossfadeNodes(from: oldNode, to: newNode, durationMs: durationMs)
            return
        }
        let nowSec = AVAudioTime.seconds(forHostTime: now)
        let atSec  = AVAudioTime.seconds(forHostTime: boundaryHostTime)
        let delay  = max(0.0, atSec - nowSec)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.crossfadeNodes(from: oldNode, to: newNode, durationMs: durationMs)
        }
    }
    
    private func runAtHostTime(_ ht: UInt64, _ block: @escaping () -> Void) {
        guard let now = engineNowHostTime() else { block(); return }
        let nowSec = AVAudioTime.seconds(forHostTime: now)
        let atSec  = AVAudioTime.seconds(forHostTime: ht)
        let delay  = max(0.0, atSec - nowSec)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block)
    }
    
    // Replace the helper you added earlier with this version
    private func hostTimeForNextQuantizedBoundary(gridBeats: Double) -> (hostTime: UInt64, targetBeat: Double)? {
        guard gridBeats > 0,
              let nowHT = engineNowHostTime(),
              let master = masterStartHostTime else { return nil }

        let current  = getCurrentBeat()
        let nextQ    = ceil(current / gridBeats) * gridBeats
        guard let ht = hostTimeForBeat(nextQ) else { return nil }

        // If the boundary is already in the past (e.g., heavy work delayed us), schedule ASAP with tiny lead.
        let nowSec = AVAudioTime.seconds(forHostTime: nowHT)
        let atSec  = AVAudioTime.seconds(forHostTime: ht)
        if atSec <= nowSec {
            if let asap = hostTimeForSecondsFromNow(minScheduleLeadSeconds) {
                return (asap, nextQ)
            }
            return nil
        }

        // ✅ Do NOT bump to the next grid if we're close — we’ll trust the tiny lead.
        return (ht, nextQ)
    }


    
    // MARK: - AUDIO ENGINE SETUP (unchanged)
    
    private let audioEngine = AVAudioEngine()
    private let currentPlayerNode = AVAudioPlayerNode()
    private let nextPlayerNode = AVAudioPlayerNode()
    private let filterNode = AVAudioUnitEQ(numberOfBands: 1)
    private let reverbNode = AVAudioUnitReverb()
    private let mixerNode = AVAudioMixerNode()
    
    private let instrumentPlayerNode = AVAudioPlayerNode()
    private let nextInstrumentPlayerNode = AVAudioPlayerNode()
    private let instrumentFilterNode = AVAudioUnitEQ(numberOfBands: 1)
    private let instrumentReverbNode = AVAudioUnitReverb()
    private let instrumentMixerNode = AVAudioMixerNode()
    
    // Current audio files
    private var currentDrumFile: AVAudioFile?
    private var currentInstrumentFile: AVAudioFile?
    
    // Node state
    private var isDrumCurrentNodeActive: Bool = true
    private var isInstrumentCurrentNodeActive: Bool = true
    
    private let instrumentCrossfadeMs: Double = 25  // 15–40ms is the sweet spot
    private let drumCrossfadeMs: Double = 25
    
    override init() {
        super.init()
        setupAudioEngine()
        setupAudioSession()
    }
    
    deinit {
        stopAll()
        masterBeatTimer?.invalidate()
        lfoTimer?.invalidate()
        audioEngine.stop()
    }
    
    // MARK: - AUDIO ENGINE SETUP (unchanged from original)
    
    private func setupAudioEngine() {
        // Attach all nodes
        audioEngine.attach(currentPlayerNode)
        audioEngine.attach(nextPlayerNode)
        audioEngine.attach(filterNode)
        audioEngine.attach(reverbNode)
        audioEngine.attach(mixerNode)
        
        audioEngine.attach(instrumentPlayerNode)
        audioEngine.attach(nextInstrumentPlayerNode)
        audioEngine.attach(instrumentFilterNode)
        audioEngine.attach(instrumentReverbNode)
        audioEngine.attach(instrumentMixerNode)
        
        audioEngine.attach(stutterPlayerNode)
        audioEngine.attach(stutterReverb)
        
        // Setup drum effects
        filterNode.bands[0].filterType = .lowPass
        filterNode.bands[0].frequency = filterFrequency
        filterNode.bands[0].bandwidth = 0.5
        filterNode.bands[0].gain = 0.0
        filterNode.bands[0].bypass = false
        
        reverbNode.loadFactoryPreset(.mediumHall)
        reverbNode.wetDryMix = 0.0
        
        // Setup instrument effects
        instrumentFilterNode.bands[0].filterType = .lowPass
        instrumentFilterNode.bands[0].frequency = instrumentFilterFrequency
        instrumentFilterNode.bands[0].bandwidth = 0.5
        instrumentFilterNode.bands[0].gain = 0.0
        instrumentFilterNode.bands[0].bypass = false
        
        instrumentReverbNode.loadFactoryPreset(.mediumHall)
        instrumentReverbNode.wetDryMix = 0.0
        
        
        
        // Audio routing
        audioEngine.connect(currentPlayerNode, to: mixerNode, format: nil)
        audioEngine.connect(nextPlayerNode, to: mixerNode, format: nil)
        // ⟵ CHANGE stutter route: through its private reverb INTO the same drum mixer
            audioEngine.connect(stutterPlayerNode, to: stutterReverb, format: nil)
            audioEngine.connect(stutterReverb,     to: mixerNode,     format: nil)
        audioEngine.connect(mixerNode, to: filterNode, format: nil)
        audioEngine.connect(filterNode, to: reverbNode, format: nil)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: nil)
        
        audioEngine.connect(instrumentPlayerNode, to: instrumentMixerNode, format: nil)
        audioEngine.connect(nextInstrumentPlayerNode, to: instrumentMixerNode, format: nil)
        audioEngine.connect(instrumentMixerNode, to: instrumentFilterNode, format: nil)
        audioEngine.connect(instrumentFilterNode, to: instrumentReverbNode, format: nil)
        audioEngine.connect(instrumentReverbNode, to: audioEngine.mainMixerNode, format: nil)
        
        // Initialize stutter reverb’s preset/mix (low initial wet)
            stutterReverb.loadFactoryPreset(.largeHall2)   // try .plate for tighter tails
            stutterReverb.wetDryMix = stutterReverbMinMix
        
        do {
            try audioEngine.start()
            print("✅ Audio engine started with beat-synchronized timing")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setPreferredSampleRate(48_000)
            try audioSession.setActive(true)
            print("✅ Audio session configured @ \(audioSession.sampleRate) Hz")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - BEAT-BASED TIMING CORE
    
    // Add near your other timing helpers
    private var preScheduleLeadBeats: Double { scheduleSafetyLeadSeconds / secondsPerBeat }

    
    private func getCurrentBeat() -> Double {
        guard
            let master = masterStartHostTime,
            let now = engineNowHostTime()
        else { return 0.0 }
        
        let masterSec = AVAudioTime.seconds(forHostTime: master)
        let nowSec    = AVAudioTime.seconds(forHostTime: now)
        let elapsed   = max(0.0, nowSec - masterSec)
        return elapsed * beatsPerSecond
    }

    
    private func getNextBeatBoundary(for loopBeats: Int) -> Int {
        let currentBeat = getCurrentBeat()
        let currentBeatInt = Int(floor(currentBeat))
        
        // Find the next beat that's aligned to the loop length
        let beatsIntoLoop = currentBeatInt % loopBeats
        let beatsUntilLoopEnd = loopBeats - beatsIntoLoop
        
        return currentBeatInt + beatsUntilLoopEnd
    }
    
    private func startMasterBeatTimer() {
        masterBeatTimer?.invalidate()
        
        // Check for pending switches every 20ms (50Hz) - much more frequent than beat boundaries
        masterBeatTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.processBeatTick()
        }
        
        print("🎯 Master beat timer started")
    }
    
    private func processBeatTick() {
        let currentBeat = getCurrentBeat()
        let leadBeats   = preScheduleLeadBeats
        let currentBeatInt = Int(floor(currentBeat))

        // Handle "both" case first when they target the same beat
        if let drumPending = pendingDrumSwitch,
           let instrumentPending = pendingInstrumentSwitch,
           drumPending.targetBeat == instrumentPending.targetBeat,
           Double(drumPending.targetBeat) - currentBeat <= leadBeats {

            executeBothSwitchesSynchronized(drum: drumPending, instrument: instrumentPending)
            pendingDrumSwitch = nil
            pendingInstrumentSwitch = nil

        } else {
            if let pending = pendingDrumSwitch,
               Double(pending.targetBeat) - currentBeat <= leadBeats {
                executeDrumSwitch(pending)
                pendingDrumSwitch = nil
            }

            if let pending = pendingInstrumentSwitch,
               Double(pending.targetBeat) - currentBeat <= leadBeats {
                executeInstrumentSwitch(pending)
                pendingInstrumentSwitch = nil
            }
        }

        // UI progress stays the same
        updateBeatBasedProgress(currentBeat: currentBeat)
    }

    
    // MARK: - LOOP LOADING (SIMPLIFIED)
    
    func loadDrumLoop(_ url: URL, metadata: [String: Any]? = nil) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let beats = calculateBeatsFromMetadata(metadata, defaultBeats: 16)
            
            if isPlaying {
                // Queue for next beat boundary
                let targetBeat = getNextBeatBoundary(for: drumLoopBeats)
                pendingDrumSwitch = PendingLoopSwitch(
                    audioFile: audioFile,
                    url: url,
                    metadata: metadata,
                    targetBeat: targetBeat
                )
                
                drumNextLoopQueued = true
                print("🥁 Queued drum switch for beat \(targetBeat)")
                
            } else {
                // Load immediately
                loadDrumImmediately(audioFile: audioFile, url: url, metadata: metadata, beats: beats)
            }
            
        } catch {
            print("❌ Failed to load drum loop: \(error)")
            drumAudioURL = nil
            currentDrumFile = nil
            drumLoopMetadata = nil
        }
    }
    
    func loadInstrumentLoop(_ url: URL, metadata: [String: Any]? = nil) {
        do {
            let beats = calculateBeatsFromMetadata(metadata, defaultBeats: 16)
            let targetBeat = getNextBeatBoundary(for: instrumentLoopBeats)
            let audioFile = try AVAudioFile(forReading: url)

            // Pre-read
            let frames = AVAudioFrameCount(audioFile.length)
            let fmt    = audioFile.processingFormat
            let buf    = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)
            audioFile.framePosition = 0
            try audioFile.read(into: buf!)
            
            if isPlaying {
                // Queue for next beat boundary
                let targetBeat = getNextBeatBoundary(for: instrumentLoopBeats)
                pendingInstrumentSwitch = PendingLoopSwitch(
                    audioFile: audioFile,
                    url: url,
                    metadata: metadata,
                    targetBeat: targetBeat,
                    preparedBuffer: buf // <— stash it
                )
                instrumentNextLoopQueued = true
                print("🎹 Queued instrument switch for beat \(targetBeat)")
                
            } else {
                // Load immediately
                loadInstrumentImmediately(audioFile: audioFile, url: url, metadata: metadata, beats: beats)
            }
            
        } catch {
            print("❌ Failed to load instrument loop: \(error)")
            instrumentAudioURL = nil
            currentInstrumentFile = nil
            instrumentLoopMetadata = nil
        }
    }
    
    private func calculateBeatsFromMetadata(_ metadata: [String: Any]?, defaultBeats: Int) -> Int {
        guard let metadata = metadata else { return defaultBeats }
        
        // Try bars first
        if let bars = metadata["bars"] as? Int {
            return bars * 4  // Assume 4/4 time
        }
        
        // Try calculating from BPM and duration
        if let duration = metadata["loopDuration"] as? TimeInterval,
           let bpm = metadata["bpm"] as? Int {
            let beats = duration * Double(bpm) / 60.0
            return Int(round(beats))
        }
        
        return defaultBeats
    }
    
    private func loadDrumImmediately(audioFile: AVAudioFile, url: URL, metadata: [String: Any]?, beats: Int) {
        currentDrumFile = audioFile
        drumAudioURL = url
        drumLoopMetadata = metadata
        drumLoopBeats = beats
        isDrumCurrentNodeActive = true
        
        print("✅ Drum loaded: \(beats) beats, \(url.lastPathComponent)")
    }
    
    private func loadInstrumentImmediately(audioFile: AVAudioFile,
                                           url: URL,
                                           metadata: [String: Any]?,
                                           beats: Int) {
        // Update instrument state
        currentInstrumentFile   = audioFile
        instrumentAudioURL      = url
        instrumentLoopMetadata  = metadata
        instrumentLoopBeats     = beats
        isInstrumentCurrentNodeActive = true

        print("✅ Instrument loaded: \(beats) beats, \(url.lastPathComponent)")

        // If drums (or the transport) are already running, schedule the instrument to join in sync.
        if isPlaying {
            // Prefer the next bar boundary for this instrument; if unavailable, start slightly in the future.
            let startHT: UInt64? = {
                if let boundary = hostTimeForNextLoopBoundary(loopBeats: instrumentLoopBeats)?.hostTime {
                    return boundary
                }
                return hostTimeForSecondsFromNow(scheduleSafetyLeadSeconds)
            }()

            guard let startHostTime = startHT else {
                print("❌ Could not compute host time to start instrument; skipping auto-start.")
                return
            }

            startInstrumentPlayback(atHostTime: startHostTime)
        }
    }
    
    // MARK: - BUFFER PREPARATION (NEW)
    
    private struct PreparedBuffer {
        let node: AVAudioPlayerNode
        let buffer: AVAudioPCMBuffer
    }
    
    private func prepareDrumBuffer() -> PreparedBuffer? {
        guard let audioFile = currentDrumFile else { return nil }
        
        let activeNode = isDrumCurrentNodeActive ? currentPlayerNode : nextPlayerNode
        
        let bufferSize = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: bufferSize) else {
            print("❌ Failed to create drum buffer")
            return nil
        }
        
        do {
            audioFile.framePosition = 0
            try audioFile.read(into: buffer)
            return PreparedBuffer(node: activeNode, buffer: buffer)
        } catch {
            print("❌ Failed to prepare drum buffer: \(error)")
            return nil
        }
    }
    
    private func prepareInstrumentBuffer() -> PreparedBuffer? {
        guard let audioFile = currentInstrumentFile else { return nil }
        
        let activeNode = isInstrumentCurrentNodeActive ? instrumentPlayerNode : nextInstrumentPlayerNode
        
        let bufferSize = AVAudioFrameCount(audioFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: bufferSize) else {
            print("❌ Failed to create instrument buffer")
            return nil
        }
        
        do {
            audioFile.framePosition = 0
            try audioFile.read(into: buffer)
            return PreparedBuffer(node: activeNode, buffer: buffer)
        } catch {
            print("❌ Failed to prepare instrument buffer: \(error)")
            return nil
        }
    }
    
    // MARK: - SYNCHRONIZED PLAYBACK (NEW)
    
    private var didPrimeEngine = false
    private let coldStartLeadSeconds: Double = 0.180
    
    // Helper: map an absolute hostTime to a node's future sampleTime
    private func playerStartTime(for node: AVAudioPlayerNode, boundaryHT: UInt64) -> AVAudioTime? {
        guard let nodeRT = node.lastRenderTime,
              let pt = node.playerTime(forNodeTime: nodeRT) else { return nil }
        let nodeNowSec = AVAudioTime.seconds(forHostTime: nodeRT.hostTime)
        let boundarySec = AVAudioTime.seconds(forHostTime: boundaryHT)
        let deltaSec = max(0.0, boundarySec - nodeNowSec)
        let deltaFrames = AVAudioFramePosition((deltaSec * outputSampleRate).rounded())
        let targetSampleTime = pt.sampleTime + deltaFrames
        return AVAudioTime(sampleTime: targetSampleTime, atRate: outputSampleRate)
    }

    // Tiny silent buffer to "tickle" converters
    private func makeSilentBuffer(format: AVAudioFormat, durationMs: Double = 12.0) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(max(1, Int((format.sampleRate * durationMs / 1000.0).rounded())))
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buf.frameLength = frames
        return buf
    }

    private func startBothPlaybacksSynchronized(atHostTime startHT: UInt64) {
        // Prep full-loop buffers
        guard let drumPrep = prepareDrumBuffer(),
              let instPrep = prepareInstrumentBuffer() else { return }

        // De-click the first frame (cheap & effective)
        applyMicroFadeIn(drumPrep.buffer, milliseconds: 4.0)
        applyMicroFadeIn(instPrep.buffer,  milliseconds: 4.0)

        if !didPrimeEngine {
            // PRIME: put nodes into "playing" state now and schedule at future sampleTimes
            let outFmt = audioEngine.outputNode.outputFormat(forBus: 0)
            let silent = makeSilentBuffer(format: outFmt)

            // Ensure both *active* nodes are running (silently)
            [drumPrep.node, instPrep.node].forEach { node in
                node.stop()
                node.volume = 0.0
                node.play()                // start node timeline now
                if let s = silent { node.scheduleBuffer(s, at: nil, options: [], completionHandler: nil) } // converter warm-up
            }

            // Translate the shared boundary hostTime → per-node sampleTime and arm the loops
            if let dWhen = playerStartTime(for: drumPrep.node, boundaryHT: startHT),
               let iWhen = playerStartTime(for: instPrep.node, boundaryHT: startHT) {

                drumPrep.node.scheduleBuffer(drumPrep.buffer, at: dWhen, options: [.loops, .interrupts], completionHandler: nil)
                instPrep.node.scheduleBuffer(instPrep.buffer, at: iWhen, options: [.loops, .interrupts], completionHandler: nil)

                // Fade up exactly at the downbeat
                runAtHostTime(startHT) {
                    drumPrep.node.volume = 1.0
                    instPrep.node.volume = 1.0
                }
            } else {
                // Fallback: original hostTime start if mapping failed
                scheduleLoop(node: drumPrep.node, buffer: drumPrep.buffer, startHostTime: startHT, loop: true, initialVolume: 1.0)
                scheduleLoop(node: instPrep.node, buffer: instPrep.buffer, startHostTime: startHT, loop: true, initialVolume: 1.0)
            }
        } else {
            // Warm path: your original precise hostTime start
            scheduleLoop(node: drumPrep.node, buffer: drumPrep.buffer, startHostTime: startHT, loop: true, initialVolume: 1.0)
            scheduleLoop(node: instPrep.node, buffer: instPrep.buffer, startHostTime: startHT, loop: true, initialVolume: 1.0)
        }

        print("🎵 Scheduled synchronized start at hostTime \(startHT)  (drums \(drumLoopBeats) beats, inst \(instrumentLoopBeats) beats)")
    }

    
    private func executeBothSwitchesSynchronized(drum: PendingLoopSwitch, instrument: PendingLoopSwitch) {
        let actualBeat = getCurrentBeat()
        print("🔄 Both-switch (hard cut) requested at beat \(String(format: "%.3f", actualBeat))")

        // 1) Pick the loop boundary hostTime we’re going to hit (never mid-loop)
        guard let nowHT = engineNowHostTime() else { return }

        // Prefer their queued target beat if still ahead; otherwise roll to next common boundary (LCM)
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }
        func lcm(_ a: Int, _ b: Int) -> Int { (a / gcd(a, b)) * b }

        let queuedBeat = (drum.targetBeat == instrument.targetBeat)
            ? drum.targetBeat
            : max(drum.targetBeat, instrument.targetBeat)

        var boundaryHT: UInt64? = hostTimeForBeat(Double(queuedBeat))
        if let ht = boundaryHT, ht <= nowHT {
            let dBeats = max(1, drumLoopBeats)
            let iBeats = max(1, instrumentLoopBeats)
            let common = lcm(dBeats, iBeats)
            let curInt = Int(floor(actualBeat))
            let nextCommonBeat = ((curInt / common) + 1) * common
            boundaryHT = hostTimeForBeat(Double(nextCommonBeat))
        }

        let boundary = boundaryHT ?? hostTimeForSecondsFromNow(0.010) ?? nowHT
        let boundarySec = AVAudioTime.seconds(forHostTime: boundary)

        // 2) Active nodes for each stream (we’ll replace on the same node using .interrupts)
        let drumNode = isDrumCurrentNodeActive ? currentPlayerNode : nextPlayerNode
        let instNode = isInstrumentCurrentNodeActive ? instrumentPlayerNode : nextInstrumentPlayerNode

        // 3) Prepare new buffers (and add a micro fade-in to avoid clicks on the hard cut)
        let drumBuf: AVAudioPCMBuffer = {
            if let pre = drum.preparedBuffer { return pre }
            let frames = AVAudioFrameCount(drum.audioFile.length)
            let buf = AVAudioPCMBuffer(pcmFormat: drum.audioFile.processingFormat, frameCapacity: frames)!
            drum.audioFile.framePosition = 0
            try? drum.audioFile.read(into: buf)
            return buf
        }()
        let instBuf: AVAudioPCMBuffer = {
            if let pre = instrument.preparedBuffer { return pre }
            let frames = AVAudioFrameCount(instrument.audioFile.length)
            let buf = AVAudioPCMBuffer(pcmFormat: instrument.audioFile.processingFormat, frameCapacity: frames)!
            instrument.audioFile.framePosition = 0
            try? instrument.audioFile.read(into: buf)
            return buf
        }()

        applyMicroFadeIn(drumBuf, milliseconds: 4.0)
        applyMicroFadeIn(instBuf,  milliseconds: 4.0)

        // 4) Helper: convert the chosen hostTime boundary → player-node timeline sampleTime
        func playerStartTime(for node: AVAudioPlayerNode, boundaryHT: UInt64) -> AVAudioTime? {
            guard let nodeRT = node.lastRenderTime,
                  let pt = node.playerTime(forNodeTime: nodeRT) else { return nil }

            // Seconds until the boundary from the node’s render timestamp
            let nodeNowSec = AVAudioTime.seconds(forHostTime: nodeRT.hostTime)
            let deltaSec   = max(0.0, boundarySec - nodeNowSec)
            let deltaFrames = AVAudioFramePosition((deltaSec * outputSampleRate).rounded())

            let targetSampleTime = pt.sampleTime + deltaFrames
            return AVAudioTime(sampleTime: targetSampleTime, atRate: outputSampleRate)
        }

        guard let drumStart = playerStartTime(for: drumNode, boundaryHT: boundary),
              let instStart = playerStartTime(for: instNode, boundaryHT: boundary) else {
            print("❌ Could not map boundary to player timelines")
            return
        }

        // 5) Arm replacements on the SAME nodes with .interrupts at the exact boundary
        //    This guarantees a sample-accurate hard cut (no overlap, no main-thread stop()).
        drumNode.volume = 1.0
        drumNode.scheduleBuffer(drumBuf, at: drumStart, options: [.loops, .interrupts], completionHandler: nil)

        instNode.volume = 1.0
        instNode.scheduleBuffer(instBuf, at: instStart, options: [.loops, .interrupts], completionHandler: nil)

        // 6) Flip active flags (we’re continuing on the same nodes, but keep bookkeeping consistent)
        //    After an .interrupts replacement, the "active" node stays the same.
        //    So we DO NOT toggle the active flags here.
        // (Intentionally left as-is; remove any previous toggles for the both-switch path.)

        // 7) Defer state/UI to the exact audible switch
        runAtHostTime(boundary) {
            // Drums
            self.currentDrumFile  = drum.audioFile
            self.drumAudioURL     = drum.url
            self.drumLoopMetadata = drum.metadata
            self.drumLoopBeats    = self.calculateBeatsFromMetadata(drum.metadata, defaultBeats: 16)
            NotificationCenter.default.post(
                name: .drumLoopSwitched,
                object: nil,
                userInfo: [
                    "newAudioURL": drum.url,
                    "switchBeat": actualBeat,
                    "targetBeat": queuedBeat
                ]
            )

            // Instrument
            self.currentInstrumentFile  = instrument.audioFile
            self.instrumentAudioURL     = instrument.url
            self.instrumentLoopMetadata = instrument.metadata
            self.instrumentLoopBeats    = self.calculateBeatsFromMetadata(instrument.metadata, defaultBeats: 16)
            NotificationCenter.default.post(
                name: .instrumentLoopSwitched,
                object: nil,
                userInfo: [
                    "newAudioURL": instrument.url,
                    "switchBeat": actualBeat,
                    "targetBeat": queuedBeat
                ]
            )

            self.drumNextLoopQueued = false
            self.instrumentNextLoopQueued = false
        }

        print("✅ Both-switch scheduled (hard cut, .interrupts) @ hostTime \(boundary)")
    }




    
    // MARK: - SWITCH EXECUTION (BEAT-PERFECT)
    
    private func executeDrumSwitch(_ pending: PendingLoopSwitch) {
        let actualBeat = getCurrentBeat()
        print("🔄 Drum switch requested at beat \(String(format: "%.3f", actualBeat)) (target beat: \(pending.targetBeat))")

        // Pick the exact loop boundary on the engine clock, just like instrument
        guard let nowHT = engineNowHostTime() else { return }
        let boundary: UInt64 = {
            if let ht = hostTimeForBeat(Double(pending.targetBeat)), ht > nowHT {
                return ht
            }
            if let next = hostTimeForNextLoopBoundary(loopBeats: drumLoopBeats)?.hostTime {
                return next
            }
            return hostTimeForSecondsFromNow(scheduleSafetyLeadSeconds) ?? nowHT
        }()

        // Old/new nodes flip exactly like instrument switching
        let oldNode = isDrumCurrentNodeActive ? currentPlayerNode : nextPlayerNode
        let newNode = isDrumCurrentNodeActive ? nextPlayerNode : currentPlayerNode

        do {
            // Prepare the full-loop buffer
            let frames = AVAudioFrameCount(pending.audioFile.length)
            guard let buf = AVAudioPCMBuffer(pcmFormat: pending.audioFile.processingFormat,
                                             frameCapacity: frames) else {
                print("❌ Failed to create drum buffer")
                return
            }
            pending.audioFile.framePosition = 0
            try pending.audioFile.read(into: buf)

            // Seam policy: drums aren’t Magenta → hard cut by default (with micro fade-in)
            let doCrossfade = shouldCrossfade(pending.metadata) // will be false for standard drum loops
            if !doCrossfade {
                applyMicroFadeIn(buf, milliseconds: 4.0) // de-click the first frame
            }

            // Schedule exactly at the boundary; volume depends on seam style
            let startVolume: Float = doCrossfade ? 0.0 : 1.0
            scheduleLoop(node: newNode,
                         buffer: buf,
                         startHostTime: boundary,
                         loop: true,
                         initialVolume: startVolume)

            if doCrossfade {
                // Equal-power crossfade centered on the boundary
                crossfadeAtHostTime(boundary, from: oldNode, to: newNode, durationMs: drumCrossfadeMs)
                // Stop the old node right after fade completes
                let stopHT = boundary &+ AVAudioTime.hostTime(forSeconds: drumCrossfadeMs / 1000.0)
                runAtHostTime(stopHT) { oldNode.stop() }
            } else {
                // Hard cut: swap nodes at the boundary, no overlap
                runAtHostTime(boundary) {
                    oldNode.stop()
                    newNode.volume = 1.0 // ensure full level on the downbeat
                }
            }

            // Flip active node immediately after we’ve scheduled the new one
            isDrumCurrentNodeActive.toggle()

            // Defer state/UI + notification to the actual audible switch time
            let boundarySec = AVAudioTime.seconds(forHostTime: boundary)
            runAtHostTime(boundary) {
                self.currentDrumFile  = pending.audioFile
                self.drumAudioURL     = pending.url
                self.drumLoopMetadata = pending.metadata
                self.drumLoopBeats    = self.calculateBeatsFromMetadata(pending.metadata, defaultBeats: 16)
                self.drumNextLoopQueued = false

                NotificationCenter.default.post(
                    name: .drumLoopSwitched,
                    object: nil,
                    userInfo: [
                        "newAudioURL": pending.url,
                        "switchBeat": actualBeat,
                        "targetBeat": pending.targetBeat,
                        "switchTime": boundarySec
                    ]
                )
            }

            print("✅ Drum switch scheduled @ hostTime \(boundary) (seam: \(doCrossfade ? "crossfade" : "hard cut"))")
        } catch {
            print("❌ Drum switch failed: \(error)")
        }
    }


    
    private func executeInstrumentSwitch(_ pending: PendingLoopSwitch) {
        let actualBeat = getCurrentBeat()
        print("🔄 Instrument switch requested at beat \(String(format: "%.3f", actualBeat)) (target beat: \(pending.targetBeat))")

        // Determine the exact hostTime for the loop boundary we intend to hit.
        guard let nowHT = engineNowHostTime() else { return }
        let boundary: UInt64 = {
            // Prefer the queued target beat (start of the next instrument loop)
            if let ht = hostTimeForBeat(Double(pending.targetBeat)), ht > nowHT {
                return ht
            }
            // If somehow in the past, roll to the NEXT full loop boundary (never mid-loop)
            if let next = hostTimeForNextLoopBoundary(loopBeats: instrumentLoopBeats)?.hostTime {
                return next
            }
            // Last-resort: small safety lead from now
            return hostTimeForSecondsFromNow(scheduleSafetyLeadSeconds) ?? nowHT
        }()

        // Resolve nodes BEFORE we flip the active flag.
        let oldNode = isInstrumentCurrentNodeActive ? instrumentPlayerNode : nextInstrumentPlayerNode
        let newNode = isInstrumentCurrentNodeActive ? nextInstrumentPlayerNode : instrumentPlayerNode

        do {
            // Build the new buffer (entire loop). If you added "preparedBuffer" to PendingLoopSwitch,
            // feel free to use it here instead of re-reading.
            let frameCount = AVAudioFrameCount(pending.audioFile.length)
            guard let buf = AVAudioPCMBuffer(pcmFormat: pending.audioFile.processingFormat,
                                             frameCapacity: frameCount) else {
                print("❌ Failed to create instrument buffer")
                return
            }
            pending.audioFile.framePosition = 0
            try pending.audioFile.read(into: buf)

            // Decide seam style: crossfade for Magenta continuations; else hard cut with micro fade-in.
            let doCrossfade = shouldCrossfade(pending.metadata)
            if !doCrossfade {
                applyMicroFadeIn(buf, milliseconds: 4.0) // prevent clicks on hard cut
            }

            // Schedule at the exact loop boundary on the engine clock.
            let startVolume: Float = doCrossfade ? 0.0 : 1.0
            scheduleLoop(node: newNode,
                         buffer: buf,
                         startHostTime: boundary,
                         loop: true,
                         initialVolume: startVolume)

            if doCrossfade {
                // Equal-power crossfade centered on the boundary.
                crossfadeAtHostTime(boundary, from: oldNode, to: newNode, durationMs: instrumentCrossfadeMs)

                // Stop old node right after the fade to keep CPU tidy.
                let stopHT = boundary &+ AVAudioTime.hostTime(forSeconds: instrumentCrossfadeMs / 1000.0)
                runAtHostTime(stopHT) { oldNode.stop() }
            } else {
                // HARD CUT: no overlap at boundary; ensure new node at full level on the downbeat.
                runAtHostTime(boundary) {
                    oldNode.stop()
                    newNode.volume = 1.0
                }
            }

            // Flip which node is "active" for subsequent scheduling decisions.
            isInstrumentCurrentNodeActive.toggle()

            // Defer state/UI updates until the audible switch moment so visuals match audio exactly.
            let boundarySec = AVAudioTime.seconds(forHostTime: boundary)
            runAtHostTime(boundary) {
                self.currentInstrumentFile  = pending.audioFile
                self.instrumentAudioURL     = pending.url
                self.instrumentLoopMetadata = pending.metadata
                self.instrumentLoopBeats    = self.calculateBeatsFromMetadata(pending.metadata, defaultBeats: 16)

                // Mark queue consumed at the actual switch.
                self.instrumentNextLoopQueued = false

                NotificationCenter.default.post(
                    name: .instrumentLoopSwitched,
                    object: nil,
                    userInfo: [
                        "newAudioURL": pending.url,
                        "switchBeat": actualBeat,           // for reference/logging
                        "targetBeat": pending.targetBeat    // the boundary we hit
                    ]
                )

                // If this was a Magenta jam chunk, notify its true audible start.
                if let chunkIndex = pending.metadata?["jam_chunk_index"] as? Int {
                    NotificationCenter.default.post(
                        name: .jamChunkStartedPlaying,
                        object: nil,
                        userInfo: [
                            "chunkIndex": chunkIndex,
                            "switchTime": boundarySec,
                            "audioURL": pending.url,
                            "isMagentaChunk": true
                        ]
                    )
                }
            }

            print("✅ Instrument switch scheduled @ hostTime \(boundary) (seam: \(doCrossfade ? "crossfade" : "hard cut"))")
        } catch {
            print("❌ Failed to prepare instrument buffer: \(error)")
        }
    }





    private func crossfadeNodes(from oldNode: AVAudioPlayerNode,
                                to newNode: AVAudioPlayerNode,
                                durationMs: Double) {
        // Equal-power crossfade via tiny timer steps
        let steps = 20
        let total = max(5.0, durationMs) / 1000.0
        let dt = total / Double(steps)

        var i = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: dt)

        timer.setEventHandler { [weak oldNode, weak newNode] in
            guard let oldNode = oldNode, let newNode = newNode else {
                timer.cancel(); return
            }
            i += 1
            let x = min(1.0, Double(i) / Double(steps))
            // equal-power curves
            let fadeIn  = Float(sin(0.5 * .pi * x))
            let fadeOut = Float(cos(0.5 * .pi * x))
            newNode.volume = fadeIn
            oldNode.volume = fadeOut

            if i >= steps {
                timer.cancel()
                // Ensure final levels
                newNode.volume = 1.0
                oldNode.volume = 0.0
                oldNode.stop()
                oldNode.volume = 1.0
            }
        }
        timer.resume()
    }
    
    private func shouldCrossfade(_ metadata: [String: Any]?) -> Bool {
        // Treat Magenta chunks (continuations) as crossfade-friendly
        if let meta = metadata {
            if meta["jam_chunk_index"] != nil { return true }
            if (meta["isMagentaChunk"] as? Bool) == true { return true }
        }
        return false
    }
    
    private func applyMicroFadeIn(_ buf: AVAudioPCMBuffer, milliseconds: Double = 4.0) {
        guard let ch = buf.floatChannelData else { return }
        let sr = buf.format.sampleRate
        let fadeFrames = min(buf.frameLength, AVAudioFrameCount(max(1, Int(sr * milliseconds / 1000.0))))
        guard fadeFrames > 1 else { return }

        let n = Int(fadeFrames)
        // Cosine (Hann) half-window: smooth & click-free
        for c in 0..<Int(buf.format.channelCount) {
            let samples = ch[c]
            for i in 0..<n {
                let w = 0.5 * (1 - cos(Double(i) * .pi / Double(n))) // 0→1
                samples[i] *= Float(w)
            }
        }
    }
    
    // MARK: - PLAYBACK CONTROL (UPDATED)
    
    func startLooping() {
        guard currentDrumFile != nil || currentInstrumentFile != nil else { print("⚠️ No audio file loaded"); return }
        if isPlaying { return }
        isPlaying = true

        let lead = didPrimeEngine ? scheduleSafetyLeadSeconds : coldStartLeadSeconds
        let proposedStart = hostTimeForSecondsFromNow(lead)
        guard let startHT = proposedStart else {
            print("❌ Could not obtain engine host time; aborting start.")
            isPlaying = false
            return
        }
        masterStartHostTime = startHT
        print("🎯 Master timing (engine clock) set to hostTime \(startHT)")

        if currentDrumFile != nil && currentInstrumentFile != nil {
            startBothPlaybacksSynchronized(atHostTime: startHT)
        } else if currentDrumFile != nil {
            startDrumPlayback(atHostTime: startHT)
        } else if currentInstrumentFile != nil {
            startInstrumentPlayback(atHostTime: startHT)
        }

        // mark engine as primed right at the audible start
        runAtHostTime(startHT) { self.didPrimeEngine = true }

        startMasterBeatTimer()
        print("▶️ Started beat-synchronized playback (engine clock)")
    }
    
    private func startDrumPlayback(atHostTime startHT: UInt64) {
        guard let drumPrep = prepareDrumBuffer() else { return }
        scheduleLoop(node: drumPrep.node, buffer: drumPrep.buffer, startHostTime: startHT, loop: true, initialVolume: 1.0)
        print("🥁 Scheduled drum start at hostTime \(startHT) (\(drumLoopBeats) beats)")
    }
    
    private func startInstrumentPlayback(atHostTime startHT: UInt64) {
        guard let instrumentPrep = prepareInstrumentBuffer() else { return }
        scheduleLoop(node: instrumentPrep.node, buffer: instrumentPrep.buffer, startHostTime: startHT, loop: true, initialVolume: 1.0)
        print("🎹 Scheduled instrument start at hostTime \(startHT) (\(instrumentLoopBeats) beats)")
    }
    
    func stopAll() {
        currentPlayerNode.stop()
        nextPlayerNode.stop()
        instrumentPlayerNode.stop()
        nextInstrumentPlayerNode.stop()
        stutterPlayerNode.stop()
        
        isPlaying = false
        masterBeatTimer?.invalidate()
        lfoTimer?.invalidate()
        lfoStartTime = nil
        masterStartTime = nil
        
        // Clear pending switches
        pendingDrumSwitch = nil
        pendingInstrumentSwitch = nil
        drumNextLoopQueued = false
        instrumentNextLoopQueued = false
        
        print("⏹️ Stopped all beat-synchronized playback")
    }
    
    func updateBPM(_ newBPM: Int) {
        currentBPM = newBPM
        print("🎵 BPM updated to \(newBPM)")
    }
    
    // MARK: - PROGRESS TRACKING (BEAT-BASED)
    
    private func updateBeatBasedProgress(currentBeat: Double) {
        guard let drumURL = drumAudioURL else { return }
        
        // Calculate position within current drum loop
        let drumBeatPosition = currentBeat.truncatingRemainder(dividingBy: Double(drumLoopBeats))
        let drumTimePosition = drumBeatPosition * secondsPerBeat
        let drumLoopDuration = Double(drumLoopBeats) * secondsPerBeat
        
        // Post drum progress
        NotificationCenter.default.post(
            name: .waveformProgressUpdate,
            object: nil,
            userInfo: [
                "id": "drums",
                "currentTime": drumTimePosition,
                "duration": drumLoopDuration,
                "audioURL": drumURL,
                "currentBeat": drumBeatPosition
            ]
        )
        
        // Post instrument progress if loaded
        if let instrumentURL = instrumentAudioURL {
            let instrumentBeatPosition = currentBeat.truncatingRemainder(dividingBy: Double(instrumentLoopBeats))
            let instrumentTimePosition = instrumentBeatPosition * secondsPerBeat
            let instrumentLoopDuration = Double(instrumentLoopBeats) * secondsPerBeat
            
            NotificationCenter.default.post(
                name: .waveformProgressUpdate,
                object: nil,
                userInfo: [
                    "id": "instruments",
                    "currentTime": instrumentTimePosition,
                    "duration": instrumentLoopDuration,
                    "audioURL": instrumentURL,
                    "currentBeat": instrumentBeatPosition
                ]
            )
        }
    }
    
    // MARK: - COMPUTED PROPERTIES (SIMPLIFIED)
    
    var drumBars: Int {
        return drumLoopBeats / 4
    }
    
    var instrumentBars: Int {
        return instrumentLoopBeats / 4
    }
    
    var currentDrumLoopDuration: TimeInterval {
        return Double(drumLoopBeats) * secondsPerBeat
    }
    
    var currentInstrumentLoopDuration: TimeInterval {
        return Double(instrumentLoopBeats) * secondsPerBeat
    }
    
    var drumSecondsPerBar: TimeInterval {
        return 4.0 * secondsPerBeat  // 4 beats per bar
    }
    
    var instrumentSecondsPerBar: TimeInterval {
        return 4.0 * secondsPerBeat  // 4 beats per bar
    }
    
    // MARK: - EFFECT CONTROLS (unchanged)
    
    func setFilterFrequency(_ frequency: Float) {
        let clampedFreq = max(20.0, min(20000.0, frequency))
        filterFrequency = clampedFreq
        filterNode.bands[0].frequency = clampedFreq
        filterNode.bands[0].bypass = (clampedFreq >= 19000.0)
    }
    
    func setReverbAmount(_ amount: Float) {
        let clampedAmount = max(0.0, min(100.0, amount))
        reverbAmount = clampedAmount
        
        let wetDryMix = (clampedAmount / 100.0) * 100.0
        reverbNode.wetDryMix = wetDryMix
    }
    
    func setInstrumentFilterFrequency(_ frequency: Float) {
        let clampedFreq = max(20.0, min(20000.0, frequency))
        instrumentFilterFrequency = clampedFreq

        if instrumentLFOEnabled {
            // LFO owns the EQ; we only update the target and keep EQ engaged.
            lfoMaxCutoffTarget = clampedFreq
            instrumentFilterNode.bands[0].bypass = false
        } else {
            // No LFO: write the EQ directly, keep your original bypass rule.
            instrumentFilterNode.bands[0].frequency = clampedFreq
            instrumentFilterNode.bands[0].bypass = (clampedFreq >= 19000.0)
        }
    }
    
    func setInstrumentReverbAmount(_ amount: Float) {
        let clampedAmount = max(0.0, min(100.0, amount))
        instrumentReverbAmount = clampedAmount
        
        let wetDryMix = (clampedAmount / 100.0) * 80.0
        instrumentReverbNode.wetDryMix = wetDryMix
    }
    
    // MARK: - LFO (engine-clock, beat-synced)
    
    // Dance-wah shape (fractions of a cycle)
    private var wahClosedUntilFrac: Double = 0.50  // stay closed for first half-beat
    private var wahAttackFrac:     Double = 0.12  // quick rise after halfway
    private var wahReleaseFrac:    Double = 0.06  // quick fall before next downbeat

    // How many beats to offset the LFO phase (0.5 = half-beat "dance wah")
    private var instrumentLFOPhaseOffsetBeats: Double = 0

    // Optional: flip the direction of the sweep
    private var instrumentLFOInvert: Bool = true

    private var lfoBaseHostTime: UInt64?

    // One cycle per how many beats (1.0 = once each beat, 2.0 = once every 2 beats, 0.5 = twice per beat)
    private var instrumentLFOBeatsPerCycle: Double = 1.0

    // Timer update rate (engine-clock phase math makes this robust; 60–75Hz feels smooth)
    private let lfoUpdateInterval: TimeInterval = 1.0 / 60.0
    
    // LFO de-zipper for UI knob (remove zippering while dragging)
    private var lfoMaxCutoffTarget: Float   = 20000.0
    private var lfoMaxCutoffSmoothed: Float = 20000.0
    private var lfoParamSmoothTauSec: Double = 0.030  // ~30 ms time constant
    
    @inline(__always)
    private func smoothstep01(_ x: Double) -> Double {
        let t = max(0.0, min(1.0, x))
        return t * t * (3.0 - 2.0 * t)
    }

    // Asymmetric rounded-square: closed → quick rise → hold high → quick fall → closed
    private func danceWahShape(phase p: Double,
                               closedUntil a0: Double,
                               attackFrac aW: Double,
                               releaseFrac rW: Double) -> Float
    {
        // Clamp & derive segment boundaries
        let A0 = max(0.0, min(0.98, a0))
        let A1 = max(A0 + 1e-4, min(0.999, A0 + aW))
        let R1 = 1.0
        let R0 = max(A1, min(R1 - 1e-4, 1.0 - rW))

        let y: Double
        if p < A0 {
            y = 0.0
        } else if p < A1 {
            // Attack: 0 → 1 with smoothstep
            y = smoothstep01((p - A0) / (A1 - A0))
        } else if p < R0 {
            // Hold high
            y = 1.0
        } else {
            // Release: 1 → 0 with smoothstep
            y = 1.0 - smoothstep01((p - R0) / (R1 - R0))
        }
        return Float(y)
    }

    func setInstrumentLFOEnabled(_ enabled: Bool) {
        instrumentLFOEnabled = enabled
        if enabled {
            // Seed smoother so there’s no jump on enable
            lfoMaxCutoffTarget   = instrumentFilterFrequency
            lfoMaxCutoffSmoothed = instrumentFilterNode.bands[0].frequency
            instrumentFilterNode.bands[0].bypass = false
            startInstrumentLFO()
        } else {
            stopInstrumentLFO()  // this already ramps back to base cutoff
            instrumentFilterNode.bands[0].frequency = instrumentFilterFrequency
        }
    }
    
    

    private func startInstrumentLFO() {
        // Begin the LFO at the next downbeat so phase = 0 exactly at the audible start
        guard let (startHT, _) = hostTimeForNextQuantizedBoundary(gridBeats: 1.0) else {
            // Fallback: start immediately
            lfoBaseHostTime = engineNowHostTime()
            instrumentFilterNode.bands[0].frequency = lfoMinFrequency
            startLFOTimer()
            print("🌊 Instrument LFO started (immediate fallback)")
            return
        }

        lfoBaseHostTime = startHT

        runAtHostTime(startHT) { [weak self] in
            guard let self = self, self.instrumentLFOEnabled else { return }

            let periodSec = max(0.001, self.instrumentLFOBeatsPerCycle * self.secondsPerBeat)
            let offsetSec = self.instrumentLFOPhaseOffsetBeats * self.secondsPerBeat
            let phase0 = (offsetSec / periodSec).truncatingRemainder(dividingBy: 1.0)

            var y0 = self.danceWahShape(phase: phase0,
                                        closedUntil: self.wahClosedUntilFrac,
                                        attackFrac:   self.wahAttackFrac,
                                        releaseFrac:  self.wahReleaseFrac)
            if self.instrumentLFOInvert { y0 = 1.0 - y0 }

            let fMin = self.lfoMinFrequency
            let fMax = max(fMin + 1, self.lfoMaxCutoffSmoothed)
            let initFreq = fMin + (fMax - fMin) * y0
            self.instrumentFilterNode.bands[0].frequency = initFreq
        }

        startLFOTimer()
        print("🌊 Instrument LFO armed for next beat (phase-locked)")
    }

    private func startLFOTimer() {
        lfoTimer?.invalidate()
        lfoTimer = Timer.scheduledTimer(withTimeInterval: lfoUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateInstrumentLFOEngineClock()
        }
        // A tiny tolerance helps the system coalesce timers without hurting musical timing
        lfoTimer?.tolerance = lfoUpdateInterval * 0.3
    }

    private func stopInstrumentLFO() {
        lfoTimer?.invalidate()
        lfoTimer = nil

        // Smoothly return to the base cutoff to avoid zipper/clicks
        let current = instrumentFilterNode.bands[0].frequency
        rampFilterCutoff(from: current, to: instrumentFilterFrequency, durationMs: 80, steps: 10)

        lfoBaseHostTime = nil
    }

    // Compute phase from engine host time (no drift). Saw = 0→1 over one cycle, then reset.
    private func updateInstrumentLFOEngineClock() {
        guard instrumentLFOEnabled,
              let baseHT = lfoBaseHostTime,
              let nowHT  = engineNowHostTime() else { return }

        let baseSec = AVAudioTime.seconds(forHostTime: baseHT)
        let nowSec  = AVAudioTime.seconds(forHostTime: nowHT)
        let elapsed = max(0.0, nowSec - baseSec)

        let periodSec = max(0.001, instrumentLFOBeatsPerCycle * secondsPerBeat)
        let offsetSec = instrumentLFOPhaseOffsetBeats * secondsPerBeat

        let phase = ((elapsed + offsetSec) / periodSec).truncatingRemainder(dividingBy: 1.0) // 0..<1

        var y = danceWahShape(phase: phase,
                              closedUntil: wahClosedUntilFrac,
                              attackFrac:   wahAttackFrac,
                              releaseFrac:  wahReleaseFrac)
        if instrumentLFOInvert { y = 1.0 - y }

        let fMin = lfoMinFrequency
        let fMax = instrumentFilterFrequency
        instrumentFilterNode.bands[0].frequency = fMin + (fMax - fMin) * y
    }

    // Small, click-free parameter ramp using engine clock
    private func rampFilterCutoff(from start: Float, to end: Float, durationMs: Double, steps: Int) {
        guard let startHT = engineNowHostTime() else {
            instrumentFilterNode.bands[0].frequency = end
            return
        }
        let durationSec = max(0.0, durationMs / 1000.0)
        for i in 0...max(1, steps) {
            let t = Double(i) / Double(max(1, steps))
            // ease-in-out cubic for smoothness
            let eased = t < 0.5 ? 4*t*t*t : 1 - pow(-2*t + 2, 3)/2
            let freq = start + Float(eased) * (end - start)
            let ht = startHT &+ AVAudioTime.hostTime(forSeconds: t * durationSec)
            runAtHostTime(ht) { [weak self] in
                self?.instrumentFilterNode.bands[0].frequency = freq
            }
        }
    }

    
    // MARK: - STUTTER (updated for beat timing)
    
    // MARK: - Stutter Reverb
    private let stutterReverb = AVAudioUnitReverb()
    private var stutterFXReady = false

    // Reverb bloom settings
    private var stutterReverbMinMix: Float = 16.0     // % when stutter starts
    private var stutterReverbMaxMix: Float = 70.0    // % at full bloom
    private var stutterReverbRiseBeatsToMax: Double = 4.0  // beats to reach max while holding
    private var stutterReverbReleaseBeats: Double = 0.75   // beats to fade back on release

    private var preStutterReverbMix: Float = 0.0  // remember what it was before stutter
    
    private func setupStutterFXChainIfNeeded() {
        guard !stutterFXReady else { return }
        stutterReverb.loadFactoryPreset(.largeHall2)
        stutterReverb.wetDryMix = stutterReverbMinMix
        stutterFXReady = true
    }
    
    @inline(__always)
    private func easeInOutCubic(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        return t < 0.5 ? 4*t*t*t : 1 - pow(-2*t + 2, 3)/2
    }
    
    private var stutterReplaceDrums: Bool = true  // ✅ flam-proof default
    private let stutterAttackGuardMs: Double = 10 // protects first transient

    // Schedule horizon: how many pulses we pre-arm ahead (keeps things jitter-free)
    private let stutterPreSchedulePulses = 64

    // Stutter state
    private var stutterBaseHostTime: UInt64?
    private var stutterGridSeconds: Double { stutterGridBeats * secondsPerBeat }

    
    // Stutter grid (1.0=beat, 0.5=eighth, 0.25=sixteenth)
    private var stutterGridBeats: Double = 0.25

    // Transient search window around the boundary — look back *and* forward
    private var stutterSearchBackwardMs: Double = 50.0   // catch a kick you tapped late
    private var stutterSearchForwardMs:  Double = 50.0   // catch a snare you tapped early
    private var stutterHopMs:            Double = 2.0
    private var stutterFrameMs:          Double = 6.0    // analysis window; 5–8ms works well

    // What kind of hit to prefer when scoring onsets
    private enum TransientPreference { case auto, kick, snare }
    private var stutterPreference: TransientPreference = .auto

    // If the local window is too quiet, scan the whole loop to avoid stuttering silence
    private var stutterQuietWindowDb: Double = -45.0  // threshold to trigger global fallback energy
    
    // Find a strong onset near `anchorSec` and return the slice *start* (seconds) to use.
    // We search a small window (−back…+fwd), compute short-time energy and its delta,
    // and pick the max of 0.7*ΔE + 0.3*E. Wrap-around safe.
    private func findTransientAlignedStartSeconds(audioFile: AVAudioFile,
                                                  anchorSec: Double,
                                                  searchBackwardMs: Double,
                                                  searchForwardMs: Double,
                                                  hopMs: Double,
                                                  frameMs: Double) -> Double {
        let sr = audioFile.processingFormat.sampleRate
        let totalFrames = max(1, AVAudioFramePosition(audioFile.length))
        let fileDurSec = Double(totalFrames) / sr

        let backSec = max(0.0, searchBackwardMs / 1000.0)
        let fwdSec  = max(0.0, searchForwardMs  / 1000.0)
        let hopSec  = max(0.001, hopMs / 1000.0)
        let winSec  = max(0.002, frameMs / 1000.0)

        let startScan = anchorSec - backSec
        let endScan   = anchorSec + fwdSec
        var bestScore = -Double.infinity
        var bestSec   = anchorSec

        // Helper: read a tiny frame at `posSec` (wrap-safe) and compute energy
        func frameEnergy(at posSec: Double) -> Double {
            let frames = AVAudioFrameCount((winSec * sr).rounded(.toNearestOrAwayFromZero))
            guard frames > 1 else { return 0.0 }

            // Normalize posSec into [0, fileDur)
            var pos = posSec
            if pos < 0 { pos = posSec.truncatingRemainder(dividingBy: fileDurSec) + fileDurSec }
            if pos >= fileDurSec { pos = pos.truncatingRemainder(dividingBy: fileDurSec) }

            let startFrame0 = AVAudioFramePosition((pos * sr).rounded(.toNearestOrAwayFromZero))
            let startFrame  = (startFrame0 % totalFrames + totalFrames) % totalFrames

            // Read with wrap if needed
            guard let buf = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frames) else { return 0.0 }
            buf.frameLength = frames

            let firstChunk = AVAudioFrameCount(min(AVAudioFramePosition(frames), totalFrames - startFrame))
            let secondChunk = frames - firstChunk

            do {
                audioFile.framePosition = startFrame
                try audioFile.read(into: buf, frameCount: firstChunk)

                if secondChunk > 0 {
                    audioFile.framePosition = 0
                    guard let tmp = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: secondChunk) else { return 0.0 }
                    tmp.frameLength = secondChunk
                    try audioFile.read(into: tmp, frameCount: secondChunk)
                    if let outCh = buf.floatChannelData, let tmpCh = tmp.floatChannelData {
                        let chs = Int(audioFile.processingFormat.channelCount)
                        let fc  = Int(firstChunk)
                        let sc  = Int(secondChunk)
                        for c in 0..<chs {
                            memcpy(outCh[c] + fc, tmpCh[c], sc * MemoryLayout<Float>.size)
                        }
                    }
                }
            } catch {
                return 0.0
            }

            // Energy over all channels
            guard let ch = buf.floatChannelData else { return 0.0 }
            let N = Int(buf.frameLength)
            let C = Int(audioFile.processingFormat.channelCount)
            var sum: Double = 0.0
            for c in 0..<C {
                let p = ch[c]
                var i = 0
                while i < N {
                    let v = Double(p[i])
                    sum += v * v
                    i += 1
                }
            }
            return sum / Double(N * max(1, C))
        }

        var prevE: Double = 0.0
        var first = true

        var t = startScan
        while t <= endScan + 1e-9 {
            let e = frameEnergy(at: t)
            let d = first ? 0.0 : max(0.0, e - prevE) // only positive delta
            let score = 0.7 * d + 0.3 * e             // onset-ish
            if score > bestScore {
                bestScore = score
                bestSec = t
            }
            prevE = e
            first = false
            t += hopSec
        }

        return bestSec
    }
    
    // Bi-directional transient finder around an anchor beat position.
    // Returns (bestStartSec, rmsAtBest, peakRMSInWindow)
    private func findTransientStartBidirectional(audioFile: AVAudioFile,
                                                 anchorSec: Double,
                                                 backwardMs: Double,
                                                 forwardMs: Double,
                                                 hopMs: Double,
                                                 frameMs: Double,
                                                 preference: TransientPreference)
    -> (Double, Double, Double) {
        let sr = audioFile.processingFormat.sampleRate
        let totalFrames = max(1, AVAudioFramePosition(audioFile.length))
        let fileDurSec = Double(totalFrames) / sr

        let backSec = max(0.0, backwardMs / 1000.0)
        let fwdSec  = max(0.0, forwardMs  / 1000.0)
        let hopSec  = max(0.001, hopMs / 1000.0)
        let winSec  = max(0.002, frameMs / 1000.0)

        let scanStart = anchorSec - backSec
        let scanEnd   = anchorSec + fwdSec

        var bestScore = -Double.infinity
        var bestSec   = anchorSec
        var bestRMS:  Double = 0.0
        var peakRMS:  Double = 0.0

        var prevRMS:  Double = 0.0
        var prevHP:   Double = 0.0
        var prevLP:   Double = 0.0
        var first = true

        var t = scanStart
        while t <= scanEnd + 1e-9 {
            // Energy variants for simple kick/snare bias without FFT:
            // RMS = overall energy
            // HP  = energy of 1st-difference (high-frequency-ish, snare-ish)
            // LP  = energy of moving-average (low-frequency-ish, kick-ish)
            let (rms, hp, lp) = smallFrameEnergies(audioFile: audioFile, centerSec: t, winSec: winSec)

            // Positive deltas (onsets)
            let dR = first ? 0.0 : max(0.0, rms - prevRMS)
            let dH = first ? 0.0 : max(0.0, hp  - prevHP)
            let dL = first ? 0.0 : max(0.0, lp  - prevLP)

            // Preference weights
            let (wE, wHP, wLP, wD) : (Double, Double, Double, Double) = {
                switch preference {
                case .snare: return (0.25, 0.55, 0.10, 0.10) // favor high-freq changes
                case .kick:  return (0.35, 0.10, 0.45, 0.10) // favor low-freq and level
                case .auto:  return (0.30, 0.35, 0.25, 0.10) // blend
                }
            }()

            // Onset score: blend of absolute level + band-biased deltas
            let score = wE * rms + wHP * dH + wLP * dL + wD * dR

            if score > bestScore {
                bestScore = score
                bestSec   = t
                bestRMS   = rms
            }
            peakRMS = max(peakRMS, rms)

            prevRMS = rms; prevHP = hp; prevLP = lp; first = false
            t += hopSec
        }

        // Normalize position into [0, fileDur)
        var norm = bestSec
        if norm < 0 { norm = norm.truncatingRemainder(dividingBy: fileDurSec) + fileDurSec }
        if norm >= fileDurSec { norm = norm.truncatingRemainder(dividingBy: fileDurSec) }

        return (norm, bestRMS, peakRMS)
    }

    // Compute simple per-frame energies around a time (wrap-safe):
    // - RMS: overall amplitude
    // - HP:  high-pass-ish energy via first difference
    // - LP:  low-pass-ish energy via short moving average
    private func smallFrameEnergies(audioFile: AVAudioFile,
                                    centerSec: Double,
                                    winSec: Double)
    -> (Double, Double, Double) {
        let sr = audioFile.processingFormat.sampleRate
        let totalFrames = max(1, AVAudioFramePosition(audioFile.length))
        let frames = max(8, Int((winSec * sr).rounded()))
        let half   = frames / 2

        // Center frame (wrap-safe)
        var centerFrame0 = AVAudioFramePosition((centerSec * sr).rounded())
        if centerFrame0 < 0 { centerFrame0 = (centerFrame0 % totalFrames + totalFrames) % totalFrames }
        if centerFrame0 >= totalFrames { centerFrame0 = centerFrame0 % totalFrames }

        // Read [center - half, center + half)
        let startFrame = (centerFrame0 - AVAudioFramePosition(half) + totalFrames) % totalFrames
        let need = AVAudioFrameCount(frames)

        guard let buf = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: need) else { return (0,0,0) }
        buf.frameLength = need

        let firstChunk = AVAudioFrameCount(min(AVAudioFramePosition(need), totalFrames - startFrame))
        let secondChunk = need - firstChunk

        do {
            audioFile.framePosition = startFrame
            try audioFile.read(into: buf, frameCount: firstChunk)
            if secondChunk > 0 {
                audioFile.framePosition = 0
                guard let tmp = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: secondChunk) else { return (0,0,0) }
                tmp.frameLength = secondChunk
                try audioFile.read(into: tmp, frameCount: secondChunk)
                if let outCh = buf.floatChannelData, let tmpCh = tmp.floatChannelData {
                    let chs = Int(audioFile.processingFormat.channelCount)
                    let fc  = Int(firstChunk)
                    let sc  = Int(secondChunk)
                    for c in 0..<chs {
                        memcpy(outCh[c] + fc, tmpCh[c], sc * MemoryLayout<Float>.size)
                    }
                }
            }
        } catch { return (0,0,0) }

        guard let ch = buf.floatChannelData else { return (0,0,0) }
        let C = Int(audioFile.processingFormat.channelCount)
        let N = Int(buf.frameLength)

        var sum: Double = 0.0
        var sumHP: Double = 0.0
        var sumLP: Double = 0.0
        let lpWin = max(4, N / 6) // short moving average ~low-pass

        for c in 0..<C {
            let p = ch[c]

            // RMS
            for i in 0..<N {
                let v = Double(p[i])
                sum += v * v
            }

            // High-pass-ish via first difference
            var prev = Double(p[0])
            for i in 1..<N {
                let dv = Double(p[i]) - prev
                sumHP += dv * dv
                prev = Double(p[i])
            }

            // Low-pass-ish via moving average
            var acc: Double = 0.0
            for i in 0..<N {
                acc += Double(p[i])
                if i >= lpWin { acc -= Double(p[i - lpWin]) }
                let mean = acc / Double(min(i + 1, lpWin))
                sumLP += mean * mean
            }
        }

        let rms  = sqrt(sum  / Double(N * max(1, C)))
        let hp   = sqrt(sumHP / Double((N-1) * max(1, C)))
        let lp   = sqrt(sumLP / Double(N * max(1, C)))
        return (rms, hp, lp)
    }

    // Fallback: find loudest RMS spot across the whole loop (avoid silence stutter)
    private func findLoudestInLoop(audioFile: AVAudioFile,
                                   hopMs: Double,
                                   frameMs: Double) -> Double {
        let sr = audioFile.processingFormat.sampleRate
        let totalFrames = max(1, AVAudioFramePosition(audioFile.length))
        let durSec = Double(totalFrames) / sr
        let hopSec = max(0.002, hopMs / 1000.0)

        var bestSec = 0.0
        var bestRMS = -Double.infinity
        var t = 0.0
        while t < durSec {
            let (rms, _, _) = smallFrameEnergies(audioFile: audioFile, centerSec: t, winSec: max(0.003, frameMs / 1000.0))
            if rms > bestRMS { bestRMS = rms; bestSec = t }
            t += hopSec
        }
        return bestSec
    }

    
    func startStutter() {
        guard let audioFile = currentDrumFile, isPlaying else { return }
        
        setupStutterFXChainIfNeeded()

        // 1) Choose the next grid boundary on the engine clock
        guard let (boundaryHT, qBeat) = hostTimeForNextQuantizedBoundary(gridBeats: stutterGridBeats) else { return }
        stutterBaseHostTime = boundaryHT
        // let boundarySec = AVAudioTime.seconds(forHostTime: boundaryHT)

        
        
        // 2) Pick a transient-aligned slice inside the drum loop around that boundary
        let loopBeats = max(1, drumLoopBeats)
        let anchorSec = (qBeat.truncatingRemainder(dividingBy: Double(loopBeats))) * secondsPerBeat

        let (localStartSec, _, localPeakRMS) = findTransientStartBidirectional(
            audioFile: audioFile,
            anchorSec: anchorSec,
            backwardMs: stutterSearchBackwardMs,
            forwardMs:  stutterSearchForwardMs,
            hopMs:      stutterHopMs,
            frameMs:    stutterFrameMs,
            preference: stutterPreference
        )
        let localDb = 20.0 * log10(max(1e-9, localPeakRMS))
        let startSec: Double = (localDb < stutterQuietWindowDb)
            ? findLoudestInLoop(audioFile: audioFile, hopMs: 6.0, frameMs: 10.0)
            : localStartSec
        
        // Remember previous mix and set a low starting point at the audible start
        preStutterReverbMix = stutterReverb.wetDryMix

        let pulsesToMax = max(1, Int(round(stutterReverbRiseBeatsToMax / stutterGridBeats)))
        for n in 0..<stutterPreSchedulePulses {
            let ht = boundaryHT &+ AVAudioTime.hostTime(forSeconds: Double(n) * stutterGridSeconds)
            let prog = min(1.0, Double(n) / Double(pulsesToMax))           // 0→1 over pulsesToMax
            let eased = easeInOutCubic(prog)
            let mix = stutterReverbMinMix + Float(eased) * (stutterReverbMaxMix - stutterReverbMinMix)

            runAtHostTime(ht) { [weak self] in
                guard let self = self, self.isStuttering else { return }
                self.stutterReverb.wetDryMix = mix
            }
        }

        // 3) Build the slice at file rate, then convert to output format (nice but not required now)
        let sliceLenSec = stutterGridSeconds
        guard let sliceFile = extractExactSlice(audioFile: audioFile, startSeconds: startSec, lengthSeconds: sliceLenSec) else { return }

        // Convert to engine output (optional), then micro fade-in to avoid clicks on hard starts
        let outFmt = audioEngine.outputNode.outputFormat(forBus: 0)
        let exactFrames = AVAudioFrameCount((sliceLenSec * outFmt.sampleRate).rounded())
        let sliceOut = convertBufferToOutputFormatExact(sliceFile, inFormat: audioFile.processingFormat, exactFrames: exactFrames) ?? sliceFile
        applyMicroFadeIn(sliceOut, milliseconds: 4.0)

        // 4) Pre-schedule one-shot pulses at exact future host times (NO .loops)
        stutterPlayerNode.stop()
        stutterPlayerNode.volume = 1.0

        // Make sure the node is in "playing" state before the first scheduled buffer
        stutterPlayerNode.play() // playback will engage when first scheduled time arrives

        for n in 0..<stutterPreSchedulePulses {
            let ht = boundaryHT &+ AVAudioTime.hostTime(forSeconds: Double(n) * stutterGridSeconds)
            stutterPlayerNode.scheduleBuffer(sliceOut,
                                             at: AVAudioTime(hostTime: ht),
                                             options: [],                    // one-shot, no self-loop
                                             completionHandler: nil)
        }

        // 5) Replace vs overlay: kill the flam by removing drum overlap in replace mode
        let drumNode = isDrumCurrentNodeActive ? currentPlayerNode : nextPlayerNode
        if stutterReplaceDrums {
            // Silence drums at the exact boundary, then (optionally) keep them muted while stuttering
            let guardHT = boundaryHT &+ AVAudioTime.hostTime(forSeconds: stutterAttackGuardMs / 1000.0)
            runAtHostTime(boundaryHT) { drumNode.volume = 0.0 }
            runAtHostTime(guardHT)     { drumNode.volume = 0.0 } // stay fully replaced (no duck)
        } else {
            // Overlay mode: brief attack guard then duck to 0.2 (may reintroduce a tiny flam)
            let guardHT = boundaryHT &+ AVAudioTime.hostTime(forSeconds: stutterAttackGuardMs / 1000.0)
            runAtHostTime(boundaryHT) { drumNode.volume = 0.0 }
            runAtHostTime(guardHT)    { drumNode.volume = 0.2 }
        }

        isStuttering = true
        print("🔥 Stutter scheduled starting @ beat \(qBeat) (replaceDrums=\(stutterReplaceDrums))")
    }

    func stopStutter() {
        guard isStuttering else { return }

        // Stop on the next grid so the release is on-beat
        guard let (boundaryHT, _) = hostTimeForNextQuantizedBoundary(gridBeats: stutterGridBeats) else {
            stutterPlayerNode.stop()
            let node = isDrumCurrentNodeActive ? currentPlayerNode : nextPlayerNode
            node.volume = 1.0
            isStuttering = false
            print("🔥 Stutter stopped (immediate fallback)")
            return
        }

        // --- Click-free stop ---
        let drumNode = self.isDrumCurrentNodeActive ? self.currentPlayerNode : self.nextPlayerNode

        // ① Pre-fade the stutter a hair BEFORE the boundary so it reaches ~0 exactly at stop
        let preFadeMs = min(12.0, self.stutterGridSeconds * 0.25 * 1000.0) // <= 1/4 of a pulse, capped ~12ms
        let preFadeStart = boundaryHT &- AVAudioTime.hostTime(forSeconds: preFadeMs / 1000.0)
        self.rampVolume(self.stutterPlayerNode, from: self.stutterPlayerNode.volume, to: 0.0,
                        startHT: preFadeStart, durationMs: preFadeMs, steps: 6)


        runAtHostTime(boundaryHT) {
            self.stutterPlayerNode.stop()
            // Restore drums
            drumNode.volume = 1.0
            self.isStuttering = false
            self.stutterBaseHostTime = nil
            print("🔥 Stutter stopped on-grid")
        }
        
        // Reverb release back to the pre-stutter mix over N steps, on the engine clock
        let startMix = self.stutterReverb.wetDryMix
        let durSec = self.stutterReverbReleaseBeats * self.secondsPerBeat
        let steps = max(6, Int(round(durSec / 0.03)))   // ~30ms steps

        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let eased = self.easeInOutCubic(1.0 - frac) // decay
            let mix = self.preStutterReverbMix + Float(eased) * (startMix - self.preStutterReverbMix)
            let ht = boundaryHT &+ AVAudioTime.hostTime(forSeconds: frac * durSec)
            self.runAtHostTime(ht) { self.stutterReverb.wetDryMix = mix }
        }
    }
    
    private func rampVolume(_ node: AVAudioPlayerNode,
                            from startVol: Float,
                            to endVol: Float,
                            startHT: UInt64,
                            durationMs: Double,
                            steps: Int = 8)
    {
        let durSec = max(0.0, durationMs / 1000.0)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // ease-in-out for smoothness
            let eased = t < 0.5 ? 4*t*t*t : 1 - pow(-2*t + 2, 3)/2
            let vol = startVol + Float(eased) * (endVol - startVol)
            let ht = startHT &+ AVAudioTime.hostTime(forSeconds: t * durSec)
            runAtHostTime(ht) { node.volume = vol }
        }
    }
    
    // Convert a buffer from its source format to the engine's output format,
    // returning a buffer with EXACTLY `exactFrames` frames (pads/trims as needed).
    private func convertBufferToOutputFormatExact(
        _ inBuf: AVAudioPCMBuffer,
        inFormat: AVAudioFormat,
        exactFrames: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        let outFmt = audioEngine.outputNode.outputFormat(forBus: 0)

        // If formats already match and length is exact, return as-is
        if inFormat == outFmt, inBuf.frameLength == exactFrames {
            return inBuf
        }

        // If formats match but length differs, copy/pad/trim to exactFrames
        func copyToExact(_ src: AVAudioPCMBuffer, fmt: AVAudioFormat, exact: AVAudioFrameCount) -> AVAudioPCMBuffer? {
            guard let dst = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: exact) else { return nil }
            dst.frameLength = exact
            guard let s = src.floatChannelData, let d = dst.floatChannelData else { return nil }
            let C = Int(fmt.channelCount)
            let copyFrames = min(Int(src.frameLength), Int(exact))
            for c in 0..<C {
                // copy existing frames
                memcpy(d[c], s[c], copyFrames * MemoryLayout<Float>.size)
                // zero-pad remainder if needed
                if copyFrames < Int(exact) {
                    let remain = Int(exact) - copyFrames
                    memset(d[c] + copyFrames, 0, remain * MemoryLayout<Float>.size)
                }
            }
            return dst
        }

        if inFormat == outFmt {
            return copyToExact(inBuf, fmt: outFmt, exact: exactFrames)
        }

        // Formats differ: resample/convert with AVAudioConverter
        guard let converter = AVAudioConverter(from: inFormat, to: outFmt) else { return nil }
        guard let tmpOut = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: exactFrames) else { return nil }

        var inputProvided = false
        var convError: NSError?
        let status = converter.convert(to: tmpOut, error: &convError, withInputFrom: { _, outStatus in
            if inputProvided {
                outStatus.pointee = .endOfStream
                return nil
            }
            inputProvided = true
            outStatus.pointee = .haveData
            return inBuf
        })

        if status == .error {
            if let e = convError { print("❌ AVAudioConverter error: \(e)") }
            return nil
        }

        // Ensure exact frame count by copy/pad/trim
        return copyToExact(tmpOut, fmt: outFmt, exact: exactFrames)
    }

    
    // Exact-length slice with wrap-around so we always get the full requested duration
    private func extractExactSlice(audioFile: AVAudioFile,
                                   startSeconds: TimeInterval,
                                   lengthSeconds: TimeInterval) -> AVAudioPCMBuffer? {
        let sr = audioFile.processingFormat.sampleRate
        let totalFrames = AVAudioFramePosition(audioFile.length)
        let reqFrames = AVAudioFrameCount((lengthSeconds * sr).rounded(.toNearestOrAwayFromZero))

        guard reqFrames > 0 else { return nil }

        let format = audioFile.processingFormat
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: reqFrames) else { return nil }
        out.frameLength = reqFrames

        // Normalize start to [0, fileLength)
        let startFrame0 = AVAudioFramePosition((startSeconds * sr).rounded(.toNearestOrAwayFromZero))
        let startFrame = (startFrame0 % totalFrames + totalFrames) % totalFrames

        let firstChunkFrames = min(AVAudioFrameCount(totalFrames - startFrame), reqFrames)
        let secondChunkFrames = reqFrames - firstChunkFrames

        // Read first chunk
        do {
            audioFile.framePosition = startFrame
            try audioFile.read(into: out, frameCount: firstChunkFrames)
        } catch {
            print("❌ Stutter slice read #1 failed: \(error)")
            return nil
        }

        // If we wrapped, read from start of file to complete the slice
        if secondChunkFrames > 0 {
            do {
                audioFile.framePosition = 0
                // Create a temp buffer to read the remainder, then copy into `out`
                guard let tmp = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: secondChunkFrames) else { return nil }
                tmp.frameLength = secondChunkFrames
                try audioFile.read(into: tmp, frameCount: secondChunkFrames)

                // Copy channel-by-channel
                guard let outCh = out.floatChannelData, let tmpCh = tmp.floatChannelData else { return nil }
                let chCount = Int(format.channelCount)
                let firstCount = Int(firstChunkFrames)
                let secondCount = Int(secondChunkFrames)
                for c in 0..<chCount {
                    memcpy(outCh[c] + firstCount, tmpCh[c], secondCount * MemoryLayout<Float>.size)
                }
            } catch {
                print("❌ Stutter slice read #2 failed: \(error)")
                return nil
            }
        }

        return out
    }
    
    // MARK: - SEEK (beat-aligned)
    
    func seekDrumLoop(to time: TimeInterval) {
        guard currentDrumFile != nil else { return }

        // Convert desired time → beat, align to downbeat (for logging/consistency only).
        let targetBeat  = time * beatsPerSecond
        let alignedBeat = floor(targetBeat)
        let alignedTime = alignedBeat * secondsPerBeat
        let clampedTime = max(0, min(alignedTime, currentDrumLoopDuration))

        if isPlaying {
            // Restart drums exactly on the next loop boundary (engine clock).
            let startHT = hostTimeForNextLoopBoundary(loopBeats: drumLoopBeats)?.hostTime
                ?? hostTimeForSecondsFromNow(scheduleSafetyLeadSeconds)

            if let ht = startHT {
                startDrumPlayback(atHostTime: ht)
                print("🎯 Drum 'seek' requested to beat \(Int(alignedBeat)) (~\(String(format: "%.2f", clampedTime))s) — restarting at next boundary hostTime \(ht).")
            } else {
                print("❌ Could not compute host time for drum 'seek'.")
            }
        } else {
            // Transport stopped: keep behavior the same (no auto-start).
            print("⏸️ Transport stopped; recorded drum 'seek' beat \(Int(alignedBeat)) (~\(String(format: "%.2f", clampedTime))s). Will start aligned when playback begins.")
        }
    }
    
    // MARK: - GENERATION STATE
    
    func setGeneratingNext(_ generating: Bool) {
        DispatchQueue.main.async {
            self.isGeneratingNext = generating
        }
    }
    
    // MARK: - DIAGNOSTICS
    
    func getTimingDiagnostics() -> [String: Any] {
        guard let startTime = masterStartTime, isPlaying else {
            return ["status": "not_playing"]
        }
        
        let currentBeat = getCurrentBeat()
        let drumBeatInLoop = currentBeat.truncatingRemainder(dividingBy: Double(drumLoopBeats))
        let instrumentBeatInLoop = currentBeat.truncatingRemainder(dividingBy: Double(instrumentLoopBeats))
        
        return [
            "status": "playing",
            "current_beat": currentBeat,
            "drum_beat_in_loop": drumBeatInLoop,
            "instrument_beat_in_loop": instrumentBeatInLoop,
            "drum_loop_beats": drumLoopBeats,
            "instrument_loop_beats": instrumentLoopBeats,
            "bpm": currentBPM,
            "seconds_per_beat": secondsPerBeat,
            "master_start_time": startTime.timeIntervalSince1970,
            "beat_precision": "perfect"  // Always perfect with this system
        ]
    }
}
