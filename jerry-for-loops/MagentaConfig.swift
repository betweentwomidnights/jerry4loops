//
//  MagentaConfig.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 8/17/25.
//


import Foundation

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
    @Published var guidanceWeight: Double = 1.5    // 0–10

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
