import Foundation
import AVFoundation

// MARK: - Multipart Form Data Utility
public struct MultipartFormData {
    private let boundary = "----LOOP-AUDIO-\(UUID().uuidString)"
    private var body = Data()

    var contentTypeHeader: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func addFile(url: URL, name: String, filename: String, mimeType: String) {
        guard let fileData = try? Data(contentsOf: url) else { return }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    func encode() -> Data {
        var end = Data()
        end.append("--\(boundary)--\r\n".data(using: .utf8)!)
        var full = body
        full.append(end)
        return full
    }
}

// Notification names - UPDATED with separate switch notifications
extension Notification.Name {
    static let drumLoopGenerated = Notification.Name("drumLoopGenerated")
    static let instrumentLoopGenerated = Notification.Name("instrumentLoopGenerated")
    static let drumLoopSwitched = Notification.Name("drumLoopSwitched")        // NEW - drum specific
    static let instrumentLoopSwitched = Notification.Name("instrumentLoopSwitched")  // NEW - instrument specific
    static let waveformProgressUpdate = Notification.Name("waveformProgressUpdate")
    
    // Keep the old generic one for backward compatibility if needed
    static let loopSwitched = Notification.Name("loopSwitched")
    
    static let bpmChanged = Notification.Name("bpmChanged")
    
    static let magentaJamStartRequested = Notification.Name("magentaJamStartRequested")
    
    static let magentaJamStarted = Notification.Name("magentaJamStarted")
    static let magentaJamStopped = Notification.Name("magentaJamStopped")
    
    static let jamChunkStartedPlaying = Notification.Name("jamChunkStartedPlaying")
}

class LoopAudioManager: ObservableObject {
    @Published var isGenerating = false
    @Published var errorMessage: String?
    @Published var magentaConfig = MagentaConfig()
    
    // API Configuration
    internal var backendURL: String = "https://g4l.thecollabagepatch.com/audio"
    
    // Reference to player manager for generation state coordination
    weak var playerManager: EngineLoopPlayerManager?
    
    @Published var isJamStartRequested: Bool = false
    
    struct PendingJamRequest {
        let bpm: Int
        let barsPerChunk: Int
        let styles: [String]
        let styleWeights: [Double]
        let loopWeight: Double
        let temperature: Double
        let topK: Int
        let guidanceWeight: Double
    }
    @Published var pendingJamRequest: PendingJamRequest? = nil
    
    enum MagentaJamState: Equatable {
        case idle
        case starting
        case running(sessionID: String)   // real session later
        case stopping
        case error(String)

        var isActive: Bool {
            if case .running = self { return true }
            return false
        }
        var isBusy: Bool { self == .starting || self == .stopping }
    }
    
    @Published var jamState: MagentaJamState = .idle
    private let magentaBaseURL = URL(string: "https://thecollabagepatch-magenta-retry.hf.space")!
    
    private var jamSessionID: String?
    private var jamPollTimer: Timer?
    private var jamLastIndex: Int = 0
    
    enum JamUpdateError: LocalizedError {
        case noActiveJam
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .noActiveJam:      return "No active jam session to update."
            case .badStatus(let c): return "Server returned HTTP \(c)."
            }
        }
    }
    
    init() {
            // Listen for when jam chunks actually start playing
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleJamChunkStartedPlaying(_:)),
                name: .jamChunkStartedPlaying,
                object: nil
            )
        }
        
        // 🎯 ADD THIS DEINIT METHOD TOO
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    
    @objc private func handleJamChunkStartedPlaying(_ notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let chunkIndex = userInfo["chunkIndex"] as? Int,
                  let switchTime = userInfo["switchTime"] as? TimeInterval,
                  case .running(let sessionID) = jamState else {
                return
            }
            
            let timingDrift = userInfo["timingDrift"] as? TimeInterval ?? 0.0
            
            print("✅ Jam chunk \(chunkIndex) actually started playing at \(String(format: "%.3f", switchTime))s")
            print("   Timing drift: \(String(format: "%.3f", timingDrift))s")
            print("   Marking consumed now...")
            
            markChunkConsumed(sessionID: sessionID, chunkIndex: chunkIndex)
        }
    
    
    func updateBackendURL(_ newURL: String) {
        self.backendURL = newURL
    }
    
    func connectPlayerManager(_ manager: EngineLoopPlayerManager) {
        self.playerManager = manager
    }
    
    // MARK: - Loop Type Enum
    enum LoopType {
        case drums, instruments
        
        var filePrefix: String {
            switch self {
            case .drums: return "drum_loop_"
            case .instruments: return "instrument_loop_"
            }
        }
        
        var displayName: String {
            switch self {
            case .drums: return "Drum loop"
            case .instruments: return "Instrument loop"
            }
        }
        
        var shortDisplayName: String {
            switch self {
            case .drums: return "Loop"
            case .instruments: return "Instrument"
            }
        }
        
        var notificationName: Notification.Name {
            switch self {
            case .drums: return .drumLoopGenerated
            case .instruments: return .instrumentLoopGenerated
            }
        }
        
        var apiLoopType: String {
            switch self {
            case .drums: return "drums"
            case .instruments: return "instruments"
            }
        }
        
        var generationEmoji: String {
            switch self {
            case .drums: return "🥁"
            case .instruments: return "🎹"
            }
        }
        
        var generationMessage: String {
            switch self {
            case .drums: return "Generating drum loop"
            case .instruments: return "Generating instrument loop"
            }
        }
    }
    
    // MARK: - State Management Helpers
        
        /// Starts generation if not already in progress. Returns false if already generating.
        public func startGeneration() -> Bool {
            guard !isGenerating else {
                print("❌ Loop generation already in progress")
                return false
            }
            
            DispatchQueue.main.async {
                self.errorMessage = nil
                self.isGenerating = true
            }
            
            if playerManager?.isPlaying == true {
                playerManager?.setGeneratingNext(true)
                print("🎵 Queuing generation for next loop (currently playing)")
            }
            
            return true
        }
        
        /// Cleans up generation state
        public func cleanupGeneration() {
            DispatchQueue.main.async {
                self.isGenerating = false
                self.playerManager?.setGeneratingNext(false)
            }
        }
    
    // MARK: basic genration functions
    
    // MARK: - Generic Generation Function
    private func generateLoop(
        prompt: String,
        bpm: Int,
        loopType: LoopType,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        guard startGeneration() else { return }
        
        // Build the prompt with BPM
        let finalPrompt = "\(prompt) \(bpm)bpm"
        
        // Create request
        guard let url = URL(string: "\(backendURL)/generate/loop") else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid backend URL"
            }
            cleanupGeneration()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Use MultipartFormData utility
        var formData = MultipartFormData()
        
        // Add form fields
        formData.addField(name: "prompt", value: finalPrompt)
        formData.addField(name: "loop_type", value: loopType.apiLoopType)
        formData.addField(name: "steps", value: "\(steps)")
        formData.addField(name: "cfg_scale", value: "\(cfgScale)")
        formData.addField(name: "seed", value: "\(seed)")
        formData.addField(name: "return_format", value: "base64")
        
        // Add bars if specified
        if let bars = bars {
            formData.addField(name: "bars", value: "\(bars)")
        }
        
        // Set request headers and body
        request.setValue(formData.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.encode()
        
        print("\(loopType.generationEmoji) \(loopType.generationMessage): '\(finalPrompt)'")
        print("   Steps: \(steps), CFG: \(cfgScale), Seed: \(seed)")
        if let bars = bars {
            print("   Bars: \(bars)")
        } else {
            print("   Bars: auto-calculated")
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.cleanupGeneration()
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Invalid response from server"
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Server error: \(httpResponse.statusCode)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "No data received"
                }
                return
            }
            
            // Parse JSON response
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                guard let audioBase64 = jsonResponse?["audio_base64"] as? String,
                      let metadata = jsonResponse?["metadata"] as? [String: Any] else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Invalid JSON response format"
                    }
                    return
                }
                
                // Decode base64 audio data
                guard let audioData = Data(base64Encoded: audioBase64) else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Failed to decode base64 audio"
                    }
                    return
                }
                
                // Save with appropriate save method
                self?.saveLoop(data: audioData, bpm: bpm, metadata: metadata, loopType: loopType)
                
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                }
            }
            
        }.resume()
    }

    // MARK: - Basic Generation Wrapper Functions (Preserve Existing API)
    func generateDrumLoop(
        prompt: String,
        bpm: Int,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        generateLoop(
            prompt: prompt,
            bpm: bpm,
            loopType: .drums,
            steps: steps,
            cfgScale: cfgScale,
            seed: seed,
            bars: bars
        )
    }

    func generateInstrumentLoop(
        prompt: String,
        bpm: Int,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        generateLoop(
            prompt: prompt,
            bpm: bpm,
            loopType: .instruments,
            steps: steps,
            cfgScale: cfgScale,
            seed: seed,
            bars: bars
        )
    }
    
    
    // MARK: - Generic Save Function
    public func saveLoop(data: Data, bpm: Int, metadata: [String: Any], loopType: LoopType) {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Extract metadata values
        let bars = metadata["bars"] as? Int ?? 1
        let loopDuration = metadata["loop_duration_seconds"] as? Double ?? 0.0
        let secondsPerBar = metadata["seconds_per_bar"] as? Double ?? 0.0
        let actualBPM = metadata["detected_bpm"] as? Int ?? bpm
        let seed = metadata["seed"] as? Int ?? -1
        
        // Create filename with BPM, bars, and timestamp
        let timestamp = Int(Date().timeIntervalSince1970)
        let fileName = "\(loopType.filePrefix)\(actualBPM)bpm_\(bars)bars_\(timestamp).wav"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            // Clean up old loops to save space
            let fileManager = FileManager.default
            let directoryContents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
            
            for file in directoryContents {
                if file.lastPathComponent.hasPrefix(loopType.filePrefix) {
                    try? fileManager.removeItem(at: file)
                }
            }
            
            // Save new loop
            try data.write(to: fileURL)
            print("✅ \(loopType.displayName) saved: \(fileName)")
            
            // Validate the audio file
            guard let audioFile = try? AVAudioFile(forReading: fileURL) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid audio file generated"
                }
                return
            }
            
            let actualDuration = Double(audioFile.length) / audioFile.fileFormat.sampleRate
            print("📊 \(loopType.shortDisplayName): \(bars) bars, \(String(format: "%.2f", loopDuration))s (API) vs \(String(format: "%.2f", actualDuration))s (actual)")
            print("📊 BPM: \(actualBPM), Seed: \(seed)")
            
            // Post notification with rich metadata
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: loopType.notificationName,
                    object: nil,
                    userInfo: [
                        "audioURL": fileURL,
                        "bpm": actualBPM,
                        "bars": bars,
                        "loopDuration": loopDuration,
                        "secondsPerBar": secondsPerBar,
                        "actualDuration": actualDuration,
                        "seed": seed,
                        "metadata": metadata // Include full metadata for future use
                    ]
                )
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to save \(loopType.displayName.lowercased()): \(error.localizedDescription)"
            }
            print("❌ Error saving \(loopType.displayName.lowercased()): \(error)")
        }
    }

    // MARK: - Wrapper Functions (Preserve Existing API)
   public func saveDrumLoop(data: Data, bpm: Int, metadata: [String: Any]) {
        saveLoop(data: data, bpm: bpm, metadata: metadata, loopType: .drums)
    }

    public func saveInstrumentLoop(data: Data, bpm: Int, metadata: [String: Any]) {
        saveLoop(data: data, bpm: bpm, metadata: metadata, loopType: .instruments)
    }
    
    // MARK: - Api Health Check
    
    // Utility method to check if API is available
    func checkAPIHealth(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(backendURL)/health") else {
            completion(false)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }.resume()
    }
}


extension LoopAudioManager {
    // MARK: - Style Transfer Generation
        
    /// Generic Style Transfer Function
    private func generateStyleTransferLoop(
        prompt: String,
        bpm: Int,
        loopType: LoopType,
        styleStrength: Float = 0.8,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        guard startGeneration() else { return }
        
        // Generate combined audio
        guard let combinedAudioURL = generateCombinedAudioForStyleTransfer() else {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create combined audio for style transfer"
            }
            cleanupGeneration()
            return
        }
        
        print("\(loopType.generationEmoji) Starting \(loopType.displayName.lowercased()) style transfer with combined audio")
        
        // Build the prompt with BPM
        let finalPrompt = "\(prompt) \(bpm)bpm"
        
        // Create request URL
        guard let url = URL(string: "\(backendURL)/generate/loop") else {
            DispatchQueue.main.async {
                self.errorMessage = "Invalid backend URL"
            }
            cleanupGeneration()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Use MultipartFormData utility
        var formData = MultipartFormData()
        
        // Add audio file for style transfer
        formData.addFile(
            url: combinedAudioURL,
            name: "audio_file",
            filename: "combined_loop.wav",
            mimeType: "audio/wav"
        )
        
        // Add form fields
        formData.addField(name: "prompt", value: finalPrompt)
        formData.addField(name: "loop_type", value: loopType.apiLoopType)
        formData.addField(name: "style_strength", value: "\(styleStrength)")
        formData.addField(name: "steps", value: "\(steps)")
        formData.addField(name: "cfg_scale", value: "\(cfgScale)")
        formData.addField(name: "seed", value: "\(seed)")
        formData.addField(name: "return_format", value: "base64")
        
        // Add bars if specified
        if let bars = bars {
            formData.addField(name: "bars", value: "\(bars)")
        }
        
        // Set request headers and body
        request.setValue(formData.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.encode()
        
        print("\(loopType.generationEmoji) Generating \(loopType.displayName.lowercased()) style transfer: '\(finalPrompt)'")
        print("   Style strength: \(styleStrength), Steps: \(steps), CFG: \(cfgScale), Seed: \(seed)")
        print("   Combined audio: \(combinedAudioURL.lastPathComponent)")
        
        // Make the request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            self?.cleanupGeneration()
            
            // Clean up temporary file
            try? FileManager.default.removeItem(at: combinedAudioURL)
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Invalid response from server"
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Server error: \(httpResponse.statusCode)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "No data received"
                }
                return
            }
            
            // Parse JSON response
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                
                guard let audioBase64 = jsonResponse?["audio_base64"] as? String,
                      let metadata = jsonResponse?["metadata"] as? [String: Any] else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Invalid JSON response format"
                    }
                    return
                }
                
                // Decode base64 audio data
                guard let audioData = Data(base64Encoded: audioBase64) else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Failed to decode base64 audio"
                    }
                    return
                }
                
                // Add style transfer metadata
                var enhancedMetadata = metadata
                enhancedMetadata["isStyleTransfer"] = true
                enhancedMetadata["styleStrength"] = styleStrength
                enhancedMetadata["sourceType"] = "combined_loops"
                
                // Save with appropriate loop type
                self?.saveLoop(data: audioData, bpm: bpm, metadata: enhancedMetadata, loopType: loopType)
                
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                }
            }
            
        }.resume()
    }

    // MARK: - Style Transfer Wrapper Functions (Preserve Existing API)
    func generateDrumStyleTransfer(
        prompt: String,
        bpm: Int,
        styleStrength: Float = 0.8,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        generateStyleTransferLoop(
            prompt: prompt,
            bpm: bpm,
            loopType: .drums,
            styleStrength: styleStrength,
            steps: steps,
            cfgScale: cfgScale,
            seed: seed,
            bars: bars
        )
    }

    func generateInstrumentStyleTransfer(
        prompt: String,
        bpm: Int,
        styleStrength: Float = 0.8,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        generateStyleTransferLoop(
            prompt: prompt,
            bpm: bpm,
            loopType: .instruments,
            styleStrength: styleStrength,
            steps: steps,
            cfgScale: cfgScale,
            seed: seed,
            bars: bars
        )
    }
}

extension LoopAudioManager {
    // MARK: - Magenta (Hugging Face Space) loop continuation - FIXED VERSION
    
    struct JamStartResponse: Decodable { let session_id: String }
    struct JamStopRequest: Encodable { let session_id: String }
    struct JamConsumeRequest: Encodable {
        let session_id: String
        let chunk_index: Int
    }

    // Updated response structures for single chunk delivery
    struct JamNextResponse: Decodable {
        let chunk: JamChunk
    }
    
    struct JamChunk: Decodable {
        let index: Int
        let audio_base64: String
        let metadata: JamMetadata
    }
    
    struct JamMetadata: Decodable {
        let bpm: Int
        let bars: Int
        let beats_per_bar: Int
        let sample_rate: Int
        let channels: Int
        let total_samples: Int
        let seconds_per_bar: Double
        let loop_duration_seconds: Double
        let guidance_weight: Double
        let temperature: Double
        let topk: Int
    }
    
    struct JamStatusResponse: Decodable {
        let running: Bool
        let last_generated_index: Int
        let last_delivered_index: Int
        let buffer_ahead: Int
        let queued_chunks: Int
        let bpm: Double
        let beats_per_bar: Int
        let bars_per_chunk: Int
        let chunk_duration_seconds: Double
        let target_sample_rate: Int
    }
    
    // MARK: - Reseed (Splice) — minimal hardcoded version
    func requestReseedSplice(anchorBars: Double = 4.0) {
        // must be running to reseed
        guard case .running(let sessionID) = jamState else {
            print("❌ Reseed requested but jam is not running")
            return
        }

        // figure out barsPerChunk + bpm from the pending request (fallbacks)
        let barsPerChunk = pendingJamRequest?.barsPerChunk ?? 8
        let bpm = pendingJamRequest?.bpm ?? 120

        // target duration = current chunk size (keeps things bar-aligned)
        let secondsPerBar = (60.0 / Double(bpm)) * 4.0
        let targetDuration = Double(barsPerChunk) * secondsPerBar

        // build a fresh combined bounce from current loops
        guard
            let drumURL = playerManager?.drumAudioURL,
            let instrumentURL = playerManager?.instrumentAudioURL,
            let drumMetadata = playerManager?.drumLoopMetadata,
            let instrumentMetadata = playerManager?.instrumentLoopMetadata,
            let combinedAudioURL = createCombinedLoopedAudio(
                drumURL: drumURL,
                instrumentURL: instrumentURL,
                drumMetadata: drumMetadata,
                instrumentMetadata: instrumentMetadata,
                targetDuration: targetDuration
            )
        else {
            DispatchQueue.main.async {
                self.errorMessage = "Need both drum & instrument loops to reseed"
            }
            return
        }

        // POST /jam/reseed_splice (multipart)
        let reseedURL = magentaBaseURL.appendingPathComponent("jam/reseed_splice")
        var request = URLRequest(url: reseedURL)
        request.httpMethod = "POST"

        var form = MultipartFormData()
        form.addField(name: "session_id", value: sessionID)
        form.addField(name: "anchor_bars", value: String(format: "%.2f", anchorBars))
        form.addFile(url: combinedAudioURL,
                     name: "combined_audio",
                     filename: "combined_now.wav",
                     mimeType: "audio/wav")

        request.setValue(form.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encode()

        print("🔁 Reseed (splice) → anchor_bars=\(anchorBars), duration=\(String(format: "%.2fs", targetDuration))")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // clean up temp file either way
            try? FileManager.default.removeItem(at: combinedAudioURL)

            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Reseed network error: \(error.localizedDescription)"
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                DispatchQueue.main.async { self?.errorMessage = "Reseed: invalid response" }
                return
            }
            guard http.statusCode == 200, let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Reseed failed: HTTP \(http.statusCode)"
                }
                return
            }
            // optional: parse {"ok":true,"anchor_bars":...} for logging
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("✅ Reseed ok:", json)
            } else {
                print("✅ Reseed ok (no json)")
            }
        }.resume()
    }

    
    
    
    func requestStartMagentaJam(
        bpm: Int,
        barsPerChunk: Int,
        styles: [String],
        styleWeights: [Double],
        loopWeight: Double,
        temperature: Double,
        topK: Int,
        guidanceWeight: Double
    ) {
        // Guards - similar to generateInstrumentMagenta
        guard !isGenerating else {
            print("❌ Loop generation already in progress")
            return
        }
        
        guard jamState == .idle else {
            print("❌ Jam session already active")
            return
        }
        
        // Calculate target duration for combined audio
        let secondsPerBar = (60.0 / Double(bpm)) * 4.0
        let targetDuration = Double(barsPerChunk) * secondsPerBar
        
        // Create combined audio - same pattern as generateInstrumentMagenta
        guard
            let drumURL = playerManager?.drumAudioURL,
            let instrumentURL = playerManager?.instrumentAudioURL,
            let drumMetadata = playerManager?.drumLoopMetadata,
            let instrumentMetadata = playerManager?.instrumentLoopMetadata,
            let combinedAudioURL = createCombinedLoopedAudio(
                drumURL: drumURL,
                instrumentURL: instrumentURL,
                drumMetadata: drumMetadata,
                instrumentMetadata: instrumentMetadata,
                targetDuration: targetDuration
            )
        else {
            DispatchQueue.main.async {
                self.errorMessage = "Need both drum and instrument loops for jam session"
            }
            return
        }
        
        // Set state
        jamState = .starting
        pendingJamRequest = PendingJamRequest(
            bpm: bpm,
            barsPerChunk: barsPerChunk,
            styles: styles,
            styleWeights: styleWeights,
            loopWeight: loopWeight,
            temperature: temperature,
            topK: topK,
            guidanceWeight: guidanceWeight
        )
        
        if let req = pendingJamRequest {
            DispatchQueue.main.async { self.magentaConfig.apply(pending: req) }
        }
        
        print("🎸 Starting Magenta jam session:")
        print("   BPM: \(bpm), Bars per chunk: \(barsPerChunk)")
        print("   Styles: \(styles)")
        print("   Combined audio: \(combinedAudioURL.lastPathComponent) (\(String(format: "%.2fs", targetDuration)))")
        
        // Build request to /jam/start (unchanged)
        guard let url = URL(string: "https://thecollabagepatch-magenta-retry.hf.space/jam/start") else {
            DispatchQueue.main.async {
                self.jamState = .error("Invalid Magenta URL")
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Use the MultipartFormData struct (unchanged)
        var formData = MultipartFormData()
        
        // Add audio file
        formData.addFile(
            url: combinedAudioURL,
            name: "loop_audio",
            filename: "combined_loop.wav",
            mimeType: "audio/wav"
        )
        
        // Add jam parameters (unchanged)
        formData.addField(name: "bpm", value: "\(bpm)")
        formData.addField(name: "bars_per_chunk", value: "\(barsPerChunk)")
        formData.addField(name: "beats_per_bar", value: "4")
        
        // Styles and weights
        let styleList = styles.joined(separator: ",")
        let weightsList = styleWeights.map { String(format: "%.4f", $0) }.joined(separator: ",")
        formData.addField(name: "styles", value: styleList)
        formData.addField(name: "style_weights", value: weightsList)
        
        // Loop influence and parameters
        formData.addField(name: "loop_weight", value: String(format: "%.3f", loopWeight))
        formData.addField(name: "guidance_weight", value: String(format: "%.4f", guidanceWeight))
        formData.addField(name: "temperature", value: String(format: "%.4f", temperature))
        formData.addField(name: "topk", value: "\(topK)")
        
        // Set request headers and body
        request.setValue(formData.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.encode()
        
        // Make the request (unchanged)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            // Clean up temporary file
            try? FileManager.default.removeItem(at: combinedAudioURL)
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.jamState = .error("Network error: \(error.localizedDescription)")
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self?.jamState = .error("Invalid response from server")
                }
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.jamState = .error("Server error: \(httpResponse.statusCode)")
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.jamState = .error("No data received")
                }
                return
            }
            
            // Parse response (unchanged)
            do {
                let response = try JSONDecoder().decode(JamStartResponse.self, from: data)
                
                DispatchQueue.main.async {
                    self?.jamState = .running(sessionID: response.session_id)
                    
                    // Start the NEW sequential chunk fetching
                    self?.startSequentialJamFetching(sessionID: response.session_id)
                    
                    // Post notification
                    NotificationCenter.default.post(name: .magentaJamStarted, object: nil)
                    
                    print("✅ Jam session started with ID: \(response.session_id)")
                }
                
            } catch {
                DispatchQueue.main.async {
                    self?.jamState = .error("Failed to parse response: \(error.localizedDescription)")
                }
            }
            
        }.resume()
    }
    
    private func postMultipart(
        fullURLOverride: URL? = nil,      // use for quick sanity checks
        path: String,                     // e.g. "jam/update" (no leading slash)
        form: MultipartFormData,
        timeout: TimeInterval = 12
    ) async throws -> (Data, HTTPURLResponse) {
        precondition(!path.hasPrefix("/"), "Pass path without leading slash")
        let url = fullURLOverride ?? magentaBaseURL.appendingPathComponent(path)

        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue(form.contentTypeHeader, forHTTPHeaderField: "Content-Type")

        let rid = UUID().uuidString
        req.setValue(rid, forHTTPHeaderField: "X-Request-ID")
        req.httpBody = form.encode()

        print("➡️ POST \(url.absoluteString) [rid=\(rid)]")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        print("⬅️ \(http.statusCode) \(url.lastPathComponent) [rid=\(rid)]")
        return (data, http)
    }

    
    func requestUpdateMagentaAll(
        useCurrentMixAsStyle: Bool,
        fullURLOverride: URL? = nil
    ) async throws {
        // Pull the session id straight from the enum:
        guard case let .running(sessionID) = jamState else {
            throw JamUpdateError.noActiveJam
        }

        let cfg = magentaConfig
        var form = MultipartFormData()
        form.addField(name: "session_id", value: sessionID)
        form.addField(name: "guidance_weight", value: String(cfg.guidanceWeight))
        form.addField(name: "temperature",     value: String(cfg.temperature))
        form.addField(name: "topk",            value: String(cfg.topK))
        form.addField(name: "styles",          value: cfg.styles.map(\.text).joined(separator: ","))
        form.addField(name: "style_weights",   value: cfg.styles.map { String(format: "%.4f", $0.weight) }.joined(separator: ","))
        form.addField(name: "use_current_mix_as_style", value: useCurrentMixAsStyle ? "true" : "false")
        form.addField(name: "loop_weight",     value: String(format: "%.3f", cfg.loopWeight))

        let (data, http) = try await postMultipart(
            fullURLOverride: fullURLOverride,
            path: "jam/update",
            form: form
        )
        guard (200..<300).contains(http.statusCode) else {
            if let s = String(data: data, encoding: .utf8) { print("🧾 body:", s) }
            throw JamUpdateError.badStatus(http.statusCode)
        }
    }

    // MARK: - NEW Sequential Chunk Fetching Logic

    private func startSequentialJamFetching(sessionID: String) {
        jamLastIndex = 0  // Reset counter
        
        print("🔄 Started sequential jam fetching for session: \(sessionID)")
        
        // Immediately fetch the first chunk
        fetchNextSequentialChunk(sessionID: sessionID)
    }

    private func fetchNextSequentialChunk(sessionID: String) {
        guard case .running = jamState else {
            print("⏹️ Jam session not running, stopping chunk fetch")
            return
        }
        
        // Call the NEW /jam/next endpoint (no query params needed)
        guard let url = URL(string: "https://thecollabagepatch-magenta-retry.hf.space/jam/next?session_id=\(sessionID)") else {
            print("❌ Invalid jam/next URL")
            return
        }
        
        print("📡 Fetching next sequential chunk (after \(jamLastIndex))...")
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error = error {
                print("❌ Error fetching chunk: \(error.localizedDescription)")
                // Retry after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.fetchNextSequentialChunk(sessionID: sessionID)
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.fetchNextSequentialChunk(sessionID: sessionID)
                }
                return
            }
            
            // Handle different status codes
            switch httpResponse.statusCode {
            case 200:
                // Success - process the chunk
                guard let data = data else {
                    print("❌ No data in 200 response")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self?.fetchNextSequentialChunk(sessionID: sessionID)
                    }
                    return
                }
                
                self?.processJamChunk(data: data, sessionID: sessionID)
                
            case 204:
                // No content - chunk not ready yet, retry after short delay
                print("⏳ Chunk not ready yet, retrying...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self?.fetchNextSequentialChunk(sessionID: sessionID)
                }
                
            case 404:
                // Session not found - stop
                print("❌ Jam session not found")
                DispatchQueue.main.async {
                    self?.jamState = .error("Session not found")
                }
                
            case 408:
                // Timeout - retry
                print("⏰ Chunk generation timeout, retrying...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.fetchNextSequentialChunk(sessionID: sessionID)
                }
                
            default:
                print("❌ Unexpected status code: \(httpResponse.statusCode)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.fetchNextSequentialChunk(sessionID: sessionID)
                }
            }
            
        }.resume()
    }

    private func processJamChunk(data: Data, sessionID: String) {
        do {
            let response = try JSONDecoder().decode(JamNextResponse.self, from: data)
            let chunk = response.chunk
            
            // Validate chunk sequence
            let expectedIndex = jamLastIndex + 1
            if chunk.index != expectedIndex {
                print("⚠️ Chunk sequence warning: expected \(expectedIndex), got \(chunk.index)")
            }
            
            // Decode audio
            guard let audioData = Data(base64Encoded: chunk.audio_base64) else {
                print("❌ Failed to decode chunk \(chunk.index) audio")
                jamLastIndex = chunk.index
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.fetchNextSequentialChunk(sessionID: sessionID)
                }
                return
            }
            
            // Update tracking
            jamLastIndex = chunk.index
            
            // Convert metadata and ADD chunk tracking info
            let metadataDict: [String: Any] = [
                "bpm": chunk.metadata.bpm,
                "bars": chunk.metadata.bars,
                "beats_per_bar": chunk.metadata.beats_per_bar,
                "sample_rate": chunk.metadata.sample_rate,
                "channels": chunk.metadata.channels,
                "total_samples": chunk.metadata.total_samples,
                "seconds_per_bar": chunk.metadata.seconds_per_bar,
                "loop_duration_seconds": chunk.metadata.loop_duration_seconds,
                "guidance_weight": chunk.metadata.guidance_weight,
                "temperature": chunk.metadata.temperature,
                "topk": chunk.metadata.topk,
                "sourceType": "magenta_jam",
                "jam_chunk_index": chunk.index,     // 🎯 Key for tracking!
                "jam_session_id": sessionID
            ]
            
            print("✅ Processed sequential jam chunk \(chunk.index) - queued for playback")
            
            // Save as instrument loop (this queues it for later playback)
            DispatchQueue.main.async {
                self.saveInstrumentLoop(data: audioData, bpm: chunk.metadata.bpm, metadata: metadataDict)
                
                // Immediately request the next chunk
                self.fetchNextSequentialChunk(sessionID: sessionID)
            }
            
            // ❌ DON'T mark consumed here - wait for actual playback!
            // self.markChunkConsumed(sessionID: sessionID, chunkIndex: chunk.index)
            
        } catch {
            print("❌ Failed to parse jam chunk: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.fetchNextSequentialChunk(sessionID: sessionID)
            }
        }
    }

    // Optional: Mark chunk as consumed for better backend flow control
    private func markChunkConsumed(sessionID: String, chunkIndex: Int) {
        guard let url = URL(string: "https://thecollabagepatch-magenta-retry.hf.space/jam/consume") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        var formData = MultipartFormData()
        formData.addField(name: "session_id", value: sessionID)
        formData.addField(name: "chunk_index", value: "\(chunkIndex)")
        
        request.setValue(formData.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = formData.encode()
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Fire and forget - don't need to handle response
            if let error = error {
                print("⚠️ Failed to mark chunk \(chunkIndex) consumed: \(error.localizedDescription)")
            }
        }.resume()
    }

    // MARK: - Enhanced Status Checking (Optional)
    
    func getJamStatus(sessionID: String, completion: @escaping (JamStatusResponse?) -> Void) {
        guard let url = URL(string: "https://thecollabagepatch-magenta-retry.hf.space/jam/status?session_id=\(sessionID)") else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                completion(nil)
                return
            }
            
            do {
                let status = try JSONDecoder().decode(JamStatusResponse.self, from: data)
                completion(status)
            } catch {
                print("❌ Failed to parse jam status: \(error)")
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Stop Logic (Enhanced)
    
    func requestStopMagentaJam() {
        guard case .running(let sessionID) = jamState else { return }
        
        jamState = .stopping
        
        print("🛑 Stopping jam session: \(sessionID)")
        
        // Call the actual /jam/stop endpoint (unchanged)
        guard let url = URL(string: "https://thecollabagepatch-magenta-retry.hf.space/jam/stop") else {
            DispatchQueue.main.async {
                self.jamState = .error("Invalid stop URL")
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Backend expects: {"session_id": "..."}
        let requestBody = JamStopRequest(session_id: sessionID)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("❌ Failed to encode stop request: \(error)")
            cleanupJamSession(sessionID: sessionID)
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("⚠️ Stop request failed: \(error.localizedDescription)")
                    // Still clean up locally even if backend call failed
                } else if let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 {
                    print("✅ Jam session stopped successfully")
                } else {
                    print("⚠️ Unexpected stop response")
                }
                
                // Always clean up local state
                self?.cleanupJamSession(sessionID: sessionID)
            }
        }.resume()
    }

    private func cleanupJamSession(sessionID: String) {
        // Reset tracking variables
        jamLastIndex = 0
        
        // Clear state
        jamState = .idle
        pendingJamRequest = nil
        
        // Post notification
        NotificationCenter.default.post(
            name: .magentaJamStopped,
            object: nil,
            userInfo: ["sessionID": sessionID, "stopped": true]
        )
        
        print("🧹 Cleaned up jam session: \(sessionID)")
    }
    
    func generateInstrumentMagenta(
            bpm: Int,
            bars: Int,
            styles: [String],
            styleWeights: [Double],
            loopWeight: Double,
            temperature: Double,
            topK: Int,
            guidanceWeight: Double
        ) {
            guard startGeneration() else { return }

            // Compute a target duration so the input mix matches Magenta's bar length
            // beats_per_bar is fixed to 4 for now
            let secondsPerBar = (60.0 / Double(bpm)) * 4.0
            let targetDuration = Double(bars) * secondsPerBar

            // Build a combined 'currently playing' mix to send as loop_audio
            guard
                let drumURL = playerManager?.drumAudioURL,
                let instrumentURL = playerManager?.instrumentAudioURL,
                let drumMD = playerManager?.drumLoopMetadata,
                let instrMD = playerManager?.instrumentLoopMetadata,
                let combinedAudioURL = createCombinedLoopedAudio(
                    drumURL: drumURL,
                    instrumentURL: instrumentURL,
                    drumMetadata: drumMD,
                    instrumentMetadata: instrMD,
                    targetDuration: targetDuration
                )
            else {
                DispatchQueue.main.async { self.errorMessage = "Need both drum and instrument loops" }
                cleanupGeneration()
                return
            }

            // Build request to the Space
            guard let url = URL(string: "https://thecollabagepatch-magenta-retry.hf.space/generate") else {
                DispatchQueue.main.async {
                    self.errorMessage = "Invalid Magenta URL"
                }
                cleanupGeneration()
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            // Use MultipartFormData utility
            var formData = MultipartFormData()

            // Add audio file as 'loop_audio' (different from style-transfer's "audio_file")
            formData.addFile(
                url: combinedAudioURL,
                name: "loop_audio",
                filename: "combined_loop.wav",
                mimeType: "audio/wav"
            )

            // Add core fields
            formData.addField(name: "bpm", value: "\(bpm)")
            formData.addField(name: "bars", value: "\(bars)")
            formData.addField(name: "beats_per_bar", value: "4")

            // Styles + weights (comma-joined; backend tolerates empty)
            let styleList = styles.joined(separator: ",")
            let weightsList = styleWeights.map { String(format: "%.4f", $0) }.joined(separator: ",")
            formData.addField(name: "styles", value: styleList)
            formData.addField(name: "style_weights", value: weightsList)

            // Loop influence
            formData.addField(name: "loop_weight", value: String(format: "%.3f", loopWeight))

            // Advanced parameters
            formData.addField(name: "guidance_weight", value: String(format: "%.4f", guidanceWeight))
            formData.addField(name: "temperature", value: String(format: "%.4f", temperature))
            formData.addField(name: "topk", value: "\(topK)")

            // Set request headers and body
            request.setValue(formData.contentTypeHeader, forHTTPHeaderField: "Content-Type")
            request.httpBody = formData.encode()

            print("✨ Magenta request:")
            print("   bpm=\(bpm), bars=\(bars), styles=[\(styleList)], weights=[\(weightsList)]")
            print("   loop_weight=\(loopWeight), temp=\(temperature), topk=\(topK), guidance=\(guidanceWeight)")
            print("   combined: \(combinedAudioURL.lastPathComponent) (\(String(format: "%.2fs", targetDuration)))")

            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                // Always clear state + remove temp file
                self?.cleanupGeneration()
                try? FileManager.default.removeItem(at: combinedAudioURL)

                if let error = error {
                    DispatchQueue.main.async { self?.errorMessage = "Network error: \(error.localizedDescription)" }
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    DispatchQueue.main.async { self?.errorMessage = "Invalid response from server" }
                    return
                }
                guard http.statusCode == 200, let data = data else {
                    DispatchQueue.main.async { self?.errorMessage = "Server error: \(http.statusCode)" }
                    return
                }

                // JSON: { audio_base64, metadata }
                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard
                        let b64 = json?["audio_base64"] as? String,
                        let meta = json?["metadata"] as? [String: Any],
                        let audio = Data(base64Encoded: b64)
                    else {
                        DispatchQueue.main.async { self?.errorMessage = "Invalid JSON response format" }
                        return
                    }

                    // Enrich metadata so the player math is bulletproof
                    var enhanced = meta
                    // If backend didn't include these (it should), compute fallbacks:
                    if enhanced["seconds_per_bar"] == nil {
                        enhanced["seconds_per_bar"] = secondsPerBar
                    }
                    if enhanced["loop_duration_seconds"] == nil {
                        enhanced["loop_duration_seconds"] = Double(bars) * secondsPerBar
                    }
                    if enhanced["detected_bpm"] == nil {
                        enhanced["detected_bpm"] = bpm
                    }
                    // Helpful tags for observability
                    enhanced["sourceType"] = "magenta"
                    enhanced["styles"] = styles
                    enhanced["style_weights"] = styleWeights
                    enhanced["loop_weight"] = loopWeight

                    self?.saveInstrumentLoop(data: audio, bpm: bpm, metadata: enhanced)

                } catch {
                    DispatchQueue.main.async { self?.errorMessage = "Failed to parse response: \(error.localizedDescription)" }
                }
            }.resume()
        }
}
