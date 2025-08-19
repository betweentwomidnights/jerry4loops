//
//  MagentaConfigPopup.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 8/17/25.
//


import SwiftUI

struct MagentaConfigPopup: View {
    @Binding var isVisible: Bool
    let audioManager: LoopAudioManager
    let globalBPM: Int
    @State private var isUpdating = false

    // We read/write through the shared model on the manager
    @ObservedObject private var cfg: MagentaConfig

    init(isVisible: Binding<Bool>, audioManager: LoopAudioManager, globalBPM: Int) {
        self._isVisible = isVisible
        self.audioManager = audioManager
        self.globalBPM = globalBPM
        self._cfg = ObservedObject(initialValue: audioManager.magentaConfig)
    }

    var body: some View {
        ZStack {
            if isVisible {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation { isVisible = false } }
                    .transition(.opacity)
            }

            if isVisible {
                VStack(spacing: 16) {
                    header
                    content
                    footerButtons
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.95))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.pink, lineWidth: 2))
                )
                .frame(maxWidth: 380)
                .transition(.scale.combined(with: .opacity))
            }
        }
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

    private var content: some View {
        VStack(spacing: 12) {
            // Styles & weights (replicated UI)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Styles & Weights").font(.subheadline).foregroundColor(.white)
                    Spacer()
                    Button {
                        cfg.styles.append(.init(text: "", weight: 1.0))
                        if cfg.styles.count > 4 { _ = cfg.styles.removeLast() }
                    } label: {
                        Image(systemName: "plus").font(.caption).foregroundColor(.pink)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.25)))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.pink.opacity(0.6), lineWidth: 1))
                    }
                    .disabled(cfg.styles.count >= 4)
                }

                ForEach(Array(cfg.styles.enumerated()), id: \.element.id) { index, entry in
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("e.g. acid house, trumpet, lofi",
                                      text: Binding(
                                        get: { cfg.styles[index].text },
                                        set: { cfg.styles[index].text = $0 }
                                      )
                            )
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.subheadline)

                            if cfg.styles.count > 1 {
                                Button {
                                    cfg.styles.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.pink)
                                }
                            }
                        }

                        HStack {
                            Text("Weight").font(.caption).foregroundColor(.gray)
                            Slider(value:
                                   Binding(get: { cfg.styles[index].weight },
                                           set: { cfg.styles[index].weight = $0 }),
                                   in: 0...1, step: 0.01)
                            Text(String(format: "%.2f", cfg.styles[index].weight))
                                .font(.caption2).foregroundColor(.pink)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.pink.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.pink.opacity(0.25), lineWidth: 1))
                }
            }

            // Loop influence
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Loop Influence").font(.subheadline).foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.2f", cfg.loopWeight)).font(.subheadline).fontWeight(.bold).foregroundColor(.pink)
                }
                Slider(value: $cfg.loopWeight, in: 0...1, step: 0.01)
            }

            // Bars: 4 / 8
            VStack(alignment: .leading, spacing: 8) {
                Text("Bars").font(.subheadline).foregroundColor(.white)
                HStack(spacing: 8) {
                    ForEach([4, 8], id: \.self) { count in
                        Button {
                            cfg.bars = count
                        } label: {
                            Text("\(count)")
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor(cfg.bars == count ? .black : .white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(cfg.bars == count ? Color.pink : Color.gray.opacity(0.3))
                                .cornerRadius(6)
                        }
                    }
                }
            }

            // Advanced
            DisclosureGroup {
                VStack(spacing: 12) {
                    row("Temperature", trailing: String(format: "%.2f", cfg.temperature))
                    Slider(value: $cfg.temperature, in: 0...4, step: 0.05)

                    row("Top-K", trailing: "\(cfg.topK)")
                    Slider(value: Binding(get: { Double(cfg.topK) }, set: { cfg.topK = Int($0.rounded()) }),
                           in: 0...1024, step: 1)

                    row("Guidance", trailing: String(format: "%.2f", cfg.guidanceWeight))
                    Slider(value: $cfg.guidanceWeight, in: 0...10, step: 0.05)
                }.padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Text("Advanced (Magenta)").font(.subheadline).foregroundColor(.gray)
                    Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func row(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundColor(.gray)
            Spacer()
            Text(trailing).font(.caption2).foregroundColor(.pink)
        }
    }

    private var footerButtons: some View {
        HStack(spacing: 10) {
            // Reseed
            Button {
                audioManager.requestReseedSplice(anchorBars: 2.0)
            } label: {
                HStack { Image(systemName: "arrow.triangle.2.circlepath"); Text("RESEED") }
            }
            .buttonStyle(Pill(color: .pink))

            Button {
                guard !isUpdating else { return }
                isUpdating = true
                Task {
                    defer { isUpdating = false }
                    do {
                        // Tip: infer “blend initial combined loop” from loop_weight > 0
                        let useCurrentMix = audioManager.magentaConfig.loopWeight > 0.001
                        try await audioManager.requestUpdateMagentaAll(useCurrentMixAsStyle: useCurrentMix)
                        // show “Queued for next bar” toast if you want
                    } catch {
                        print("❌ Update styles failed: \(error)")
                        // surface a toast/errorMessage if helpful
                    }
                }
            } label: {
                HStack { Image(systemName: "slider.horizontal.3"); Text(isUpdating ? "UPDATING…" : "UPDATE STYLES") }
            }
            .buttonStyle(Pill(color: isUpdating ? .gray : .pink))
            .disabled(isUpdating)

            Spacer()

            // Stop
            Button {
                audioManager.requestStopMagentaJam()
                withAnimation { isVisible = false }
            } label: {
                HStack { Image(systemName: "stop.fill"); Text("STOP") }
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
