import Foundation

// Data structure for saved loop info - shared across the app
struct SavedLoopInfo {
    let metadataURL: URL
    let metadata: [String: Any]
    
    var audioURL: URL {
        let audioFilename = metadata["savedFilename"] as? String ?? ""
        return metadataURL.deletingLastPathComponent().appendingPathComponent(audioFilename)
    }
    
    var userGivenName: String {
        return metadata["userGivenName"] as? String ?? "Unnamed Loop"
    }
    
    var originalPrompt: String {
        return metadata["original_prompt"] as? String ?? ""
    }
    
    var detectedBPM: Int {
        // Try multiple locations for BPM
        if let detectedBPM = metadata["detected_bpm"] as? Int {
            return detectedBPM
        } else if let bpm = metadata["bpm"] as? Int {
            return bpm
        } else if let nestedMetadata = metadata["metadata"] as? [String: Any],
                  let detectedBPM = nestedMetadata["detected_bpm"] as? Int {
            return detectedBPM
        }
        return 120 // fallback
    }
    
    var bars: Int {
        return metadata["bars"] as? Int ?? 1
    }
    
    var loopType: String {
        return metadata["loopType"] as? String ?? "unknown"
    }
    
    var duration: Double {
        return metadata["loop_duration_seconds"] as? Double ?? 0.0
    }
    
    var seed: Int {
        return metadata["seed"] as? Int ?? -1
    }
    
    // Enhanced prompt (with BPM appended)
    var enhancedPrompt: String {
        return metadata["prompt"] as? String ?? ""
    }
    
    // Negative prompt if any
    var negativePrompt: String {
        return metadata["negative_prompt"] as? String ?? ""
    }
    
    // Generation parameters
    var steps: Int {
        return metadata["steps"] as? Int ?? 8
    }
    
    var cfgScale: Double {
        return metadata["cfg_scale"] as? Double ?? 1.0
    }
    
    // Timestamps
    var savedTimestamp: Int {
        return metadata["savedTimestamp"] as? Int ?? 0
    }
    
    var generationTime: Double {
        return metadata["generation_time"] as? Double ?? 0.0
    }
    
    // Convenience computed properties
    var isInstrument: Bool {
        return loopType.lowercased().contains("instrument")
    }
    
    var isDrum: Bool {
        return loopType.lowercased().contains("drum")
    }
    
    var displayName: String {
        // Return user name, fallback to original prompt if no user name
        if !userGivenName.isEmpty && userGivenName != "Unnamed Loop" {
            return userGivenName
        } else if !originalPrompt.isEmpty {
            return originalPrompt
        } else {
            return "Loop \(savedTimestamp)"
        }
    }
    
    var shortDisplayName: String {
        // Truncated version for UI slots
        let name = displayName
        if name.count > 20 {
            return String(name.prefix(17)) + "..."
        }
        return name
    }
}
