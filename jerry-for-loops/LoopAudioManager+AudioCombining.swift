//
//  LoopAudioManager+AudioCombining.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 8/12/25.
//


import Foundation
import AVFoundation

// MARK: - LoopAudioManager Extension for Audio Combining
extension LoopAudioManager {
    
    
    
    /// Generate combined audio from current drum and instrument loops for style transfer
    private func snapshotCurrentLoopFiles()
    -> (drum: URL, inst: URL, drumMeta: [String:Any], instMeta: [String:Any])? {
        guard let pm = playerManager,
              let drumURL = pm.drumAudioURL,
              let instURL = pm.instrumentAudioURL,
              let drumMeta = pm.drumLoopMetadata,
              let instMeta = pm.instrumentLoopMetadata else { return nil }

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("style_snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let drumSnap = base.appendingPathComponent("drum_\(UUID().uuidString).wav")
        let instSnap = base.appendingPathComponent("inst_\(UUID().uuidString).wav")
        do {
            try FileManager.default.copyItem(at: drumURL, to: drumSnap)
            try FileManager.default.copyItem(at: instURL, to: instSnap)
            return (drum: drumSnap, inst: instSnap, drumMeta: drumMeta, instMeta: instMeta)
        } catch {
            print("❌ Snapshot copy failed: \(error)")
            return nil
        }
    }

    func generateCombinedAudioForStyleTransfer() -> URL? {
        guard let snap = snapshotCurrentLoopFiles() else {
            print("❌ Need both drum and instrument loops for style transfer")
            return nil
        }
        defer {
            try? FileManager.default.removeItem(at: snap.drum)
            try? FileManager.default.removeItem(at: snap.inst)
        }

        return createCombinedLoopedAudio(
            drumURL: snap.drum,
            instrumentURL: snap.inst,
            drumMetadata: snap.drumMeta,
            instrumentMetadata: snap.instMeta,
            targetDuration: 12.0
        )
    }
    
    /// Create combined looped audio with specified target duration
    func createCombinedLoopedAudio(
        drumURL: URL,
        instrumentURL: URL,
        drumMetadata: [String: Any],
        instrumentMetadata: [String: Any],
        targetDuration: TimeInterval
    ) -> URL? {
        
        do {
            // Load both audio files
            let drumFile = try AVAudioFile(forReading: drumURL)
            let instrumentFile = try AVAudioFile(forReading: instrumentURL)
            
            // Get loop durations from metadata
            let drumDuration = drumMetadata["loop_duration_seconds"] as? TimeInterval ??
                              (Double(drumFile.length) / drumFile.processingFormat.sampleRate)
            let instrumentDuration = instrumentMetadata["loop_duration_seconds"] as? TimeInterval ??
                                   (Double(instrumentFile.length) / instrumentFile.processingFormat.sampleRate)
            
            print("📊 Loop durations - Drums: \(String(format: "%.3f", drumDuration))s, Instruments: \(String(format: "%.3f", instrumentDuration))s")
            
            // Calculate the least common multiple duration where both loops align
            let lcmDuration = calculateLCMDuration(drumDuration, instrumentDuration)
            print("📊 LCM duration: \(String(format: "%.3f", lcmDuration))s")
            
            // Calculate how many times to repeat the LCM to fill target duration
            let lcmRepetitions = max(1, Int(ceil(targetDuration / lcmDuration)))
            let finalDuration = Double(lcmRepetitions) * lcmDuration
            
            print("📊 Final mixed duration: \(String(format: "%.3f", finalDuration))s (\(lcmRepetitions) x \(String(format: "%.3f", lcmDuration))s)")
            
            // Create combined audio
            let combinedURL = try mixAndLoopAudio(
                drumFile: drumFile,
                instrumentFile: instrumentFile,
                drumLoopDuration: drumDuration,
                instrumentLoopDuration: instrumentDuration,
                lcmDuration: lcmDuration,
                finalDuration: finalDuration
            )
            
            print("✅ Combined audio created: \(combinedURL.lastPathComponent)")
            return combinedURL
            
        } catch {
            print("❌ Failed to create combined audio: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Audio Processing Helpers
    
    private func calculateLCMDuration(_ duration1: TimeInterval, _ duration2: TimeInterval) -> TimeInterval {
        // Find LCM by finding the smallest duration where both loops align
        // We'll check multiples of each duration to find when they match
        
        let precision: TimeInterval = 0.001 // 1ms precision
        let maxIterations = 100
        
        var multiple1 = 1
        var multiple2 = 1
        
        for _ in 0..<maxIterations {
            let time1 = duration1 * Double(multiple1)
            let time2 = duration2 * Double(multiple2)
            
            if abs(time1 - time2) < precision {
                return time1
            } else if time1 < time2 {
                multiple1 += 1
            } else {
                multiple2 += 1
            }
        }
        
        // Fallback: use the longer of the two durations
        return max(duration1, duration2)
    }
    
    private func mixAndLoopAudio(
        drumFile: AVAudioFile,
        instrumentFile: AVAudioFile,
        drumLoopDuration: TimeInterval,
        instrumentLoopDuration: TimeInterval,
        lcmDuration: TimeInterval,
        finalDuration: TimeInterval
    ) throws -> URL {
        
        // Use the higher sample rate of the two files
        let sampleRate = max(drumFile.processingFormat.sampleRate, instrumentFile.processingFormat.sampleRate)
        let channelCount: UInt32 = 2 // Stereo output
        
        // Create output format
        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channelCount
        ) else {
            throw NSError(domain: "AudioMixing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"])
        }
        
        // Calculate buffer sizes
        let lcmFrameCount = AVAudioFrameCount(lcmDuration * sampleRate)
        let finalFrameCount = AVAudioFrameCount(finalDuration * sampleRate)
        
        // Create buffers
        guard let lcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: lcmFrameCount),
              let finalBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: finalFrameCount) else {
            throw NSError(domain: "AudioMixing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio buffers"])
        }
        
        // Create the LCM segment by mixing drum and instrument repetitions
        try createLCMSegment(
            drumFile: drumFile,
            instrumentFile: instrumentFile,
            drumLoopDuration: drumLoopDuration,
            instrumentLoopDuration: instrumentLoopDuration,
            lcmDuration: lcmDuration,
            outputBuffer: lcmBuffer,
            outputFormat: outputFormat
        )
        
        // Loop the LCM segment to fill the final duration
        try loopSegmentToFillDuration(
            sourceBuffer: lcmBuffer,
            outputBuffer: finalBuffer,
            lcmDuration: lcmDuration,
            finalDuration: finalDuration
        )
        
        // Save to temporary file
        let tempURL = createTempAudioURL()
        let outputFile = try AVAudioFile(forWriting: tempURL, settings: outputFormat.settings)
        try outputFile.write(from: finalBuffer)
        
        return tempURL
    }
    
    private func createLCMSegment(
        drumFile: AVAudioFile,
        instrumentFile: AVAudioFile,
        drumLoopDuration: TimeInterval,
        instrumentLoopDuration: TimeInterval,
        lcmDuration: TimeInterval,
        outputBuffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat
    ) throws {
        
        let sampleRate = outputFormat.sampleRate
        let lcmFrameCount = AVAudioFrameCount(lcmDuration * sampleRate)
        
        // Calculate how many repetitions of each loop we need
        let drumReps = Int(round(lcmDuration / drumLoopDuration))
        let instrumentReps = Int(round(lcmDuration / instrumentLoopDuration))
        
        print("📊 Creating LCM segment: \(drumReps) drum reps, \(instrumentReps) instrument reps")
        
        // Load and convert drum audio
        let drumBuffer = try loadAndConvertAudio(drumFile, toFormat: outputFormat, repetitions: drumReps, originalDuration: drumLoopDuration)
        
        // Load and convert instrument audio
        let instrumentBuffer = try loadAndConvertAudio(instrumentFile, toFormat: outputFormat, repetitions: instrumentReps, originalDuration: instrumentLoopDuration)
        
        // Mix the two buffers together
        outputBuffer.frameLength = lcmFrameCount
        
        guard let outputLeftChannel = outputBuffer.floatChannelData?[0],
              let outputRightChannel = outputBuffer.floatChannelData?[1],
              let drumLeftChannel = drumBuffer.floatChannelData?[0],
              let drumRightChannel = drumBuffer.format.channelCount > 1 ? drumBuffer.floatChannelData?[1] : drumBuffer.floatChannelData?[0],
              let instrumentLeftChannel = instrumentBuffer.floatChannelData?[0],
              let instrumentRightChannel = instrumentBuffer.format.channelCount > 1 ? instrumentBuffer.floatChannelData?[1] : instrumentBuffer.floatChannelData?[0] else {
            throw NSError(domain: "AudioMixing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to access audio channel data"])
        }
        
        let framesToMix = min(lcmFrameCount, min(drumBuffer.frameLength, instrumentBuffer.frameLength))
        
        // Mix with equal weighting (0.5 each to prevent clipping)
        for i in 0..<Int(framesToMix) {
            outputLeftChannel[i] = (drumLeftChannel[i] * 0.5) + (instrumentLeftChannel[i] * 0.5)
            outputRightChannel[i] = (drumRightChannel[i] * 0.5) + (instrumentRightChannel[i] * 0.5)
        }
        
        print("✅ Mixed \(framesToMix) frames for LCM segment")
    }
    
    private func loadAndConvertAudio(
        _ file: AVAudioFile,
        toFormat outputFormat: AVAudioFormat,
        repetitions: Int,
        originalDuration: TimeInterval
    ) throws -> AVAudioPCMBuffer {
        
        let originalFrameCount = AVAudioFrameCount(originalDuration * file.processingFormat.sampleRate)
        let totalFrameCount = originalFrameCount * UInt32(repetitions)
        
        // Read original audio
        guard let originalBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: originalFrameCount) else {
            throw NSError(domain: "AudioMixing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create original buffer"])
        }
        
        file.framePosition = 0
        try file.read(into: originalBuffer)
        
        // Convert to output format if needed
        let convertedOriginal: AVAudioPCMBuffer
        if file.processingFormat.sampleRate != outputFormat.sampleRate {
            guard let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
                throw NSError(domain: "AudioMixing", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"])
            }
            
            let convertedFrameCount = AVAudioFrameCount(originalDuration * outputFormat.sampleRate)
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: convertedFrameCount) else {
                throw NSError(domain: "AudioMixing", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to create converted buffer"])
            }
            
            try converter.convert(to: convertedBuffer, from: originalBuffer)
            convertedOriginal = convertedBuffer
        } else {
            // If same format, convert channels if needed
            if file.processingFormat.channelCount == outputFormat.channelCount {
                convertedOriginal = originalBuffer
            } else {
                convertedOriginal = try convertChannels(originalBuffer, toFormat: outputFormat)
            }
        }
        
        // Create repeated buffer
        let repeatedFrameCount = convertedOriginal.frameLength * UInt32(repetitions)
        guard let repeatedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: repeatedFrameCount) else {
            throw NSError(domain: "AudioMixing", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to create repeated buffer"])
        }
        
        // Copy the original buffer multiple times
        repeatedBuffer.frameLength = repeatedFrameCount
        
        for rep in 0..<repetitions {
            let startFrame = Int(convertedOriginal.frameLength) * rep
            let framesToCopy = Int(convertedOriginal.frameLength)
            
            for channel in 0..<Int(outputFormat.channelCount) {
                if let sourceChannel = convertedOriginal.floatChannelData?[channel],
                   let destChannel = repeatedBuffer.floatChannelData?[channel] {
                    memcpy(&destChannel[startFrame], sourceChannel, framesToCopy * MemoryLayout<Float>.size)
                }
            }
        }
        
        return repeatedBuffer
    }
    
    private func convertChannels(_ buffer: AVAudioPCMBuffer, toFormat outputFormat: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: buffer.frameLength) else {
            throw NSError(domain: "AudioMixing", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create channel conversion buffer"])
        }
        
        outputBuffer.frameLength = buffer.frameLength
        
        if buffer.format.channelCount == 1 && outputFormat.channelCount == 2 {
            // Mono to stereo - duplicate the mono channel
            if let sourceChannel = buffer.floatChannelData?[0],
               let leftChannel = outputBuffer.floatChannelData?[0],
               let rightChannel = outputBuffer.floatChannelData?[1] {
                memcpy(leftChannel, sourceChannel, Int(buffer.frameLength) * MemoryLayout<Float>.size)
                memcpy(rightChannel, sourceChannel, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        } else if buffer.format.channelCount == 2 && outputFormat.channelCount == 1 {
            // Stereo to mono - average the channels
            if let leftChannel = buffer.floatChannelData?[0],
               let rightChannel = buffer.floatChannelData?[1],
               let outputChannel = outputBuffer.floatChannelData?[0] {
                for i in 0..<Int(buffer.frameLength) {
                    outputChannel[i] = (leftChannel[i] + rightChannel[i]) * 0.5
                }
            }
        }
        
        return outputBuffer
    }
    
    private func loopSegmentToFillDuration(
        sourceBuffer: AVAudioPCMBuffer,
        outputBuffer: AVAudioPCMBuffer,
        lcmDuration: TimeInterval,
        finalDuration: TimeInterval
    ) throws {
        
        let repetitions = Int(ceil(finalDuration / lcmDuration))
        let finalFrameCount = AVAudioFrameCount(finalDuration * sourceBuffer.format.sampleRate)
        
        outputBuffer.frameLength = finalFrameCount
        
        for rep in 0..<repetitions {
            let startFrame = Int(sourceBuffer.frameLength) * rep
            let framesToCopy = min(Int(sourceBuffer.frameLength), Int(finalFrameCount) - startFrame)
            
            if framesToCopy <= 0 { break }
            
            for channel in 0..<Int(sourceBuffer.format.channelCount) {
                if let sourceChannel = sourceBuffer.floatChannelData?[channel],
                   let destChannel = outputBuffer.floatChannelData?[channel] {
                    memcpy(&destChannel[startFrame], sourceChannel, framesToCopy * MemoryLayout<Float>.size)
                }
            }
        }
        
        print("✅ Looped segment \(repetitions) times to fill \(String(format: "%.3f", finalDuration))s")
    }
    
    private func createTempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "combined_loop_\(Int(Date().timeIntervalSince1970)).wav"
        return tempDir.appendingPathComponent(filename)
    }
}
