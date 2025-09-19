//
//  LoopAudioManager+SavedLoopsManagement.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 8/12/25.
//


import Foundation

// MARK: - LoopAudioManager Extension for Saved Loops Management
extension LoopAudioManager {
    
    struct LoopSnapshot {
            let tempURL: URL
            let metadata: [String: Any]
            let loopType: String   // "drums" or "instruments"
        }

        /// Copy the *current* loop to a temp file so it can't be replaced while the user types.
        func makeSnapshot(for loopType: LoopType) -> LoopSnapshot? {
            guard let pm = playerManager else { return nil }

            let srcURL: URL?
            let md: [String: Any]?
            let typeString: String

            switch loopType {
            case .drums:
                srcURL = pm.drumAudioURL
                md = pm.drumLoopMetadata
                typeString = "drums"
            case .instruments:
                srcURL = pm.instrumentAudioURL
                md = pm.instrumentLoopMetadata
                typeString = "instruments"
            }

            guard let source = srcURL, let metadata = md else { return nil }

            let fm = FileManager.default
            let base = fm.temporaryDirectory.appendingPathComponent("loop_save_snapshots", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            let dst = base.appendingPathComponent("\(UUID().uuidString).wav")

            do {
                try fm.copyItem(at: source, to: dst)
                return LoopSnapshot(tempURL: dst, metadata: metadata, loopType: typeString)
            } catch {
                print("❌ Snapshot copy failed: \(error)")
                return nil
            }
        }

        /// Commit a previously captured snapshot under the user's chosen name.
        func commitSnapshot(_ snapshot: LoopSnapshot, withName name: String) {
            // Reuse our existing permanent save pipeline
            saveLoopPermanently(
                currentAudioURL: snapshot.tempURL,
                metadata: snapshot.metadata,
                userGivenName: name,
                loopType: snapshot.loopType
            )
            // Clean up the temp file
            try? FileManager.default.removeItem(at: snapshot.tempURL)
        }

        /// Discard (delete) a snapshot if the user cancels.
        func discardSnapshot(_ snapshot: LoopSnapshot) {
            try? FileManager.default.removeItem(at: snapshot.tempURL)
        }
    
    // MARK: - Permanent Save Methods

    func saveDrumLoopPermanently(withName name: String) {
        guard let currentDrumURL = playerManager?.drumAudioURL,
              let metadata = playerManager?.drumLoopMetadata else {
            print("❌ No current drum loop to save")
            return
        }
        
        saveLoopPermanently(
            currentAudioURL: currentDrumURL,
            metadata: metadata,
            userGivenName: name,
            loopType: "drums"
        )
    }

    func saveInstrumentLoopPermanently(withName name: String) {
        guard let currentInstrumentURL = playerManager?.instrumentAudioURL,
              let metadata = playerManager?.instrumentLoopMetadata else {
            print("❌ No current instrument loop to save")
            return
        }
        
        saveLoopPermanently(
            currentAudioURL: currentInstrumentURL,
            metadata: metadata,
            userGivenName: name,
            loopType: "instruments"
        )
    }

    private func saveLoopPermanently(
        currentAudioURL: URL,
        metadata: [String: Any],
        userGivenName: String,
        loopType: String
    ) {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        // Create saved_loops directory if it doesn't exist
        let savedLoopsDirectory = documentsDirectory.appendingPathComponent("saved_loops")
        
        do {
            if !fileManager.fileExists(atPath: savedLoopsDirectory.path) {
                try fileManager.createDirectory(at: savedLoopsDirectory, withIntermediateDirectories: true)
                print("✅ Created saved_loops directory")
            }
        } catch {
            print("❌ Failed to create saved_loops directory: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create save directory"
            }
            return
        }
        
        // Extract metadata for filename
        let detectedBPM = metadata["detected_bpm"] as? Int ?? 120
        let bars = metadata["bars"] as? Int ?? 1
        let timestamp = Int(Date().timeIntervalSince1970)
        
        // Create safe filename from user's name
        let safeUserName = userGivenName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create filename: "UserName_120bpm_4bars_timestamp"
        let baseFilename = "\(safeUserName)_\(detectedBPM)bpm_\(bars)bars_\(timestamp)"
        let audioFilename = "\(baseFilename).wav"
        let metadataFilename = "\(baseFilename).json"
        
        let savedAudioURL = savedLoopsDirectory.appendingPathComponent(audioFilename)
        let savedMetadataURL = savedLoopsDirectory.appendingPathComponent(metadataFilename)
        
        do {
            // Copy audio file to saved location
            if fileManager.fileExists(atPath: savedAudioURL.path) {
                try fileManager.removeItem(at: savedAudioURL)
            }
            try fileManager.copyItem(at: currentAudioURL, to: savedAudioURL)
            
            // Create clean metadata for JSON serialization (filter out URL objects and other non-serializable types)
            var cleanMetadata: [String: Any] = [:]
            
            // Copy only JSON-serializable values from original metadata
            for (key, value) in metadata {
                switch value {
                case let stringValue as String:
                    cleanMetadata[key] = stringValue
                case let intValue as Int:
                    cleanMetadata[key] = intValue
                case let doubleValue as Double:
                    cleanMetadata[key] = doubleValue
                case let boolValue as Bool:
                    cleanMetadata[key] = boolValue
                case let arrayValue as [Any]:
                    // Only include arrays if all elements are JSON-serializable
                    if JSONSerialization.isValidJSONObject(arrayValue) {
                        cleanMetadata[key] = arrayValue
                    }
                case let dictValue as [String: Any]:
                    // Only include dictionaries if they're JSON-serializable
                    if JSONSerialization.isValidJSONObject(dictValue) {
                        cleanMetadata[key] = dictValue
                    }
                default:
                    // Skip non-JSON-serializable types (like URLs)
                    print("⚠️ Skipping non-JSON-serializable metadata key: \(key) (type: \(type(of: value)))")
                }
            }
            
            // Add our additional metadata
            cleanMetadata["userGivenName"] = userGivenName
            cleanMetadata["savedTimestamp"] = timestamp
            cleanMetadata["savedFilename"] = audioFilename
            cleanMetadata["loopType"] = loopType
            
            // Convert clean metadata to JSON and save
            let jsonData = try JSONSerialization.data(withJSONObject: cleanMetadata, options: .prettyPrinted)
            try jsonData.write(to: savedMetadataURL)
            
            print("✅ Saved loop permanently:")
            print("   Audio: \(audioFilename)")
            print("   Metadata: \(metadataFilename)")
            print("   User Name: \(userGivenName)")
            print("   BPM: \(detectedBPM), Bars: \(bars)")
            
            // Show success message to user
            DispatchQueue.main.async {
                // You could add a success message state here if desired
                print("💾 Successfully saved '\(userGivenName)'")
            }
            
        } catch {
            print("❌ Failed to save loop permanently: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to save loop: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Edit / Delete Saved Loops
    func deleteSavedLoop(_ loop: SavedLoopInfo) {
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: loop.audioURL.path) {
                try fm.removeItem(at: loop.audioURL)
            }
            if fm.fileExists(atPath: loop.metadataURL.path) {
                try fm.removeItem(at: loop.metadataURL)
            }
            print("🗑️ Deleted saved loop: \(loop.displayName)")
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to delete loop: \(error.localizedDescription)"
            }
        }
    }

    func renameSavedLoop(_ loop: SavedLoopInfo, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let data = try Data(contentsOf: loop.metadataURL)
            guard var dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw NSError(domain: "Rename", code: 0, userInfo: [NSLocalizedDescriptionKey: "Bad metadata JSON"])
            }
            dict["userGivenName"] = trimmed

            let out = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
            try out.write(to: loop.metadataURL, options: .atomic)

            print("✏️ Renamed saved loop to: \(trimmed)")
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to rename: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Saved Loops Management

    /// Get all saved loops for a specific BPM (for the list component later)
    func getSavedLoops(forBPM bpm: Int) -> [SavedLoopInfo] {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let savedLoopsDirectory = documentsDirectory.appendingPathComponent("saved_loops")
        
        print("🔍 getSavedLoops: Looking for BPM \(bpm) in \(savedLoopsDirectory.path)")
        
        guard fileManager.fileExists(atPath: savedLoopsDirectory.path) else {
            print("🔍 getSavedLoops: saved_loops directory doesn't exist")
            return []
        }
        
        var savedLoops: [SavedLoopInfo] = []
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: savedLoopsDirectory, includingPropertiesForKeys: nil)
            let metadataFiles = contents.filter { $0.pathExtension == "json" }
            
            print("🔍 getSavedLoops: Found \(metadataFiles.count) JSON files")
            
            for metadataURL in metadataFiles {
                print("🔍 getSavedLoops: Processing \(metadataURL.lastPathComponent)")
                
                if let metadata = loadMetadata(from: metadataURL) {
                    print("🔍 getSavedLoops: Loaded metadata keys: \(metadata.keys.sorted())")
                    
                    // Check BPM filtering - try multiple locations
                    var loopBPM: Int? = nil
                    
                    // First try top-level "detected_bpm"
                    if let detectedBPM = metadata["detected_bpm"] as? Int {
                        loopBPM = detectedBPM
                        print("🔍 getSavedLoops: Found top-level detected_bpm=\(detectedBPM)")
                    }
                    // Then try top-level "bpm"
                    else if let bpmValue = metadata["bpm"] as? Int {
                        loopBPM = bpmValue
                        print("🔍 getSavedLoops: Found top-level bpm=\(bpmValue)")
                    }
                    // Finally try nested metadata object
                    else if let nestedMetadata = metadata["metadata"] as? [String: Any],
                            let detectedBPM = nestedMetadata["detected_bpm"] as? Int {
                        loopBPM = detectedBPM
                        print("🔍 getSavedLoops: Found nested detected_bpm=\(detectedBPM)")
                    }
                    
                    if let foundBPM = loopBPM {
                        print("🔍 getSavedLoops: Using BPM=\(foundBPM), comparing to target=\(bpm)")
                        if foundBPM == bpm {
                            let savedLoop = SavedLoopInfo(
                                metadataURL: metadataURL,
                                metadata: metadata
                            )
                            print("🔍 getSavedLoops: BPM match! loopType='\(savedLoop.loopType)', isDrum=\(savedLoop.isDrum), isInstrument=\(savedLoop.isInstrument)")
                            savedLoops.append(savedLoop)
                        } else {
                            print("🔍 getSavedLoops: BPM mismatch (\(foundBPM) != \(bpm))")
                        }
                    } else {
                        print("🔍 getSavedLoops: No BPM found anywhere in metadata")
                    }
                } else {
                    print("🔍 getSavedLoops: Failed to load metadata from \(metadataURL.lastPathComponent)")
                }
            }
            
            // Sort by saved timestamp (newest first)
            savedLoops.sort { loop1, loop2 in
                let timestamp1 = loop1.metadata["savedTimestamp"] as? Int ?? 0
                let timestamp2 = loop2.metadata["savedTimestamp"] as? Int ?? 0
                return timestamp1 > timestamp2
            }
            
            print("🔍 getSavedLoops: Final result: \(savedLoops.count) loops")
            
        } catch {
            print("❌ Failed to load saved loops: \(error)")
        }
        
        return savedLoops
    }

    private func loadMetadata(from url: URL) -> [String: Any]? {
        do {
            let data = try Data(contentsOf: url)
            let metadata = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            return metadata
        } catch {
            print("❌ Failed to load metadata from \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
