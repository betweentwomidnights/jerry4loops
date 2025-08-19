# jerry4loops - Claude Code Instructions

## project overview

jerry4loops is an experimental ios app for real-time ai-generated loop jamming. users can generate synchronized drum and instrument loops using stable-audio-open-small and magentaRT, with instant swapping and style transfer capabilities.

## codebase structure

- **LoopJamView.swift**: main ui with drum/instrument sections and transport controls
- **FilterKnob.swift**: filter frequency control knob component
- **ReverbKnob.swift**: reverb amount control knob component  
- **EngineLoopPlayerManager.swift**: handles audio playback, timing, loop switching
- **LoopAudioManager.swift**: manages ai model api calls and audio generation

## current priority task

### task: optimize layout spacing and status message display

**problem**: status messages in both drum and instrument sections are getting truncated (showing "Drum loop rea..." and "Instrument loo...") due to insufficient horizontal space. the filter and reverb knobs are competing for space with status text.

**root cause analysis**:
- filter and reverb knobs use `knobSize: CGFloat = 60` which is quite large
- status messages use verbose text like "Drum loop ready" and "Instrument loop ready"
- horizontal layout in both sections: `FilterKnob + ReverbKnob + Other Controls + Spacer + StatusText`
- status text area gets compressed when knobs take up too much space

**required changes**:

1. **in FilterKnob.swift and ReverbKnob.swift**:
   - reduce `knobSize: CGFloat = 60` to `knobSize: CGFloat = 45` 
   - adjust proportional spacing and sizing:
     - indicator line height: `knobSize * 0.3` (stays proportional)
     - center dot: reduce from `frame(width: 6, height: 6)` to `frame(width: 4, height: 4)`
     - stroke widths and background sizing should scale proportionally
   - ensure text labels ("FILTER", "REVERB") and value displays remain readable

2. **in LoopJamView.swift status messages**:
   - **shorten status text** for better fit:
     - "Drum loop ready • \(globalBPM) BPM" → "Loop ready • \(globalBPM)bpm"
     - "Instrument loop ready • \(globalBPM) BPM" → "Loop ready • \(globalBPM)bpm"
     - "Live coding: Next loop generating..." → "Next loop generating..."
     - "Generating drums..." → "Generating..."
     - "Generating instruments..." → "Generating..."
     - "No drum loop loaded" → "No loop loaded"
     - "No instrument loop loaded" → "No loop loaded"
   
   - **improve status text layout** for multi-line support:
     - ensure status VStack has proper spacing and alignment
     - consider reducing font sizes slightly if needed (.caption → .caption2 for some text)
     - make sure text doesn't compete with fixed-width knob spacing

3. **optimize horizontal spacing**:
   - in both drum and instrument HStack layouts, consider reducing spacing from `HStack(spacing: 20)` to `HStack(spacing: 15)`
   - ensure adequate space is allocated to status text area

**visual hierarchy priorities**:
1. knobs should be functional but not dominate space
2. status messages should be fully visible and informative
3. maintain consistent sizing between drum and instrument sections
4. preserve existing color schemes and interaction patterns

## code style guidelines

- maintain existing swiftui patterns and proportional sizing
- keep knob interaction areas large enough for usability
- preserve existing color schemes (red for drums, purple for instruments)
- use consistent spacing and alignment patterns
- ensure text remains legible after size reductions

## testing considerations

- verify knobs remain easy to interact with at smaller size
- ensure all status messages display completely without truncation
- test on different device sizes to ensure responsive layout
- confirm knob value displays and labels remain readable
- check that reduced spacing doesn't feel cramped

## files to modify

- `FilterKnob.swift`: reduce knob size and adjust proportional elements
- `ReverbKnob.swift`: reduce knob size and adjust proportional elements  
- `LoopJamView.swift`: shorten status messages and optimize layout spacing

## success criteria

1. filter and reverb knobs are smaller but remain fully functional and readable
2. all status messages display completely without truncation
3. layout feels balanced with adequate space for both controls and status text
4. text is concise but still informative about current state
5. consistent sizing and spacing between drum and instrument sections
6. maintain existing visual hierarchy and color coding
