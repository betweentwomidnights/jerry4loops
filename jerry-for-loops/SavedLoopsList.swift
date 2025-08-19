//
//  SavedLoopsList.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 6/19/25.
//


import SwiftUI

struct SavedLoopsList: View {
    @Binding var isPresented: Bool
    let slotType: LoopGridSlideOut.SlotType
    let slotIndex: Int
    let globalBPM: Int
    let audioManager: LoopAudioManager
    let onLoopSelected: (SavedLoopInfo) -> Void
    
    @State private var savedLoops: [SavedLoopInfo] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                if isLoading {
                    loadingView
                } else if savedLoops.isEmpty {
                    emptyStateView
                } else {
                    loopsList
                }
            }
            .background(Color.black)
            .navigationBarHidden(true)
        }
        .onAppear {
            loadSavedLoops()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .foregroundColor(.white)
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Select \(slotType == .drum ? "Drum" : "Instrument") Loop")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Slot \(slotIndex + 1) • \(globalBPM) BPM")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Invisible button for balance
                Button("Cancel") {
                    // Do nothing
                }
                .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Type indicator
            HStack {
                Image(systemName: slotType == .drum ? "waveform" : "pianokeys")
                    .foregroundColor(slotType == .drum ? .red : .purple)
                
                Text("\(globalBPM) BPM \(slotType == .drum ? "Drums" : "Instruments")")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Spacer()
                
                if !savedLoops.isEmpty {
                    Text("\(savedLoops.count) loops")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 1)
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.2)
            
            Text("Loading saved loops...")
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: slotType == .drum ? "waveform" : "pianokeys")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No \(slotType == .drum ? "Drum" : "Instrument") Loops")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("No saved loops found for \(globalBPM) BPM")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                Text("Generate and save some \(slotType == .drum ? "drum" : "instrument") loops to populate this list!")
                    .font(.caption)
                    .foregroundColor(.gray.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Loops List
    private var loopsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(savedLoops.enumerated()), id: \.offset) { index, loop in
                    SavedLoopRow(
                        loop: loop,
                        slotType: slotType,
                        onTap: {
                            onLoopSelected(loop)
                            isPresented = false
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Load Saved Loops
    private func loadSavedLoops() {
        isLoading = true
        
        // Get all saved loops for current BPM
        let allLoops = audioManager.getSavedLoops(forBPM: globalBPM)
        
        // Filter by loop type
        let filteredLoops = allLoops.filter { loop in
            switch slotType {
            case .drum:
                return loop.isDrum
            case .instrument:
                return loop.isInstrument
            }
        }
        
        // Sort by saved timestamp (newest first)
        savedLoops = filteredLoops.sorted { loop1, loop2 in
            loop1.savedTimestamp > loop2.savedTimestamp
        }
        
        isLoading = false
        
        print("📱 Loaded \(savedLoops.count) \(slotType) loops for \(globalBPM) BPM")
    }
}

// MARK: - Saved Loop Row Component
struct SavedLoopRow: View {
    let loop: SavedLoopInfo
    let slotType: LoopGridSlideOut.SlotType
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Loop type icon
                Image(systemName: slotType == .drum ? "waveform" : "pianokeys")
                    .font(.title2)
                    .foregroundColor(slotType == .drum ? .red : .purple)
                    .frame(width: 30)
                
                // Loop details
                VStack(alignment: .leading, spacing: 4) {
                    // Name
                    Text(loop.displayName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    // Original prompt
                    if !loop.originalPrompt.isEmpty {
                        Text(loop.originalPrompt)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    
                    // Metadata row
                    HStack(spacing: 8) {
                        Text("\(loop.bars) bars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("\(String(format: "%.1f", loop.duration))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if loop.seed != -1 {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("seed: \(loop.seed)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(slotType == .drum ? Color.red.opacity(0.3) : Color.purple.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SavedLoopsList(
        isPresented: .constant(true),
        slotType: .drum,
        slotIndex: 0,
        globalBPM: 120,
        audioManager: LoopAudioManager(),
        onLoopSelected: { _ in }
    )
}
