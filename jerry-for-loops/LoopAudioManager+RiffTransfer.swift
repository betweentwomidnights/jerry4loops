//
//  LoopAudioManager+RiffTransfer.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 8/12/25.
//


import Foundation
import AVFoundation

// MARK: - LoopAudioManager Extension for Riff Transfer
extension LoopAudioManager {
    
    // MARK: - Generic Riff Transfer Function
    private func generateRiffTransferLoop(
        prompt: String,
        key: String,
        bpm: Int,
        loopType: LoopType,
        styleStrength: Float = 0.8,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        guard startGeneration() else { return }
        
        print("\(loopType.generationEmoji) Starting \(loopType.displayName.lowercased()) riff transfer:")
        print("   Key: \(key)")
        print("   Target BPM: \(bpm)")
        print("   Prompt: \(prompt)")
        print("   Style strength: \(styleStrength)")
        
        // Build the prompt with BPM
        let finalPrompt = "\(prompt) \(bpm)bpm"
        
        // Create request URL - DIFFERENT ENDPOINT
        guard let url = URL(string: "\(backendURL)/generate/loop-with-riff") else {
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
        
        // Add form fields for riff transfer
        formData.addField(name: "prompt", value: finalPrompt)
        formData.addField(name: "key", value: key)  // <- KEY PARAMETER for riff transfer
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
        
        print("\(loopType.generationEmoji) Generating \(loopType.displayName.lowercased()) riff transfer: '\(finalPrompt)'")
        print("   Key: \(key), Style strength: \(styleStrength), Steps: \(steps), CFG: \(cfgScale), Seed: \(seed)")
        
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
                    // Try to parse error message from response
                    if let data = data,
                       let errorResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let errorMsg = errorResponse["error"] as? String {
                        self?.errorMessage = "API error: \(errorMsg)"
                    } else {
                        self?.errorMessage = "Server error: \(httpResponse.statusCode)"
                    }
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
                
                // Add riff transfer metadata
                var enhancedMetadata = metadata
                enhancedMetadata["isRiffTransfer"] = true
                enhancedMetadata["styleStrength"] = styleStrength
                enhancedMetadata["sourceKey"] = key
                enhancedMetadata["sourceType"] = "personal_riff_library"
                
                // Save with appropriate loop type
                self?.saveLoop(data: audioData, bpm: bpm, metadata: enhancedMetadata, loopType: loopType)
                
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse response: \(error.localizedDescription)"
                }
            }
            
        }.resume()
    }
    
    // MARK: - Public Riff Transfer Functions
    
    /// Generate a new instrument loop using riff transfer from personal riff library
    func generateInstrumentRiffTransfer(
        prompt: String,
        key: String,
        bpm: Int,
        styleStrength: Float = 0.8,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        generateRiffTransferLoop(
            prompt: prompt,
            key: key,
            bpm: bpm,
            loopType: .instruments,
            styleStrength: styleStrength,
            steps: steps,
            cfgScale: cfgScale,
            seed: seed,
            bars: bars
        )
    }

    /// Generate a new drum loop using riff transfer from personal riff library
    func generateDrumRiffTransfer(
        prompt: String,
        key: String,
        bpm: Int,
        styleStrength: Float = 0.8,
        steps: Int = 8,
        cfgScale: Double = 1.0,
        seed: Int = -1,
        bars: Int? = nil
    ) {
        generateRiffTransferLoop(
            prompt: prompt,
            key: key,
            bpm: bpm,
            loopType: .drums,
            styleStrength: styleStrength,
            steps: steps,
            cfgScale: cfgScale,
            seed: seed,
            bars: bars
        )
    }
}
