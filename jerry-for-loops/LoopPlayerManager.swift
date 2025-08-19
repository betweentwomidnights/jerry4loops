import Foundation
import AVFoundation

// Notification for waveform progress updates
// extension Notification.Name {
//    static let waveformProgressUpdate = Notification.Name("waveformProgressUpdate")
//    static let loopSwitched = Notification.Name("loopSwitched")
// }

class LoopPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var drumAudioURL: URL?
    @Published var isPlaying: Bool = false
    @Published var currentBPM: Int = 120
    @Published var isGeneratingNext: Bool = false
    @Published var nextLoopQueued: Bool = false
    
    // Dual player system for seamless switching
    private var currentPlayer: AVAudioPlayer?
    private var nextPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var switchTimer: Timer?
    
    // Queuing system
    private var queuedAudioURL: URL?
    private var isCurrentPlayerPrimary: Bool = true // Track which player is active
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    deinit {
        stopAll()
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    // MARK: - Drum Loop Management
   // func loadDrumLoop(_ url: URL) {
   //     if isPlaying && currentPlayer != nil {
   //         // Queue for next loop if currently playing
   //         queueNextLoop(url)
   //     } else {
   //         // Load immediately if not playing
   //         loadImmediately(url)
   //     }
   // }
    
    private func loadImmediately(_ url: URL) {
        stopAll() // Stop any current playback
        
        do {
            currentPlayer = try AVAudioPlayer(contentsOf: url)
            currentPlayer?.delegate = self
            currentPlayer?.numberOfLoops = -1 // Infinite loops
            currentPlayer?.prepareToPlay()
            
            drumAudioURL = url
            isCurrentPlayerPrimary = true
            
            print("✅ Drum loop loaded immediately: \(url.lastPathComponent)")
            if let duration = currentPlayer?.duration {
                print("📊 Loop duration: \(String(format: "%.2f", duration))s")
            }
            
        } catch {
            print("❌ Failed to load drum loop: \(error)")
            drumAudioURL = nil
        }
    }
    
    private func queueNextLoop(_ url: URL) {
        print("🎵 Queuing next loop: \(url.lastPathComponent)")
        queuedAudioURL = url
        nextLoopQueued = true
        
        // Prepare the next player
        do {
            nextPlayer = try AVAudioPlayer(contentsOf: url)
            nextPlayer?.delegate = self
            nextPlayer?.numberOfLoops = -1
            nextPlayer?.prepareToPlay()
            
            // Schedule the switch at the next loop boundary
            scheduleLoopSwitch()
            
        } catch {
            print("❌ Failed to prepare next loop: \(error)")
            queuedAudioURL = nil
            nextLoopQueued = false
        }
    }
    
    // MARK: - Seamless Loop Switching
    private func scheduleLoopSwitch() {
        guard let current = currentPlayer,
              current.isPlaying else { return }
        
        // Calculate time until next loop completion
        let currentTime = current.currentTime
        let loopDuration = current.duration
        let timeInCurrentLoop = currentTime.truncatingRemainder(dividingBy: loopDuration)
        let timeUntilLoopEnd = loopDuration - timeInCurrentLoop
        
        print("🔄 Scheduling loop switch in \(String(format: "%.3f", timeUntilLoopEnd))s")
        
        // Cancel any existing switch timer
        switchTimer?.invalidate()
        
        // Schedule the switch with high precision
        switchTimer = Timer.scheduledTimer(withTimeInterval: timeUntilLoopEnd - 0.05, repeats: false) { [weak self] _ in
            self?.executeLoopSwitch()
        }
    }
    
    private func executeLoopSwitch() {
        guard let nextAudioPlayer = nextPlayer,
              let queuedURL = queuedAudioURL else {
            print("⚠️ No next player ready for switch")
            return
        }
        
        print("🔄 Executing seamless loop switch")
        
        // Stop the current player
        currentPlayer?.stop()
        
        // Start the next player from the beginning
        nextAudioPlayer.currentTime = 0
        nextAudioPlayer.play()
        
        // Swap the players
        currentPlayer = nextAudioPlayer
        nextPlayer = nil
        
        // Update state
        drumAudioURL = queuedURL
        queuedAudioURL = nil
        nextLoopQueued = false
        isCurrentPlayerPrimary = !isCurrentPlayerPrimary
        
        // Post notification for UI updates
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .loopSwitched,
                object: nil,
                userInfo: ["newAudioURL": queuedURL]
            )
        }
        
        print("✅ Loop switch completed: \(queuedURL.lastPathComponent)")
    }
    
    // MARK: - Playback Controls
    func startLooping() {
        guard let drumPlayer = currentPlayer else {
            print("⚠️ No drum player available")
            return
        }
        
        if !drumPlayer.isPlaying {
            drumPlayer.currentTime = 0 // Start from beginning
            drumPlayer.play()
            isPlaying = true
            startProgressTimer()
            print("▶️ Started drum loop playback")
        }
    }
    
    func stopAll() {
        currentPlayer?.stop()
        nextPlayer?.stop()
        isPlaying = false
        stopProgressTimer()
        switchTimer?.invalidate()
        
        // Clear queued state
        queuedAudioURL = nil
        nextLoopQueued = false
        
        print("⏹️ Stopped all playback")
    }
    
    func updateBPM(_ newBPM: Int) {
        currentBPM = newBPM
        // Note: BPM changes don't affect playback speed in this simple implementation
        // The BPM is used for generation, not real-time playback modification
    }
    
    // MARK: - Progress Tracking
    private func startProgressTimer() {
        stopProgressTimer()
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        guard let drumPlayer = currentPlayer,
              drumPlayer.isPlaying,
              let drumURL = drumAudioURL else { return }
        
        let currentTime = drumPlayer.currentTime
        let duration = drumPlayer.duration
        
        // Post notification for waveform updates
        NotificationCenter.default.post(
            name: .waveformProgressUpdate,
            object: nil,
            userInfo: [
                "id": "drums",
                "currentTime": currentTime,
                "duration": duration,
                "audioURL": drumURL
            ]
        )
    }
    
    // MARK: - Seek Functionality
    func seekDrumLoop(to time: TimeInterval) {
        guard let drumPlayer = currentPlayer else { return }
        
        let wasPlaying = drumPlayer.isPlaying
        drumPlayer.currentTime = min(time, drumPlayer.duration)
        
        if !wasPlaying {
            // If not playing, just update the visual progress
            updateProgress()
        }
        
        print("🎯 Seeked drum loop to \(String(format: "%.2f", time))s")
    }
    
    // MARK: - Generation State Management
    func setGeneratingNext(_ generating: Bool) {
        DispatchQueue.main.async {
            self.isGeneratingNext = generating
        }
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if !flag {
            print("❌ Audio player finished with error")
            isPlaying = false
            stopProgressTimer()
        }
        // Note: With numberOfLoops = -1, this shouldn't be called unless there's an error
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ Audio player decode error: \(error?.localizedDescription ?? "Unknown")")
        isPlaying = false
        stopProgressTimer()
    }
}
