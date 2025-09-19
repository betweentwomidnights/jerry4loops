//
//  MagentaConfig.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 8/17/25.
//


import Foundation
import Combine

final class MagentaConfig: ObservableObject {
    struct StyleEntry: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var weight: Double
    }

    @Published var styles: [StyleEntry] = [StyleEntry(text: "", weight: 1.0)]
    @Published var loopWeight: Double = 1.0        // 0–1
    @Published var bars: Int = 4                   // 4 or 8
    @Published var temperature: Double = 1.2       // 0–4
    @Published var topK: Int = 30                  // 0–1024
    @Published var guidanceWeight: Double = 5.0    // 0–10
    
    // ── NEW: finetune steering state ─────────────────────────────────
        @Published var mean: Double = 1.0                // 0.0…2.0 like the Colab
        @Published var centroidWeights: [Double] = []    // length == centroidCount (0 if none)

        // Backend-reported asset status (read-only to UI)
        @Published private(set) var assetsRepo: String? = nil
        @Published private(set) var centroidCount: Int? = nil
        @Published private(set) var meanAvailable: Bool = false

        var assetsAvailable: Bool { (centroidCount ?? 0) > 0 || meanAvailable }

        // Compact UI helpers (so we don’t need 6 full sliders on small screens)
        @Published var compactCentroidIndex: Int = 0     // 0…K-1
        @Published var compactCentroidIntensity: Double = 0.0 // 0.0…2.0
        @Published var showAdvancedCentroids: Bool = false

        // CSV encoders for requests
        var centroidWeightsCSV: String { centroidWeights.map { String(format: "%.4f", $0) }.joined(separator: ",") }
        var stylesCSV: String { styles.map(\.text).joined(separator: ",") }
        var styleWeightsCSV: String { styles.map { String(format: "%.4f", $0.weight) }.joined(separator: ",") }

        // Match the /model/assets/status payload
        struct AssetsStatus: Decodable {
            let repo_id: String?
            let mean_loaded: Bool
            let centroids_loaded: Bool
            let centroid_count: Int?
            let embedding_dim: Int?
        }

        func applyAssetsStatus(_ s: AssetsStatus) {
            assetsRepo = s.repo_id
            meanAvailable = s.mean_loaded
            if s.centroids_loaded, let k = s.centroid_count, k > 0 {
                setCentroidCount(k)
            } else {
                setCentroidCount(0)
            }
        }

        func setCentroidCount(_ k: Int) {
            centroidCount = k
            if k <= 0 {
                centroidWeights = []
                compactCentroidIndex = 0
                compactCentroidIntensity = 0.0
                return
            }
            if centroidWeights.count != k {
                centroidWeights = Array(repeating: 0.0, count: k)
            }
            compactCentroidIndex = min(max(compactCentroidIndex, 0), k - 1)
        }

        /// Call this when the user tweaks the compact controls so weights reflect that choice.
    func applyCompactMixer() {
        guard let k = centroidCount, k > 0 else { return }
        if centroidWeights.count != k {
            centroidWeights = Array(repeating: 0.0, count: k)
        }
        // Only touch the selected centroid — leave others as-is
        centroidWeights[compactCentroidIndex] = compactCentroidIntensity
    }
    
    func selectCompactCentroid(_ idx: Int) {
        guard let k = centroidCount, k > 0 else { return }
        compactCentroidIndex = min(max(idx, 0), k - 1)
        if centroidWeights.count != k {
            centroidWeights = Array(repeating: 0.0, count: k)
        }
        // Pull the remembered weight into the compact slider
        compactCentroidIntensity = centroidWeights[compactCentroidIndex]
    }


    // Seed from a PendingJamRequest (so MagentaConfigPopup knows the session params)
    func apply(pending req: LoopAudioManager.PendingJamRequest) {
        styles = zip(req.styles, req.styleWeights).map { StyleEntry(text: $0.0, weight: $0.1) }
        loopWeight = req.loopWeight
        bars = req.barsPerChunk
        temperature = req.temperature
        topK = req.topK
        guidanceWeight = req.guidanceWeight
    }

    // Build a PendingJamRequest (useful if you want to re-start with current settings)
    func toPending(bpm: Int) -> LoopAudioManager.PendingJamRequest {
        .init(
            bpm: bpm,
            barsPerChunk: bars,
            styles: styles.map(\.text),
            styleWeights: styles.map(\.weight),
            loopWeight: loopWeight,
            temperature: temperature,
            topK: topK,
            guidanceWeight: guidanceWeight
        )
    }
}
