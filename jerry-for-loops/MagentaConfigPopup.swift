import SwiftUI

struct MagentaConfigPopup: View {
    @Binding var isVisible: Bool
    let audioManager: LoopAudioManager
    let globalBPM: Int
    @State private var isUpdating = false
    @State private var showAdvanced: Bool = false
    @State private var showSteering: Bool = false

    // We read/write through the shared model on the manager
    @ObservedObject private var cfg: MagentaConfig

    init(isVisible: Binding<Bool>, audioManager: LoopAudioManager, globalBPM: Int) {
        self._isVisible = isVisible
        self.audioManager = audioManager
        self.globalBPM = globalBPM
        self._cfg = ObservedObject(initialValue: audioManager.magentaConfig)
    }

    // Layout calculations
    private let maxPopupHeight: CGFloat = UIScreen.main.bounds.height - 150

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isVisible {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { isVisible = false } }
                        .transition(.opacity)
                }

                if isVisible {
                    popupContent(in: geometry)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
    
    private func popupContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Fixed header
            header
                .padding(.bottom, 16)
            
            // Content area - always scrollable but height-constrained based on content
            contentArea(in: geometry)
            
            // Fixed footer buttons
            footerButtons
                .padding(.top, 16)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.95))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.pink, lineWidth: 2))
        )
        .frame(maxWidth: 380)
        .frame(maxHeight: maxPopupHeight)
        .onAppear {
            audioManager.fetchModelAssetsStatus()
        }
    }
    
    // Always use ScrollView but constrain height based on content needs
    @ViewBuilder
    private func contentArea(in geometry: GeometryProxy) -> some View {
        let content = VStack(spacing: 12) {
            stylesSection
                .id("styles")
            loopInfluenceSection
                .id("loop-influence")
            advancedSection
                .id("advanced")
            if cfg.assetsAvailable {
                steeringSection
                    .id("steering")
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.25), value: showAdvanced)
        .animation(.easeInOut(duration: 0.25), value: showSteering)
        
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: shouldShowScrollIndicators) {
                content
            }
            .frame(maxHeight: calculateContentHeight(in: geometry))
            .onChange(of: showAdvanced) { isAdvanced in
                if isAdvanced {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo("advanced", anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: showSteering) { isSteering in
                if isSteering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            proxy.scrollTo("steering", anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // Simplified logic: show scroll indicators only when content might overflow
    private var shouldShowScrollIndicators: Bool {
        let hasMultipleStyles = cfg.styles.count > 2
        let hasExpandedSections = showAdvanced || showSteering
        let hasComplexContent = (showAdvanced && cfg.styles.count > 1) ||
                               (showSteering && cfg.styles.count > 1) ||
                               (hasMultipleStyles && hasExpandedSections)
        
        return hasComplexContent
    }
    
    // Dynamic height calculation - grows with content but caps at available space
    private func calculateContentHeight(in geometry: GeometryProxy) -> CGFloat {
        let availableHeight = geometry.size.height
        let fixedContentHeight: CGFloat = 280 // Estimated height of header + footer
        let maxScrollHeight = availableHeight - fixedContentHeight
        
        // Estimate content height based on current state
        let baseHeight: CGFloat = 120 // Styles + Loop Influence
        let styleHeight = CGFloat(cfg.styles.count) * 70 // Approximate height per style
        let advancedHeight: CGFloat = showAdvanced ? 120 : 0
        let steeringHeight: CGFloat = showSteering ? 150 : 0
        
        let estimatedContentHeight = baseHeight + styleHeight + advancedHeight + steeringHeight
        
        // Return the minimum of estimated height and available space, with a reasonable minimum
        return min(max(estimatedContentHeight, 200), maxScrollHeight)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MAGENTA JAM").font(.headline).foregroundColor(.white)
                Text("Live session controls").font(.caption).foregroundColor(.pink.opacity(0.8))
            }
            Spacer()
            Button {
                withAnimation { isVisible = false }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
            }
        }
    }

    // MARK: - Styles Section
    private var stylesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Styles & Weights")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    cfg.styles.append(.init(text: "", weight: 1.0))
                    if cfg.styles.count > 4 { _ = cfg.styles.removeLast() }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption2)
                        .foregroundColor(.pink)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.pink.opacity(0.6), lineWidth: 1))
                }
                .disabled(cfg.styles.count >= 4)
            }

            ForEach(Array(cfg.styles.enumerated()), id: \.element.id) { index, entry in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("e.g. acid house, trumpet, lofi",
                                  text: Binding(
                                    get: { cfg.styles[index].text },
                                    set: { cfg.styles[index].text = $0 }
                                  )
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.caption)
                        
                        // Dice button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                cfg.styles[index].text = MagentaPrompts.getNextCyclingStyle()
                            }
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Image(systemName: "dice")
                                .font(.caption2)
                                .foregroundColor(.pink)
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.3))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.pink, lineWidth: 1)
                                )
                        }

                        if cfg.styles.count > 1 {
                            Button {
                                cfg.styles.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.pink)
                            }
                        }
                    }

                    HStack {
                        Text("Weight")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Slider(value:
                               Binding(get: { cfg.styles[index].weight },
                                       set: { cfg.styles[index].weight = $0 }),
                               in: 0...1, step: 0.01)
                            .frame(height: 20)
                        Text(String(format: "%.2f", cfg.styles[index].weight))
                            .font(.caption2)
                            .foregroundColor(.pink)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink.opacity(0.25), lineWidth: 1))
            }
        }
    }

    // MARK: - Loop Influence Section
    private var loopInfluenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Loop Influence")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", cfg.loopWeight))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.pink)
            }
            Slider(value: $cfg.loopWeight, in: 0...1, step: 0.01)
                .frame(height: 20)
        }
    }

    // MARK: - Advanced Section
    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(spacing: 8) {
                row("Temperature", trailing: String(format: "%.2f", cfg.temperature))
                Slider(value: $cfg.temperature, in: 0...4, step: 0.05)
                    .frame(height: 20)

                row("Top-K", trailing: "\(cfg.topK)")
                Slider(value: Binding(get: { Double(cfg.topK) }, set: { cfg.topK = Int($0.rounded()) }),
                       in: 0...1024, step: 1)
                    .frame(height: 20)

                row("Guidance", trailing: String(format: "%.2f", cfg.guidanceWeight))
                Slider(value: $cfg.guidanceWeight, in: 0...10, step: 0.05)
                    .frame(height: 20)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text("Advanced (Magenta)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: showAdvanced)
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Steering Section
    private var steeringSection: some View {
        DisclosureGroup(isExpanded: $showSteering) {
            VStack(spacing: 8) {
                // Mean (only shown if backend said it exists)
                if cfg.meanAvailable {
                    HStack {
                        Text("Mean")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.2f", cfg.mean))
                            .font(.caption2)
                            .foregroundColor(.pink)
                    }
                    Slider(value: $cfg.mean, in: 0...2, step: 0.01)
                        .frame(height: 20)
                }

                // Compact centroid mixer (space-efficient)
                if let k = cfg.centroidCount, k > 0 {
                    // Centroid picker chips (C1…Ck)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(0..<k, id: \.self) { idx in
                                Button {
                                    cfg.selectCompactCentroid(idx)
                                } label: {
                                    Text("C\(idx+1)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(cfg.compactCentroidIndex == idx ? .black : .white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(cfg.compactCentroidIndex == idx ? Color.pink : Color.gray.opacity(0.35))
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }

                    // One intensity slider
                    HStack {
                        Text("Intensity")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        Text(String(format: "%.2f", cfg.compactCentroidIntensity))
                            .font(.caption2)
                            .foregroundColor(.pink)
                    }
                    Slider(
                        value: Binding(
                            get: { cfg.compactCentroidIntensity },
                            set: { cfg.compactCentroidIntensity = $0; cfg.applyCompactMixer() }
                        ),
                        in: 0...2, step: 0.01
                    )
                    .frame(height: 20)

                    // Optional: reveal all individual centroid sliders
                    Toggle(isOn: $cfg.showAdvancedCentroids) {
                        Text("Show all centroid sliders")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .pink))

                    if cfg.showAdvancedCentroids {
                        VStack(spacing: 6) {
                            ForEach(0..<k, id: \.self) { idx in
                                HStack {
                                    Text("Centroid \(idx+1)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Slider(value: Binding(
                                        get: { cfg.centroidWeights[idx] },
                                        set: { newVal in
                                            cfg.centroidWeights[idx] = newVal
                                            if idx == cfg.compactCentroidIndex {
                                                cfg.compactCentroidIntensity = newVal
                                            }
                                        }
                                    ), in: 0...2, step: 0.01)
                                    .frame(height: 20)
                                    Text(String(format: "%.2f", cfg.centroidWeights[idx]))
                                        .font(.caption2)
                                        .foregroundColor(.pink)
                                        .frame(width: 32, alignment: .trailing)
                                }
                            }
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.pink.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink.opacity(0.2), lineWidth: 1))
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text("Steering (Finetune)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.gray)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(showSteering ? 180 : 0))
                    .animation(.easeInOut(duration: 0.2), value: showSteering)
            }
        }
        .padding(.vertical, 6)
    }

    private func row(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer()
            Text(trailing)
                .font(.caption2)
                .foregroundColor(.pink)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            // Reseed
            Button {
                audioManager.requestReseedSplice(anchorBars: 2.0)
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("RESEED")
                }
            }
            .buttonStyle(Pill(color: .pink))

            Button {
                guard !isUpdating else { return }
                isUpdating = true
                Task {
                    defer { isUpdating = false }
                    do {
                        // Tip: infer "blend initial combined loop" from loop_weight > 0
                        let useCurrentMix = audioManager.magentaConfig.loopWeight > 0.001
                        try await audioManager.requestUpdateMagentaAll(useCurrentMixAsStyle: useCurrentMix)
                        // show "Queued for next bar" toast if you want
                    } catch {
                        print("❌ Update styles failed: \(error)")
                        // surface a toast/errorMessage if helpful
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text(isUpdating ? "UPDATING…" : "UPDATE STYLES")
                }
            }
            .buttonStyle(Pill(color: isUpdating ? .gray : .pink))
            .disabled(isUpdating)

            Spacer()

            // Stop
            Button {
                audioManager.requestStopMagentaJam()
                withAnimation { isVisible = false }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("STOP")
                }
            }
            .buttonStyle(Pill(color: .red))
        }
    }
}

private struct Pill: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline).fontWeight(.bold)
            .foregroundColor(.black)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1.0))
            .cornerRadius(8)
    }
}
