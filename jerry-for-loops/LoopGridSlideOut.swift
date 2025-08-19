import SwiftUI

struct LoopGridSlideOut: View {
    @Binding var isExpanded: Bool
    let globalBPM: Int
    let audioManager: LoopAudioManager
    let playerManager: EngineLoopPlayerManager
    
    // Grid state - 4 slots for drums, 4 for instruments
    @State private var drumSlots: [SavedLoopInfo?] = Array(repeating: nil, count: 4)
    @State private var instrumentSlots: [SavedLoopInfo?] = Array(repeating: nil, count: 4)
    
    // UI state
    @State private var showingSavedLoopsList = false
    @State private var selectedSlotIndex = 0
    @State private var selectedSlotType: SlotType = .drum
    
    // BPM tracking for clearing slots
    @State private var lastKnownBPM: Int = 120
    
    enum SlotType {
        case drum, instrument
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Slide-out panel
            if isExpanded {
                slideOutPanel
                    .transition(.move(edge: .leading))
            }
            
            // Chevron toggle button
            chevronButton
                .zIndex(10) // Keep above panel
        }
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
        .onAppear {
            lastKnownBPM = globalBPM
        }
        .onChange(of: globalBPM) { newBPM in
            // Clear slots when BPM changes
            if newBPM != lastKnownBPM {
                clearAllSlots()
                lastKnownBPM = newBPM
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bpmChanged)) { notification in
            if let newBPM = notification.userInfo?["newBPM"] as? Int {
                print("🎵 LoopGrid: BPM changed to \(newBPM) - clearing all slots")
                clearAllSlots()
                lastKnownBPM = newBPM
                
                // Visual feedback with animation
                withAnimation(.easeInOut(duration: 0.3)) {
                    // Trigger a subtle animation by temporarily changing opacity or something
                }
            }
        }
        .overlay(
            // Saved loops list overlay (instead of sheet)
            Group {
                if showingSavedLoopsList {
                    ZStack {
                        // Background overlay
                        Color.black.opacity(0.7)
                            .edgesIgnoringSafeArea(.all)
                            .onTapGesture {
                                showingSavedLoopsList = false
                            }
                        
                        // List component
                        SavedLoopsList(
                            isPresented: $showingSavedLoopsList,
                            slotType: selectedSlotType,
                            slotIndex: selectedSlotIndex,
                            globalBPM: globalBPM,
                            audioManager: audioManager,
                            onLoopSelected: { selectedLoop in
                                populateSlot(type: selectedSlotType, index: selectedSlotIndex, with: selectedLoop)
                            }
                        )
                        .frame(maxWidth: 400, maxHeight: 600)
                        .background(Color.black)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.3), radius: 20)
                        .transition(.scale.combined(with: .opacity))
                    }
                    .zIndex(100)
                }
            }
        )
    }
    
    // MARK: - Slide-out Panel (UPDATED with BPM status)
    private var slideOutPanel: some View {
        VStack(spacing: 20) {
            // Title with BPM status
            VStack(spacing: 4) {
                Text("SAVED LOOPS")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("\(globalBPM) BPM")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                // Show if slots are empty due to BPM change
                if allSlotsEmpty && globalBPM != 120 {
                    Text("Slots cleared • New BPM")
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.7))
                } else if allSlotsEmpty {
                    Text("Tap and hold to add loops")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            .padding(.top, 16)
            
            // Drums section
            drumSection
            
            // Instruments section
            instrumentSection
            
            // Bottom padding instead of Spacer()
            Color.clear.frame(height: 20)
        }
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black.opacity(0.95))
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.red.opacity(0.3), Color.purple.opacity(0.3)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.1)
                )
        )
        .overlay(
            // Right border
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1),
            alignment: .trailing
        )
        .fixedSize(horizontal: false, vertical: true) // Compact height
    }
    
    // MARK: - Computed Properties
    private var allSlotsEmpty: Bool {
        drumSlots.allSatisfy { $0 == nil } && instrumentSlots.allSatisfy { $0 == nil }
    }
    
    // MARK: - Clear All Slots (NEW)
    private func clearAllSlots() {
        drumSlots = Array(repeating: nil, count: 4)
        instrumentSlots = Array(repeating: nil, count: 4)
        print("🧹 LoopGrid: All slots cleared for new BPM")
    }
    
    // MARK: - Drum Section
    private var drumSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.red)
                Text("DRUMS")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // 4 drum slots
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    SlotButton(
                        slotInfo: drumSlots[index],
                        slotType: .drum,
                        index: index,
                        onTap: {
                            print("🔍 Drum slot \(index) tapped")
                            tapSlot(type: .drum, index: index)
                        },
                        onLongPress: {
                            print("🔍 Drum slot \(index) long pressed - calling longPressSlot with .drum")
                            longPressSlot(type: .drum, index: index)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Instrument Section
    private var instrumentSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "pianokeys")
                    .foregroundColor(.purple)
                Text("INSTRUMENTS")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // 4 instrument slots
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    SlotButton(
                        slotInfo: instrumentSlots[index],
                        slotType: .instrument,
                        index: index,
                        onTap: {
                            print("🔍 Instrument slot \(index) tapped")
                            tapSlot(type: .instrument, index: index)
                        },
                        onLongPress: {
                            print("🔍 Instrument slot \(index) long pressed - calling longPressSlot with .instrument")
                            longPressSlot(type: .instrument, index: index)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Chevron Button
    private var chevronButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                isExpanded.toggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.left" : "chevron.right")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 40, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Color.black.opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 0)
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .offset(x: isExpanded ? 0 : 8) // Slight offset when collapsed
    }
    
    // MARK: - Actions
    private func tapSlot(type: SlotType, index: Int) {
        print("🎵 Tapped \(type) slot \(index)")
        
        // Get the saved loop from the slot
        let slotInfo: SavedLoopInfo?
        switch type {
        case .drum:
            slotInfo = drumSlots[index]
        case .instrument:
            slotInfo = instrumentSlots[index]
        }
        
        guard let savedLoop = slotInfo else {
            print("⚠️ No saved loop in slot \(index)")
            return
        }
        
        // Load the saved loop into the player (same as generating a new one)
        switch type {
        case .drum:
            playerManager.loadDrumLoop(savedLoop.audioURL, metadata: savedLoop.metadata)
            print("🥁 Loading saved drum loop: \(savedLoop.userGivenName)")
        case .instrument:
            playerManager.loadInstrumentLoop(savedLoop.audioURL, metadata: savedLoop.metadata)
            print("🎹 Loading saved instrument loop: \(savedLoop.userGivenName)")
        }
    }
    
    private func longPressSlot(type: SlotType, index: Int) {
        print("🎵 Long pressed \(type) slot \(index) - opening saved loops list")
        print("🔍 Debug: type=\(type), selectedSlotType before=\(selectedSlotType)")
        
        // Set state and show overlay with animation
        selectedSlotIndex = index
        selectedSlotType = type
        
        print("🔍 Debug: selectedSlotType after=\(selectedSlotType)")
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showingSavedLoopsList = true
        }
    }
    
    private func populateSlot(type: SlotType, index: Int, with loop: SavedLoopInfo) {
        switch type {
        case .drum:
            drumSlots[index] = loop
            print("🥁 Populated drum slot \(index) with '\(loop.displayName)'")
        case .instrument:
            instrumentSlots[index] = loop
            print("🎹 Populated instrument slot \(index) with '\(loop.displayName)'")
        }
    }
}

// MARK: - Slot Button Component
struct SlotButton: View {
    let slotInfo: SavedLoopInfo?
    let slotType: LoopGridSlideOut.SlotType
    let index: Int
    let onTap: () -> Void
    let onLongPress: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let info = slotInfo {
                    // Filled slot - show loop info
                    VStack(spacing: 2) {
                        Text(info.userGivenName)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        
                        Text("\(info.bars) bars")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                } else {
                    // Empty slot
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundColor(.gray.opacity(0.6))
                        
                        Text("Empty")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.8))
                    }
                }
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(slotInfo != nil ? slotColor.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(slotInfo != nil ? slotColor : Color.gray.opacity(0.3), lineWidth: 1.5)
                    )
            )
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress()
                }
        )
    }
    
    private var slotColor: Color {
        switch slotType {
        case .drum:
            return .red
        case .instrument:
            return .purple
        }
    }
}

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)
        
        VStack {
            Spacer()
            HStack {
                LoopGridSlideOut(
                    isExpanded: .constant(true),
                    globalBPM: 120,
                    audioManager: LoopAudioManager(),
                    playerManager: EngineLoopPlayerManager()
                )
                Spacer()
            }
            Spacer()
        }
    }
}
