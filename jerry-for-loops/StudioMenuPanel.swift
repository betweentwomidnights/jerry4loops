import SwiftUI

// MARK: - ViewModel

@MainActor
final class ModelSelectorVM: ObservableObject {
    // Magenta selection
    @Published var size: String = "large"
    @Published var repo: String = "thepatch/magenta-ft"
    @Published var revision: String = "main"
    @Published var stepChoice: StepChoice = .latest
    @Published var specificStep: String = ""

    // Options
    @Published var syncAssets: Bool = true
    @Published var prewarm: Bool = true

    // Checkpoints data
    @Published var steps: [Int] = []
    @Published var latest: Int? = nil

    // Activity flags
    @Published var isLoading: Bool = false
    @Published var isWorking: Bool = false

    // Backend health
    @Published var backendHealthy: Bool? = nil
    @Published var backendMessage: String? = nil
    @Published var checkingBackend: Bool = false

    // Responses
    @Published var banner: String? = nil
    @Published var error: String? = nil
    @Published var config: ModelConfigResponse? = nil

    enum StepChoice: String, CaseIterable, Identifiable { case none, latest, specific; var id: String { rawValue } }

    func onOpenSheet(using service: ModelService) async { await checkBackend(using: service) }

    func refreshConfig(using service: ModelService) async {
        do { config = try await service.getConfig() } catch { self.error = error.localizedDescription }
    }

    func fetchSteps(using service: ModelService) async {
        guard !repo.isEmpty, stepChoice != .none else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let resp = try await service.getCheckpoints(repo: repo, revision: revision)
            steps = resp.steps
            latest = resp.latest
        } catch { self.error = error.localizedDescription }
    }

    func checkBackend(using service: ModelService) async {
        checkingBackend = true; backendMessage = nil; defer { checkingBackend = false }
        let res = await service.getHealth()
        backendHealthy = res.ok
        backendMessage = res.message
        guard res.ok else { return }
        await refreshConfig(using: service) // lightweight snapshot
    }

    func apply(using service: ModelService) async {
        error = nil; banner = nil; isWorking = true; defer { isWorking = false }
        // 1) validate (dry-run)
        do {
            let req = makeRequest(dryRun: true)
            _ = try await service.selectModel(req)
        } catch { self.error = "Validation failed: \(error.localizedDescription)"; return }
        // 2) real apply
        do {
            let req = makeRequest(dryRun: false)
            let resp = try await service.selectModel(req)
            banner = resp.ok ? (prewarm ? "Model ready (prewarmed)" : "Model switched") : "Switch failed"
            await refreshConfig(using: service)
        } catch { self.error = error.localizedDescription }
    }

    private func makeRequest(dryRun: Bool) -> ModelSelectReq {
        var stepStr: String? = nil
        switch stepChoice {
        case .none: stepStr = "none"
        case .latest: stepStr = "latest"
        case .specific:
            let val = specificStep.trimmingCharacters(in: .whitespaces)
            stepStr = val.isEmpty ? nil : val
        }
        return ModelSelectReq(
            size: size,
            repo_id: (stepChoice == .none ? nil : repo),
            revision: (stepChoice == .none ? nil : revision),
            step: stepStr,
            assets_repo_id: (stepChoice == .none ? nil : repo),
            sync_assets: syncAssets,
            prewarm: prewarm,
            stop_active: true,
            dry_run: dryRun
        )
    }
}

// MARK: - UI Panel

struct StudioMenuPanel: View {
    @EnvironmentObject private var service: ModelService
    @EnvironmentObject private var audio: LoopAudioManager
    @StateObject private var vm = ModelSelectorVM()

    // NEW: parent controls visibility (overlay, not sheet)
    @Binding var isVisible: Bool
    
    @State private var magentaURLField: String = ""

    // Mirror the drawer’s drag state, but for left-side dismissal
    private enum DragLock { case horizontal, vertical }
    @State private var dragX: CGFloat = 0
    @State private var dragLock: DragLock? = nil
    @State private var isHorizDragging = false
    
    // Keyboard handling
    @FocusState private var isURLFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

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
                    // Panel is on the LEFT → allow swiping LEFT (negative) to dismiss
                    dragX = min(0, value.translation.width)
                }
            }
            .onEnded { value in
                defer { dragLock = nil; isHorizDragging = false }
                guard dragLock == .horizontal else { return }

                let predicted = value.predictedEndTranslation.width
                let shouldDismiss = dragX < -80 || predicted < -160   // mirror thresholds

                if shouldDismiss {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragX = -420 // fling off-screen to the left
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
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Studio Controls").font(.headline)
                Spacer()
                Button {
                    withAnimation(.spring()) { isVisible = false }
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    magentaSection
                    stableAudioSection
                    backendSection
                }
                .padding(4)
            }
            .scrollDisabled(isHorizDragging) // mirror drawer to avoid gesture conflict
        }
        .padding(16)
        .frame(maxWidth: 520)
        
        .padding(.bottom, keyboardHeight)                  // grow the panel down to the keyboard
        .ignoresSafeArea(.keyboard, edges: .bottom)        // opt out of automatic keyboard insets
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .shadow(radius: 20)
        .overlay(overlayBanner.padding(.bottom, 8), alignment: .bottom)
        .contentShape(Rectangle()) // fine to keep for hit-testing the card
        
        
        .offset(x: dragX)                      // follow finger horizontally
        
        .task {
                    await vm.onOpenSheet(using: service)
                    // seed field & service from manager on open
                    magentaURLField = audio.magentaBaseURLString
                    service.baseURL = audio.magentaBaseURLString
                }
        // ⬇️ ADD THIS
        .overlay(alignment: .trailing) {
            Color.clear
                .frame(width: 40)                     // 16–24 px feels good
                .contentShape(Rectangle())
                .gesture(swipeToDismiss)              // the same DragGesture you already have
        }
        
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
        guard let info = note.userInfo,
        let frame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        let height = max(0, UIScreen.main.bounds.height - frame.origin.y)
        withAnimation(.easeOut(duration: duration)) { keyboardHeight = height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
        }
        .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
        //Spacer()
        Button("Done") { isURLFocused = false }
        }
        }
        
    }

    private var overlayBanner: some View {
        Group {
            if let msg = vm.banner { banner(text: msg, color: .green) }
            else if let err = vm.error { banner(text: err, color: .red) }
        }
        .animation(.spring(), value: vm.banner)
        .animation(.spring(), value: vm.error)
    }

    private func banner(text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote).padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.6), lineWidth: 1))
            .foregroundColor(.primary)
            .padding(.bottom, 12)
    }

    // MARK: - Sections

    private var magentaSection: some View {
        GroupBox(label: label("MagentaRT Model")) {
            VStack(alignment: .leading, spacing: 14) {
                if vm.backendHealthy == false {
                    Label("Backend is offline. Please check the backend URL and start the HF Space to use MagentaRT.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.footnote)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                }

                LabeledContent("Size") {
                    Picker("Size", selection: $vm.size) {
                        Text("base").tag("base")
                        Text("large").tag("large")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }

                LabeledContent("Repo") {
                    TextField("thepatch/magenta-ft", text: $vm.repo)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .disabled(vm.stepChoice == .none)
                        .opacity(vm.stepChoice == .none ? 0.5 : 1)
                }

                DisclosureGroup("Advanced") {
                    LabeledContent("Revision") {
                        TextField("main", text: $vm.revision)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .disabled(vm.stepChoice == .none)
                            .opacity(vm.stepChoice == .none ? 0.5 : 1)
                    }
                }

                LabeledContent("Checkpoint") {
                    Picker("Checkpoint", selection: $vm.stepChoice) {
                        Text("No finetune").tag(ModelSelectorVM.StepChoice.none)
                        Text("Latest").tag(ModelSelectorVM.StepChoice.latest)
                        Text("Specific").tag(ModelSelectorVM.StepChoice.specific)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)
                }

                if vm.stepChoice == .specific {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("e.g. 1863001", text: $vm.specificStep)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            Button {
                                Task { await vm.fetchSteps(using: service) }
                            } label: {
                                Label("Fetch checkpoints", systemImage: vm.isLoading ? "hourglass" : "arrow.clockwise")
                                    .labelStyle(.titleAndIcon)
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.isLoading || vm.backendHealthy != true)
                        }

                        if !vm.steps.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(vm.steps, id: \.self) { s in
                                        Button("\(s)") { vm.specificStep = String(s) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }.padding(.vertical, 2)
                            }
                            if let latest = vm.latest { Text("Latest: \(latest)").font(.footnote).foregroundColor(.secondary) }
                        }
                    }
                }

                Divider().padding(.vertical, 2)

                Button(action: { Task { await vm.apply(using: service) } }) {
                    HStack {
                        if vm.isWorking { ProgressView().scaleEffect(0.9) }
                        Text(vm.prewarm ? "Apply & Warm" : "Apply")
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(vm.isWorking || vm.backendHealthy != true)

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $vm.syncAssets) {
                        Label("Sync finetune assets (mean/centroids)", systemImage: "square.stack.3d.up")
                    }
                    Toggle(isOn: $vm.prewarm) {
                        Label("Prewarm (compile now to reduce first-use latency)", systemImage: "bolt.fill")
                    }
                }
                .toggleStyle(.switch)
                .disabled(vm.backendHealthy != true)

                if let cfg = vm.config {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                        statusRow(name: "Active size", value: cfg.size)
                        statusRow(name: "Repo", value: cfg.repo ?? "—")
                        statusRow(name: "Step", value: cfg.selected_step ?? "—")
                        statusRow(name: "Loaded", value: cfg.loaded ? "yes" : "no")
                        statusRow(name: "Warmup", value: cfg.warmup_done ? "ready" : "—")
                        if cfg.active_jam { statusRow(name: "Jam", value: "running") }
                    }.font(.caption)
                }
            }
            .padding(8)
        }
    }

    private var stableAudioSection: some View {
        GroupBox(label: label("Stable Audio (open-small)")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Finetunes")
                    .font(.footnote).foregroundColor(.secondary)
                TextField("no finetunes exist of this yet. please make one and upload it to the hf hub", text: .constant(""))
                    .disabled(true)
                    .textFieldStyle(.roundedBorder)
                    .opacity(0.6)
            }.padding(8)
        }
    }

    private var backendSection: some View {
            GroupBox(label: label("Backend")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Magenta server")
                        .font(.footnote).foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("https://your-space.hf.space", text: $magentaURLField)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textFieldStyle(.roundedBorder)
                            .focused($isURLFocused)
                            .submitLabel(.done)
                            .onSubmit { isURLFocused = false }
                            .frame(maxWidth: .infinity) // let the field stretch

                        HStack(spacing: 8) {
                            Spacer() // push buttons to the trailing edge
                            Button("Apply") {
                                let normalized = LoopAudioManager.normalizeBaseURL(magentaURLField)
                                magentaURLField = normalized
                                audio.setMagentaBaseURL(normalized)
                                service.baseURL = normalized
                                Task { await vm.checkBackend(using: service) }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reset") {
                                let def = LoopAudioManager.defaultMagentaBaseURL
                                magentaURLField = def
                                audio.setMagentaBaseURL(def)
                                service.baseURL = def
                                Task { await vm.checkBackend(using: service) }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let healthy = vm.backendHealthy {
                        if healthy {
                            Label(vm.backendMessage ?? "Online", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.footnote)
                        } else {
                            Label(vm.backendMessage ?? "Offline or unreachable", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.footnote)
                        }
                    } else {
                        Text("Tap Apply to set and test connectivity.")
                            .font(.footnote).foregroundColor(.secondary)
                    }

                    // UPDATED NOTE + CLICKABLE LINK
                    VStack(alignment: .leading, spacing: 4) {
                    Text("MagentaRT needs a bigger GPU. Duplicate our Hugging Face Space using an L40S GPU, start it, then paste your new Space URL above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    Link("Open the Space: thecollabagepatch/magenta-retry",
                    destination: URL(string: "https://huggingface.co/spaces/thecollabagepatch/magenta-retry")!)
                    .font(.caption)
                    }
                }
                .padding(8)
            }
        }
    
    // MARK: - Small helpers
    private func label(_ title: String) -> some View {
        HStack(spacing: 6) { Text(title).font(.headline) }
    }

    private func statusRow(name: String, value: String) -> some View {
        HStack { Text(name).foregroundColor(.secondary); Spacer(); Text(value) }
    }
}

// MARK: - Preview
#Preview {
    StudioMenuPanel(isVisible: .constant(true))
        .environmentObject(LoopAudioManager())
        .environmentObject(ModelService(baseURL: "https://thecollabagepatch-magenta-retry.hf.space"))
    
}
