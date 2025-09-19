//
//  MagentaPrompts.swift
//  jerry_for_loops
//
//  Upgraded “dice” logic: concise, descriptive styles (1–3 words).
//

import Foundation

struct MagentaPrompts {

    // MARK: - Base Style Pools (kept from your original, lightly edited)

    // Instruments stay broad — the richness comes from descriptors below.
    static let instruments = [
        "electric guitar","acoustic guitar","flamenco guitar","bass guitar",
        "electric piano","grand piano","synth lead","synth arpeggio",
        "violin","cello","trumpet","saxophone","clarinet",
        "drums","808 drums","live drums",
        "strings","brass section","hammond organ","wurlitzer","moog bass","analog synth"
    ]

    // Vibes — we’ll sometimes add a tiny rhythmic/scene descriptor.
    static let vibes = [
        "warmup","afterglow","sunrise","midnight","dusk","twilight","daybreak","nocturne","aurora","ember",
        "neon","chrome","velvet","glass","granite","desert","oceanic","skyline","underground","warehouse",
        "dreamy","nostalgic","moody","uplifting","mysterious","energetic","chill","dark","bright","atmospheric",
        "spacey","groovy","ethereal","glitchy","dusty","tape","vintage","hazy","crystalline","shimmer",
        "magnetic","luminous","starlit","shadow","hollow","smolder","static","drift","bloom","horizon"
    ]

    // Keep a coarse genre list for coverage, but avoid pure "jazz" in random rolls.
    static let genres = [
        "synthwave","death metal","lofi hiphop","acid house","techno","ambient",
        "jazz","blues","rock","pop","electronic","hip hop","reggae","folk",
        "classical","funk","soul","disco","dubstep","drum and bass","trance","garage"
    ]

    // Micro-genres & tight idioms that models tend to know well (western/electronic-leaning).
    static let microGenres = [
        "breakbeat","boom bap","uk garage","two step","dub techno","deep house",
        "lofi house","minimal techno","progressive house","psytrance","goa",
        "liquid dnb","neurofunk","glitch hop","idm","electro","footwork",
        "phonk","dark trap","hyperpop","darksynth","chillwave","vaporwave","future garage"
    ]

    // Short qualifiers to shape a base genre when we don’t use a microGenre.
    static let genreQualifiers = ["deep","dub","dark","melodic","minimal","uplifting","lofi","industrial","retro","neo"]

    // Technique/playing descriptors — some are generic, many are instrument-specific below.
    static let genericTechniques = ["arpeggio","ostinato","staccato","legato","tremolo","harmonics","plucks","pad","chops"]

    // Map instrument → descriptors that make musical/production sense for that instrument.
    static let instrumentDescriptors: [String: [String]] = [
        "electric guitar": ["palm-muted","tremolo","shoegaze","chorused","lead","octave"],
        "acoustic guitar": ["fingerstyle","nylon","arpeggio","strummed"],
        "flamenco guitar": ["rasgueado","picado"],
        "bass guitar": ["slap","picked","sub","syncopated"],
        "moog bass": ["sub","resonant","rubbery"],
        "analog synth": ["pad","plucks","supersaw","arpeggio"],
        "synth lead": ["portamento","supersaw","mono"],
        "electric piano": ["rhodes","chorused","tine"],
        "wurlitzer": ["dirty","tremolo"],
        "grand piano": ["felt","upright","arpeggio"],
        "hammond organ": ["leslie","drawbar"],
        "strings": ["pizzicato","ostinato","legato"],
        "violin": ["pizzicato","legato","tremolo"],
        "cello": ["sul tasto","legato","pizzicato"],
        "trumpet": ["muted","harmon"],
        "saxophone": ["breathy","subtone"],
        "clarinet": ["staccato","legato"],
        "drums": ["brushed","breakbeat","rimshot"],
        "808 drums": ["808","trap"],
        "live drums": ["brushed","tight","roomy"],
        "brass section": ["stabs","swell"]
    ]

    // MARK: - Cycling State (unchanged)
    private static var currentCategoryIndex = 0
    enum StyleCategory: CaseIterable { case instrument, vibe, genre
        var displayName: String {
            switch self { case .instrument: "Instrument"; case .vibe: "Vibe"; case .genre: "Genre" }
        }
    }

    // MARK: - Public API (same signatures, richer outputs)

    /// instrument → vibe → genre → instrument...
    static func getNextCyclingStyle() -> String {
        let categories = StyleCategory.allCases
        let currentCategory = categories[currentCategoryIndex]
        currentCategoryIndex = (currentCategoryIndex + 1) % categories.count
        switch currentCategory {
        case .instrument: return getRandomInstrument()
        case .vibe:       return getRandomVibe()
        case .genre:      return getRandomGenre()
        }
    }

    static func getCurrentCategory() -> StyleCategory {
        StyleCategory.allCases[currentCategoryIndex]
    }

    // MARK: - Category Pickers (now “rich”)

    static func getRandomInstrument() -> String {
        let inst = instruments.randomElement() ?? "electric guitar"
        // 55% plain instrument, 45% instrument + descriptor
        if chance(0.45) {
            let specific = instrumentDescriptors[inst]?.randomElement()
            let tech = specific ?? genericTechniques.randomElement() ?? "arpeggio"
            return clippedWords([tech, inst])
        }
        return inst
    }

    static func getRandomVibe() -> String {
        vibes.randomElement() ?? "warmup"
    }

    static func getRandomGenre() -> String {
        // Prefer micro-genres most of the time; avoid pure “jazz” randomly as requested
        if chance(0.65) {
            return microGenres.randomElement() ?? "breakbeat"
        } else {
            var pool = genres.filter { $0.lowercased() != "jazz" } // keep user-typed jazz possible, but not dice-picked
            let base = pool.randomElement() ?? "electronic"
            // 30% add a qualifier in front (deep house, dub techno, etc.)
            if chance(0.30) {
                let q = genreQualifiers.randomElement() ?? "deep"
                return clippedWords([q, base])
            }
            return base
        }
    }

    // MARK: - Random (no cycling) / Weighted (unchanged behavior, richer under the hood)

    static func getRandomStyle() -> String {
        // draw from all three, but with rich category pickers
        let pick = Int.random(in: 0..<3)
        switch pick { case 0: return getRandomInstrument(); case 1: return getRandomVibe(); default: return getRandomGenre() }
    }

    /// 40% instruments, 30% vibes, 30% genres (category weights unchanged)
    static func getWeightedStyle() -> String {
        let r = Int.random(in: 1...100)
        if r <= 40 { return getRandomInstrument() }
        if r <= 70 { return getRandomVibe() }
        return getRandomGenre()
    }

    // Category selector unchanged
    static func getStyleFrom(category: StyleCategory) -> String {
        switch category { case .instrument: getRandomInstrument()
        case .vibe: getRandomVibe()
        case .genre: getRandomGenre() }
    }

    // MARK: - Utilities

    static func resetCycle() { currentCategoryIndex = 0 }

    static func getAllStyles(for category: StyleCategory) -> [String] {
        switch category { case .instrument: instruments; case .vibe: vibes; case .genre: genres }
    }

    /// Replace or insert into the styles array (used by your UI)
    static func randomizeStyleEntry(in styles: inout [MagentaConfig.StyleEntry]) {
        let newStyle = getNextCyclingStyle()
        if let idx = styles.firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            styles[idx].text = newStyle
        } else if !styles.isEmpty {
            styles[0].text = newStyle
        } else {
            styles.append(MagentaConfig.StyleEntry(text: newStyle, weight: 1.0))
        }
    }

    // MARK: - Private helpers

    private static func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < max(0,min(1,p)) }

    /// Joins words into a single style, clipping to at most 3 words.
    private static func clippedWords(_ words: [String], max: Int = 3) -> String {
        let tokens = words
            .flatMap { $0.split(separator: " ").map(String.init) }
            .prefix(max)
        return tokens.joined(separator: " ")
    }
}
