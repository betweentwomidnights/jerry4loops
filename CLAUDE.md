# jerry4loops - Claude Code Instructions

## project overview

jerry4loops is an experimental ios app for real-time ai-generated loop jamming. users can generate synchronized drum and instrument loops using stable-audio-open-small and magentaRT, with instant swapping and style transfer capabilities.

## codebase structure

- **LoopJamView.swift**: main ui with drum/instrument sections and transport controls
- **EngineLoopPlayerManager.swift**: handles audio playback, timing, loop switching with sample-accurate beat synchronization  
- **LoopAudioManager.swift**: manages ai model api calls, audio generation, and notifications
- **Various popup views**: configuration dialogs for generation parameters

## current priority task

### task: fix generation status routing for individual loop types

**problem**: when either drum or instrument loop is generating, BOTH loop sections show "generating" status instead of only the section that's actually generating.

**root cause analysis**:
- `LoopAudioManager` has single `@Published var isGenerating: Bool = false` used for all generation activity
- `LoopJamView` drum section checks `audioManager.isGenerating` for status
- `LoopJamView` instrument section also checks `audioManager.isGenerating` for status  
- when ANY loop generates, both sections show "generating" because they use the same flag

**required changes**:

1. **in LoopAudioManager.swift**:
   - replace `@Published var isGenerating = false` with:
     - `@Published var isDrumGenerating: Bool = false`
     - `@Published var isInstrumentGenerating: Bool = false`
   
   - update `startGeneration()` method to accept loop type parameter:
     ```swift
     public func startGeneration(for loopType: LoopType) -> Bool {
         guard !isDrumGenerating && !isInstrumentGenerating else { return false }
         
         switch loopType {
         case .drums:
             isDrumGenerating = true
         case .instruments:
             isInstrumentGenerating = true
         }
         // rest of existing logic...
     }
     ```
   
   - update `cleanupGeneration()` method to accept loop type parameter:
     ```swift
     public func cleanupGeneration(for loopType: LoopType) {
         switch loopType {
         case .drums:
             isDrumGenerating = false
         case .instruments:
             isInstrumentGenerating = false
         }
         // rest of existing logic...
     }
     ```
   
   - update `generateLoop()` method to pass loop type to start/cleanup:
     ```swift
     private func generateLoop(..., loopType: LoopType, ...) {
         guard startGeneration(for: loopType) else { return }
         // existing generation logic...
         // in completion: cleanupGeneration(for: loopType)
     }
     ```

   - add computed property for backward compatibility:
     ```swift
     var isGenerating: Bool {
         return isDrumGenerating || isInstrumentGenerating
     }
     ```

2. **in LoopJamView.swift**:
   - drum section status logic: change `audioManager.isGenerating` to `audioManager.isDrumGenerating`
   - instrument section status logic: change `audioManager.isGenerating` to `audioManager.isInstrumentGenerating`
   - keep any other references to `audioManager.isGenerating` unchanged (like button disabled states that should apply to both)

**method call chain to update**:
- `generateDrumLoop()` → `generateLoop(..., loopType: .drums, ...)`
- `generateInstrumentLoop()` → `generateLoop(..., loopType: .instruments, ...)`  
- `generateStyleTransferLoop()` → needs loop type parameter
- any magenta generation methods → use instrument type

## code style guidelines

- use lowercase comments and print statements (existing style)
- maintain existing swiftui patterns and @published property bindings
- preserve all existing functionality including generation state coordination with playerManager
- keep backward compatibility where possible with computed properties

## testing considerations

- verify only drum section shows "generating" when drum loop is being generated
- verify only instrument section shows "generating" when instrument loop is being generated
- ensure button disabled states still work correctly for both sections
- test both standard generation and style transfer scenarios
- verify magenta jam generation shows correct status

## files to modify

- `LoopAudioManager.swift`: split isGenerating into type-specific flags, update generation methods
- `LoopJamView.swift`: update status message logic to use type-specific flags

## success criteria

1. when drum loop generates, only drum section shows "generating" status
2. when instrument loop generates, only instrument section shows "generating" status  
3. magenta jam generation shows status in instrument section only
4. all existing generation functionality preserved
5. button disabled states and other ui logic continues working correctly
