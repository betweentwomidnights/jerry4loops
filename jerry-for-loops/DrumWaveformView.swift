//
//  DrumWaveformView.swift
//  jerry-for-loops
//
//  Created by Kevin Griffing on 6/17/25.
//

import SwiftUI
import AVFoundation
import FDWaveformView
// Note: This assumes FDWaveformView is available in the project
// You'll need to add the FDWaveformView library to your project

struct DrumWaveformView: View {
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
                    waveformId: "drums",
                    waveformColor: Color.red,
                    onSeek: { time in
                        playerManager.seekDrumLoop(to: time)
                    }
                )
                .background(Color.black)
                .cornerRadius(6)
            } else {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("No drum loop loaded")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .cornerRadius(6)
            }
            
            // Play indicator overlay
            if isPlaying {
                VStack {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.green.opacity(0.8))
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

// Updated generic wrapper for filtered audio - supports both drums and instruments
struct FilteredWaveformWrapper: UIViewRepresentable {
    let audioURL: URL
    @Binding var totalSamples: Int
    let waveformId: String // "drums" or "instruments"
    let waveformColor: Color
    let onSeek: ((TimeInterval) -> Void)?
    
    func makeUIView(context: Context) -> FDWaveformView {
        let waveformView = FDWaveformView()
        waveformView.delegate = context.coordinator
        context.coordinator.waveformView = waveformView
        
        // Configure for audio loop display
        waveformView.audioURL = audioURL
        customizeWaveformAppearance(waveformView, color: waveformColor)
        
        // Add tap gesture for seeking
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleTap(_:))
        )
        waveformView.addGestureRecognizer(tapGesture)
        
        return waveformView
    }
    
    func updateUIView(_ uiView: FDWaveformView, context: Context) {
        // Update audio URL if changed
        if uiView.audioURL != audioURL {
            uiView.audioURL = audioURL
            customizeWaveformAppearance(uiView, color: waveformColor)
            
            // Reset progress highlighting
            uiView.highlightedSamples = 0..<0
            
            // Update audio duration in coordinator (async)
            let audioAsset = AVURLAsset(url: audioURL)
            Task {
                do {
                    let duration = try await audioAsset.load(.duration)
                    await MainActor.run {
                        context.coordinator.audioDuration = CMTimeGetSeconds(duration)
                    }
                } catch {
                    print("❌ Failed to load audio duration: \(error)")
                }
            }
        }
    }
    
    func makeCoordinator() -> FilteredWaveformCoordinator {
        FilteredWaveformCoordinator(self)
    }
    
    private func customizeWaveformAppearance(_ waveformView: FDWaveformView, color: Color) {
        // Use direct UIColors for better visibility instead of converting SwiftUI Colors
        if waveformId == "drums" {
            waveformView.wavesColor = UIColor.red
            waveformView.progressColor = UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0) // Bright red progress
        } else {
            waveformView.wavesColor = UIColor.systemPurple
            waveformView.progressColor = UIColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1.0) // Bright purple progress
        }
        
        waveformView.backgroundColor = UIColor.black
        
        // Disable scrolling but allow scrubbing for seeking
        waveformView.doesAllowScrubbing = true
        waveformView.doesAllowScroll = false
    }
    
    class FilteredWaveformCoordinator: NSObject, FDWaveformViewDelegate {
        var parent: FilteredWaveformWrapper
        var waveformView: FDWaveformView?
        var audioDuration: TimeInterval?
        
        // ENHANCED: Track loading state to prevent race conditions
        private var isLoadingNewAudio = false
        private var lastAudioURL: URL?
        
        init(_ parent: FilteredWaveformWrapper) {
            self.parent = parent
            super.init()
            
            // Listen for progress updates
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(updateProgress(notification:)),
                name: .waveformProgressUpdate,
                object: nil
            )
            
            // Listen for type-specific loop switches based on waveform ID
            let switchNotification: Notification.Name = parent.waveformId == "drums" ? .drumLoopSwitched : .instrumentLoopSwitched
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleLoopSwitch(notification:)),
                name: switchNotification,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func handleLoopSwitch(notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let newAudioURL = userInfo["newAudioURL"] as? URL,
                  let waveformView = waveformView else { return }
            
            print("🔄 [\(parent.waveformId)] Handling loop switch to: \(newAudioURL.lastPathComponent)")
            
            // ENHANCED: Mark as loading to prevent race conditions
            isLoadingNewAudio = true
            lastAudioURL = newAudioURL
            
            // Update the waveform to show the new audio
            DispatchQueue.main.async {
                waveformView.audioURL = newAudioURL
                waveformView.highlightedSamples = 0..<0 // Reset progress
                
                // IMPORTANT: Use the same bright colors as initial setup
                if self.parent.waveformId == "drums" {
                    waveformView.wavesColor = UIColor.red
                    waveformView.progressColor = UIColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
                } else {
                    waveformView.wavesColor = UIColor.systemPurple
                    waveformView.progressColor = UIColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1.0)
                }
                waveformView.backgroundColor = UIColor.black
                
                // Update duration for the new audio
                let asset = AVURLAsset(url: newAudioURL)
                Task {
                    do {
                        let duration = try await asset.load(.duration)
                        let durationSeconds = CMTimeGetSeconds(duration)
                        await MainActor.run {
                            self.audioDuration = durationSeconds
                            print("✅ [\(self.parent.waveformId)] Audio duration updated: \(String(format: "%.2f", durationSeconds))s")
                        }
                    } catch {
                        print("❌ [\(self.parent.waveformId)] Failed to load new audio duration: \(error)")
                    }
                }
            }
        }
        
        @objc func updateProgress(notification: Notification) {
            guard let userInfo = notification.userInfo,
                  let notificationId = userInfo["id"] as? String,
                  notificationId == parent.waveformId,
                  let currentTime = userInfo["currentTime"] as? TimeInterval,
                  let duration = userInfo["duration"] as? TimeInterval,
                  let waveformView = waveformView else { return }
            
            // ENHANCED: Prevent race conditions during audio loading
            if isLoadingNewAudio {
                // Check if waveform has finished loading by comparing URLs
                if let currentURL = waveformView.audioURL,
                   let expectedURL = lastAudioURL,
                   currentURL == expectedURL,
                   waveformView.totalSamples > 0 {
                    // Waveform is ready
                    isLoadingNewAudio = false
                    print("✅ [\(parent.waveformId)] Waveform ready after switch, resuming progress updates")
                } else {
                    // Still loading, skip this update
                    return
                }
            }
            
            // ENHANCED: Validate totalSamples before calculating progress
            let totalSamples = waveformView.totalSamples
            guard totalSamples > 0 else {
                print("⚠️ [\(parent.waveformId)] Skipping progress update - totalSamples not ready: \(totalSamples)")
                return
            }
            
            // ENHANCED: Validate progress calculation
            guard currentTime >= 0 && duration > 0 && currentTime <= duration else {
                print("⚠️ [\(parent.waveformId)] Invalid progress data - currentTime: \(currentTime), duration: \(duration)")
                return
            }
            
            let progressSamples = Int((currentTime / duration) * Double(totalSamples))
            
            // ENHANCED: Validate progressSamples range
            guard progressSamples >= 0 && progressSamples <= totalSamples else {
                print("⚠️ [\(parent.waveformId)] Invalid progressSamples: \(progressSamples), totalSamples: \(totalSamples)")
                return
            }
            
            // Update progress highlighting
            waveformView.highlightedSamples = 0..<progressSamples
            
            // Debug log occasionally
#if DEBUG
            if Int(currentTime * 5) % 10 == 0 { // Every 2 seconds
                let progressPercent = (currentTime / duration) * 100
                print("📊 [\(parent.waveformId)] Progress: \(String(format: "%.1f", progressPercent))% (\(progressSamples)/\(totalSamples) samples)")
            }
#endif
        }
        
        @objc func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard let waveformView = waveformView,
                  let duration = audioDuration else { return }
            
            let location = gestureRecognizer.location(in: waveformView)
            let waveformWidth = waveformView.bounds.width
            let progress = location.x / waveformWidth
            
            let newTime = duration * Double(progress)
            
            // Update highlighted samples immediately for visual feedback
            let totalSamples = waveformView.totalSamples
            let newSamplePosition = Int(Double(totalSamples) * progress)
            waveformView.highlightedSamples = 0..<newSamplePosition
            
            // Notify parent to seek
            DispatchQueue.main.async {
                self.parent.onSeek?(newTime)
            }
        }
        
        // MARK: - FDWaveformViewDelegate
        func waveformViewDidLoad(_ waveformView: FDWaveformView) {
            self.waveformView = waveformView
            parent.totalSamples = waveformView.totalSamples
            
            print("✅ [\(parent.waveformId)] Waveform loaded with \(waveformView.totalSamples) samples")
            
            // ENHANCED: Clear loading state when waveform finishes loading
            if isLoadingNewAudio {
                if let currentURL = waveformView.audioURL,
                   let expectedURL = lastAudioURL,
                   currentURL == expectedURL {
                    isLoadingNewAudio = false
                    print("✅ [\(parent.waveformId)] Waveform switch completed successfully")
                }
            }
            
            // Calculate audio duration (async)
            if let audioURL = waveformView.audioURL {
                let asset = AVURLAsset(url: audioURL)
                Task {
                    do {
                        let duration = try await asset.load(.duration)
                        let durationSeconds = CMTimeGetSeconds(duration)
                        await MainActor.run {
                            self.audioDuration = durationSeconds
                        }
                    } catch {
                        print("❌ [\(self.parent.waveformId)] Failed to load audio duration: \(error)")
                    }
                }
            }
        }
    }
}

#Preview {
    DrumWaveformView(
        audioURL: nil,
        isPlaying: .constant(false),
        playerManager: EngineLoopPlayerManager()
    )
    .frame(height: 100)
    .background(Color.gray.opacity(0.2))
}
