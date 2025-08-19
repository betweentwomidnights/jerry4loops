//
//  BeatPrompts.swift
//  jerry-for-loops
//
//  Created by Kevin Griffing on 6/17/25.
//


import Foundation

struct BeatPrompts {
    
    // MARK: - Genre-Based Prompts (kept original)
    static let genrePrompts = [
        // Hip-hop
        "trap beat", "boom bap hip hop", "UK drill beat", "old school hip hop",
        "lo-fi hip hop", "jazz hip hop", "phonk beat", "drill beat",
        "cloud rap beat", "underground hip hop",
        
        // EDM/Electronic
        "house beat", "deep house", "tech house", "progressive house",
        "techno beat", "minimal techno", "acid techno", "drum and bass",
        "liquid drum and bass", "neurofunk", "dubstep beat", "future bass",
        "trap EDM", "garage beat", "UK garage", "trance beat",
        "progressive trance", "psytrance", "ambient techno", "breakbeat",
        "big beat", "jungle beat", "hardcore techno", "gabber beat",
        "synthwave", "chillwave", "downtempo", "trip-hop", "glitch hop",
        "electro funk",
    ]
    
    // MARK: - Drum-Specific Descriptors (NEW - Heavy Focus)
    static let drumDescriptors = [
        "crispy drums", "punchy drums", "hard-hitting drums",
        "vintage drums", "analog drums", "digital drums",
        "compressed drums", "reverb drums", "dry drums",
        "filtered drums", "pitched drums", "chopped drums",
        "layered drums", "minimal drums", "complex drums",
        "bouncy drums", "tight drums", "loose drums",
        "heavy drums", "light drums", "driving drums",
        "snappy drums", "booming drums", "clean drums",
        "gritty drums", "warm drums", "cold drums",
        "fat drums", "thin drums", "wide drums"
    ]
    
    // MARK: - Drum Techniques (NEW)
    static let drumTechniques = [
        "side-chained", "compressed", "saturated",
        "bit-crushed", "filtered", "pitched down",
        "pitched up", "reversed", "chopped", "stuttered",
        "gated", "distorted", "overdrive", "tape-saturated"
    ]
    
    // MARK: - Specific Drum Elements (NEW)
    static let drumElements = [
        "kick pattern", "snare hits", "hi-hat rolls",
        "808 slides", "rim shots", "clap pattern",
        "cymbal crashes", "tom fills", "percussion loop",
        "drum fills", "beat drops", "drum breaks"
    ]
    
    // MARK: - Simple Drum-Focused Prompts (ENHANCED)
    static let simpleDrumPrompts = [
        "hard drums", "soft drums", "punchy beat", "bouncy rhythm",
        "driving beat", "laid-back drums", "aggressive drums", "smooth beat",
        "tight rhythm", "loose groove", "minimal drums", "complex beat",
        "simple rhythm", "drum loop", "beat pattern", "percussion"
    ]
    
    // MARK: - Original categories (kept for compatibility)
    static let rhythmPrompts = [
        "syncopated drum pattern", "straight drum beat", "polyrhythmic drums",
        "shuffle rhythm", "half-time drums", "double-time beat",
        "triplet groove", "ghost note pattern", "tight drum programming",
        "loose drum feel", "quantized drums", "swing drums",
        "four-on-the-floor", "breakbeat pattern", "complex rhythm"
    ]
    
    static let instrumentationPrompts = [
        "808 drums", "analog drums", "live drums", "vintage drums",
        "electronic drums", "trap 808s", "heavy 808 bass", "punchy kick drum",
        "crisp snare", "vinyl samples", "jazz samples", "soul samples",
        "orchestral samples", "synthesizer bass", "analog synth"
    ]
    
    static let productionPrompts = [
        "heavy compression", "analog warmth", "digital crisp", "vinyl crackle",
        "tape saturation", "clean production", "gritty texture", "reverb-heavy",
        "dry mix", "stereo-wide", "mono drums", "distorted drums",
        "filtered drums", "pitched drums", "chopped samples"
    ]
    
    // MARK: - All Prompts Combined
    static let allPrompts = genrePrompts + drumDescriptors + drumTechniques +
                           drumElements + simpleDrumPrompts + rhythmPrompts +
                           instrumentationPrompts + productionPrompts
    
    // MARK: - DRUM-FOCUSED Random Selection (MAIN METHOD)
    static func getRandomPrompt() -> String {
        let randomSeed = Int.random(in: 1...100)
        
        // 50% chance: Simple drum descriptor + genre
        if randomSeed <= 50 {
            let drumDesc = drumDescriptors.randomElement() ?? "punchy drums"
            let genre = genrePrompts.randomElement() ?? "hip hop"
            return "\(drumDesc) \(genre)"
        }
        // 25% chance: Technique + drum descriptor
        else if randomSeed <= 75 {
            let technique = drumTechniques.randomElement() ?? "compressed"
            let drumDesc = drumDescriptors.randomElement() ?? "drums"
            return "\(technique) \(drumDesc)"
        }
        // 15% chance: Genre + specific drum element
        else if randomSeed <= 90 {
            let genre = genrePrompts.randomElement() ?? "trap"
            let element = drumElements.randomElement() ?? "kick pattern"
            return "\(genre) \(element)"
        }
        // 10% chance: Complex combination (3 elements)
        else {
            let technique = drumTechniques.randomElement() ?? "compressed"
            let genre = genrePrompts.randomElement() ?? "hip hop"
            let drumDesc = drumDescriptors.randomElement() ?? "drums"
            return "\(technique) \(genre) \(drumDesc)"
        }
    }
    
    // MARK: - Fallback method (always ensures drums)
    static func getRandomDrumPrompt() -> String {
        let basePrompt = getRandomPrompt()
        
        // If prompt doesn't contain drum-related words, append one
        let drumWords = ["drum", "beat", "kick", "snare", "808", "percussion"]
        let containsDrumWord = drumWords.contains { basePrompt.lowercased().contains($0) }
        
        if !containsDrumWord {
            let drumEnder = ["drums", "beat", "percussion"].randomElement() ?? "drums"
            return "\(basePrompt) \(drumEnder)"
        }
        
        return basePrompt
    }
    
    // MARK: - Category-Specific Random Selection (UPDATED)
    static func getRandomPrompt(from category: PromptCategory) -> String {
        switch category {
        case .genre:
            return genrePrompts.randomElement() ?? "hip hop beat"
        case .rhythm:
            return rhythmPrompts.randomElement() ?? "drum pattern"
        case .instrumentation:
            return instrumentationPrompts.randomElement() ?? "808 drums"
        case .production:
            return productionPrompts.randomElement() ?? "analog warmth"
        case .hybrid:
            return getRandomPrompt() // Use new drum-focused logic
        case .simple:
            return simpleDrumPrompts.randomElement() ?? "punchy beat"
        case .drums: // NEW category
            return drumDescriptors.randomElement() ?? "punchy drums"
        case .all:
            return getRandomDrumPrompt() // Always ensure drums
        }
    }
}

// MARK: - Prompt Categories Enum (UPDATED)
enum PromptCategory: CaseIterable {
    case genre
    case rhythm
    case instrumentation
    case production
    case hybrid
    case simple
    case drums // NEW
    case all
    
    var displayName: String {
        switch self {
        case .genre: return "Genre"
        case .rhythm: return "Rhythm"
        case .instrumentation: return "Instruments"
        case .production: return "Production"
        case .hybrid: return "Hybrid"
        case .simple: return "Simple"
        case .drums: return "Drums" // NEW
        case .all: return "All"
        }
    }
}
