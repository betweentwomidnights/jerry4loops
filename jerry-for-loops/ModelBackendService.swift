//
//  ModelBackendService.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 9/14/25.
//

import Foundation

// --- Shared wire models ---
struct ModelConfigResponse: Codable {
    let size: String
    let repo: String?
    let revision: String
    let selected_step: String?
    let assets_repo: String?
    let loaded: Bool
    let active_jam: Bool
    let local_checkpoint_dir: String?
    let mean_loaded: Bool
    let centroids_loaded: Bool
    let centroid_count: Int?
    let warmup_done: Bool
}

struct ModelCheckpointsResponse: Codable {
    let repo: String
    let revision: String
    let steps: [Int]
    let latest: Int?
}

struct ModelSelectReq: Codable {
    var size: String?
    var repo_id: String?
    var revision: String? = "main"
    var step: String?     // "none" | "latest" | "1863001"
    var assets_repo_id: String?
    var sync_assets: Bool? = true
    var prewarm: Bool? = false
    var stop_active: Bool? = true
    var dry_run: Bool? = false
}

struct ModelSelectResp: Codable {
    let ok: Bool
    let dry_run: Bool?
    let target_size: String
    let target_repo: String?
    let target_revision: String?
    let target_step: Int?
    let assets_repo: String?
    let active_jam: Bool
}

// --- Shared service ---
@MainActor
final class ModelService: ObservableObject {
    // Shared key + default so we stay in sync with LoopAudioManager and StudioMenuPanel
    static let defaultsKey = "magenta_base_url"
    static let defaultBaseURL = "https://thecollabagepatch-magenta-retry.hf.space"

    /// Human-editable value shown in UI (always normalized on set)
    @Published var baseURL: String {
        didSet {
            let normalized = Self.normalize(baseURL)
            if normalized != baseURL {
                // Re-assign once with the normalized string, then persist on the next didSet
                baseURL = normalized
                return
            }
            UserDefaults.standard.set(normalized, forKey: Self.defaultsKey)
        }
    }

    init(baseURL: String? = nil) {
        let seed = baseURL
            ?? UserDefaults.standard.string(forKey: Self.defaultsKey)
            ?? Self.defaultBaseURL
        self.baseURL = Self.normalize(seed)
    }

    // MARK: - Normalization & URL building

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private var base: URL {
        // safe unwrap; we normalize on set/init
        URL(string: baseURL)!
    }

    private func makeURL(_ path: String, queryItems: [URLQueryItem]? = nil) -> URL {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let qi = queryItems, !qi.isEmpty { comps.queryItems = qi }
        return comps.url!
    }

    // MARK: - API calls (unchanged signatures)

    func getHealth() async -> (ok: Bool, message: String) {
        do {
            let url = makeURL("health")
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (false, "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1) from /health")
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ok = obj["ok"] as? Bool, ok {
                return (true, "Online")
            }
            return (false, "Unexpected /health payload")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    func getConfig() async throws -> ModelConfigResponse {
        let url = makeURL("model/config")
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ModelConfigResponse.self, from: data)
    }

    func getCheckpoints(repo: String, revision: String) async throws -> ModelCheckpointsResponse {
        let qi = [
            URLQueryItem(name: "repo_id", value: repo),
            URLQueryItem(name: "revision", value: revision)
        ]
        let url = makeURL("model/checkpoints", queryItems: qi)
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ModelCheckpointsResponse.self, from: data)
    }

    func selectModel(_ req: ModelSelectReq) async throws -> ModelSelectResp {
        let url = makeURL("model/select")
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.addValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(req)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "ModelService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return try JSONDecoder().decode(ModelSelectResp.self, from: data)
    }
}

