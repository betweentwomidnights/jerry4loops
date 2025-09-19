//
//  RecordingLibrary.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 9/14/25.
//


import AVFoundation
import SwiftUI

final class RecordingLibrary: ObservableObject {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let name: String
        let duration: TimeInterval
        let sizeBytes: Int
        let modified: Date
    }

    @Published var items: [Item] = []

    private func docsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    private func recordingsFolderURL() -> URL {
        docsURL().appendingPathComponent("recorded_jams", isDirectory: true)
    }
    private func ensureRecordingsFolder() {
        let u = recordingsFolderURL()
        if !FileManager.default.fileExists(atPath: u.path) {
            try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }

    /// Best-effort: move any Jam_*.wav in Documents root into recorded_jams/
    private func migrateOrphans() {
        let fm = FileManager.default
        let root = docsURL()
        guard let contents = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for u in contents where u.pathExtension.lowercased() == "wav" {
            if u.lastPathComponent.hasPrefix("Jam_") {
                let dest = recordingsFolderURL().appendingPathComponent(u.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: u, to: dest)
                }
            }
        }
    }

    func refresh() {
        ensureRecordingsFolder()
        migrateOrphans()

        let fm = FileManager.default
        let folder = recordingsFolderURL()
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []

        var out: [Item] = []
        for u in urls where u.pathExtension.lowercased() == "wav" {
            let rv = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = rv?.fileSize ?? 0
            let mod  = rv?.contentModificationDate ?? Date.distantPast

            var dur: TimeInterval = 0
            if let f = try? AVAudioFile(forReading: u) {
                let sr = f.fileFormat.sampleRate
                if sr > 0 { dur = TimeInterval(Double(f.length) / sr) }
            }
            out.append(.init(url: u,
                             name: u.deletingPathExtension().lastPathComponent,
                             duration: dur,
                             sizeBytes: size,
                             modified: mod))
        }
        items = out.sorted { $0.modified > $1.modified }
    }

    func delete(_ item: Item) {
        let fm = FileManager.default
        try? fm.removeItem(at: item.url)
        if let idx = items.firstIndex(of: item) { items.remove(at: idx) }
    }
}




struct RecordingsDrawer: View {
    @Binding var isVisible: Bool              // NEW: parent controls visibility
    @ObservedObject var library: RecordingLibrary

    @State private var player: AVAudioPlayer?
    @State private var playingURL: URL?
    private let previewDelegate = PreviewDelegate()

    // Rename sheet
    @State private var showRenameSheet = false
    @State private var renameTarget: RecordingLibrary.Item?
    @State private var renameText: String = ""

    // NEW: swipe-to-dismiss state
    private enum DragLock { case horizontal, vertical }
    @State private var dragX: CGFloat = 0
    @State private var dragLock: DragLock? = nil
    @State private var isHorizDragging = false
    
    
    
    private func performRename(to newBaseName: String) {
        guard let target = renameTarget else { return }
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let fm = FileManager.default
        let folder = target.url.deletingLastPathComponent()
        var dest = folder.appendingPathComponent(sanitize(trimmed))
        if dest.pathExtension.lowercased() != "wav" {
            dest.deletePathExtension()
            dest.appendPathExtension("wav")
        }

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest) // replace if exists
            }
            try fm.moveItem(at: target.url, to: dest)
            if playingURL == target.url { playingURL = dest }  // keep playback coherent
            library.refresh()
        } catch {
            print("❌ rename failed:", error)
        }
    }

    private func sanitize(_ name: String) -> String {
        var s = name
        let bad = CharacterSet(charactersIn: "/:\\?<>\\*|\"")
        s = s.components(separatedBy: bad).joined(separator: "-")
        return s
    }
    
    private var swipeToDismiss: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if dragLock == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    if dx > dy + 6 { dragLock = .horizontal; isHorizDragging = true }
                    else if dy > dx + 6 { dragLock = .vertical; isHorizDragging = false }
                }
                if dragLock == .horizontal {
                    // Drawer is on the right → allow swiping to the right to dismiss
                    dragX = max(0, value.translation.width)
                }
            }
            .onEnded { value in
                defer { dragLock = nil; isHorizDragging = false }
                guard dragLock == .horizontal else { return }

                let predicted = value.predictedEndTranslation.width
                let shouldDismiss = dragX > 80 || predicted > 160

                if shouldDismiss {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragX = 420 // fling off-screen to the right
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                        isVisible = false
                        dragX = 0
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.90)) { dragX = 0 }
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recorded Jams").font(.headline)
                Spacer()
                Button { library.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
            }

            if library.items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.and.waveform.and.person.crop").foregroundColor(.secondary)
                    Text("No recordings yet. Tap the red ● to record.").foregroundColor(.secondary)
                }.font(.footnote)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(library.items) { item in
                            HStack(spacing: 10) {
                                // Play / Stop
                                Button { togglePlay(item) } label: {
                                    Image(systemName: playingURL == item.url ? "stop.fill" : "play.fill")
                                }
                                .buttonStyle(.bordered)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).lineLimit(1)
                                    Text("\(formatDuration(item.duration)) • \(formatSize(item.sizeBytes))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                // ⬆️ Share (system share sheet: Drive, Messages, etc.)
                                ShareLink(item: item.url) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.bordered)

                                // ✏️ Rename
                                Button {
                                    renameTarget = item
                                    renameText = item.name
                                    showRenameSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.bordered)

                                // 🗑️ Delete
                                Button(role: .destructive) {
                                    if playingURL == item.url { player?.stop(); playingURL = nil }
                                    library.delete(item)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.1)))
                        }
                    }
                   .scrollDisabled(isHorizDragging) // NEW
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())                 // NEW: capture drags anywhere in the card
        .offset(x: dragX)                          // NEW
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 22)
                .contentShape(Rectangle())
                .gesture(swipeToDismiss)   // your existing DragGesture for right-side dismiss
        }     // NEW
        .onAppear { library.refresh() }
        .onDisappear {
            if player?.isPlaying == true { player?.stop() }
            player = nil
            playingURL = nil
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Rename Recording").font(.headline)
                    TextField("New name", text: $renameText)
                        .textFieldStyle(.roundedBorder)

                    Spacer()

                    HStack {
                        Button("Cancel") { showRenameSheet = false }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)

                        Button("Save") {
                            performRename(to: renameText)
                            showRenameSheet = false
                        }
                        .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .navigationBarHidden(true)
            }
            .presentationDetents([.medium])
        }
    }

    private func togglePlay(_ item: RecordingLibrary.Item) {
        // Stop if tapping the same item
        if playingURL == item.url {
            player?.stop()
            playingURL = nil
            player = nil
            return
        }

        // Stop any existing preview first
        if player?.isPlaying == true { player?.stop() }

        do {
            let newPlayer = try AVAudioPlayer(contentsOf: item.url)
            previewDelegate.onFinish = { [weak player = newPlayer] in
                // Ensure the callback corresponds to the active player
                if self.player === player {
                    self.player?.stop()
                    self.player = nil
                    self.playingURL = nil
                }
            }
            newPlayer.delegate = previewDelegate
            newPlayer.prepareToPlay()
            newPlayer.play()

            player = newPlayer
            playingURL = item.url
        } catch {
            playingURL = nil
            player = nil
            print("❌ preview failed:", error)
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(round(t))
        return String(format: "%d:%02d", s/60, s%60)
    }
    private func formatSize(_ b: Int) -> String {
        let kb = Double(b)/1024.0, mb = kb/1024.0
        return mb >= 1 ? String(format:"%.1f MB", mb) : String(format:"%.0f KB", kb)
    }
}

private final class PreviewDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.onFinish?() }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { self.onFinish?() }
    }
}
