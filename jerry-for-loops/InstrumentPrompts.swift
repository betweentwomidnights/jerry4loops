//
//  InstrumentPrompts.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 6/18/25.
//

import Foundation

struct InstrumentPrompts {
    
    // MARK: - Verified Base Genres (Tested & Reliable)
    static let verifiedBaseGenres = [
        "aggressive techno",
        "ambient electronic",
        "experimental electronic",
        "future bass",
        "liquid dnb",
        "synthwave",
        "chillwave",
        "neurofunk",
        "drone",
        "melodic dubstep"
    ]
    
    // MARK: - Standalone Reliable Prompts
    static let standalonePrompts = [
        "aggressive techno",
        "melodic rap",
        "ambient electronic",
        "ethereal",
        "experimental electronic",
        "future bass",
        "synthwave",
        "chillwave",
        "melodic dubstep"
    ]
    
    // MARK: - Instrument Descriptors (Append to Base Genres)
    static let instrumentDescriptors = [
        "bass",
        "chords",
        "melody",
        "pads"
    ]
    
    // MARK: - Verified Combinations (Pre-tested)
    static let verifiedCombinations = [
        "drone bass",
        "neurofunk bass",
        "liquid dnb chords",
        "liquid dnb melody",
        "chillwave chords",
        "chillwave pads"
    ]
    
    // MARK: - MAIN GENERATION METHOD
    static func getRandomGenrePrompt() -> String {
        let randomSeed = Int.random(in: 1...100)
        
        // 40% chance: Use verified standalone prompts
        if randomSeed <= 40 {
            return standalonePrompts.randomElement() ?? "aggressive techno"
        }
        // 35% chance: Use verified combinations
        else if randomSeed <= 75 {
            return verifiedCombinations.randomElement() ?? "drone bass"
        }
        // 25% chance: Create base genre + descriptor combination
        else {
            let baseGenre = verifiedBaseGenres.randomElement() ?? "synthwave"
            let descriptor = instrumentDescriptors.randomElement() ?? "melody"
            return "\(baseGenre) \(descriptor)"
        }
    }
    
    // MARK: - Category-Specific Selection
    static func getRandomPrompt(from category: GenreCategory) -> String {
        switch category {
        case .standalone:
            return standalonePrompts.randomElement() ?? "aggressive techno"
        case .bass:
            let bassPrompts = verifiedCombinations.filter { $0.contains("bass") } +
                             verifiedBaseGenres.map { "\($0) bass" }
            return bassPrompts.randomElement() ?? "drone bass"
        case .chords:
            let chordPrompts = verifiedCombinations.filter { $0.contains("chords") } +
                              verifiedBaseGenres.map { "\($0) chords" }
            return chordPrompts.randomElement() ?? "liquid dnb chords"
        case .melody:
            let melodyPrompts = verifiedCombinations.filter { $0.contains("melody") } +
                               verifiedBaseGenres.map { "\($0) melody" }
            return melodyPrompts.randomElement() ?? "liquid dnb melody"
        case .pads:
            let padPrompts = verifiedCombinations.filter { $0.contains("pads") } +
                            verifiedBaseGenres.map { "\($0) pads" }
            return padPrompts.randomElement() ?? "chillwave pads"
        case .all:
            return getRandomGenrePrompt()
        }
    }
    
    // MARK: - Weighted Selection (Prioritizes Proven Prompts)
    static func getWeightedGenrePrompt() -> String {
        let randomSeed = Int.random(in: 1...100)
        
        // 50% chance: Verified combinations (highest reliability)
        if randomSeed <= 50 {
            return verifiedCombinations.randomElement() ?? "drone bass"
        }
        // 35% chance: Standalone reliable prompts
        else if randomSeed <= 85 {
            return standalonePrompts.randomElement() ?? "aggressive techno"
        }
        // 15% chance: Generate new combination from verified parts
        else {
            let baseGenre = verifiedBaseGenres.randomElement() ?? "synthwave"
            let descriptor = instrumentDescriptors.randomElement() ?? "melody"
            return "\(baseGenre) \(descriptor)"
        }
    }
    
    // MARK: - Target Specific Instrument Types
    static func getBassPrompt() -> String {
        let bassOptions = ["drone bass", "neurofunk bass"] +
                         verifiedBaseGenres.map { "\($0) bass" }
        return bassOptions.randomElement() ?? "drone bass"
    }
    
    static func getChordsPrompt() -> String {
        let chordOptions = ["liquid dnb chords", "chillwave chords"] +
                          verifiedBaseGenres.map { "\($0) chords" }
        return chordOptions.randomElement() ?? "liquid dnb chords"
    }
    
    static func getMelodyPrompt() -> String {
        let melodyOptions = ["liquid dnb melody"] +
                           verifiedBaseGenres.map { "\($0) melody" }
        return melodyOptions.randomElement() ?? "liquid dnb melody"
    }
    
    static func getPadsPrompt() -> String {
        let padOptions = ["chillwave pads"] +
                        verifiedBaseGenres.map { "\($0) pads" }
        return padOptions.randomElement() ?? "chillwave pads"
    }
    
    // MARK: - Legacy Method (For Compatibility)
    static func getCleanInstrumentPrompt() -> String {
        // Use weighted selection for maximum reliability
        return getWeightedGenrePrompt()
    }
}

// MARK: - Genre Categories Enum
enum GenreCategory: CaseIterable {
    case standalone
    case bass
    case chords
    case melody
    case pads
    case all
    
    var displayName: String {
        switch self {
        case .standalone: return "Standalone"
        case .bass: return "Bass"
        case .chords: return "Chords"
        case .melody: return "Melody"
        case .pads: return "Pads"
        case .all: return "All"
        }
    }
}
