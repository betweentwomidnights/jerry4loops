import SwiftUI

struct FilterKnob: View {
    @Binding var frequency: Float
    let onFrequencyChange: (Float) -> Void
    
    // Knob state
    @State private var angle: Double = 0
    @State private var startAngle: Double = 0
    @State private var isDragging: Bool = false
    
    // Constants
    private let minFreq: Float = 20.0      // 20Hz
    private let maxFreq: Float = 20000.0   // 20kHz
    private let minAngle: Double = -135     // Start angle
    private let maxAngle: Double = 135      // End angle
    private let knobSize: CGFloat = 45
    
    var body: some View {
        VStack(spacing: 4) {
            Text("FILTER")
                .font(.caption2)
                .foregroundColor(.gray)
            
            // Main knob
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: knobSize, height: knobSize)
                
                // Active arc showing filter range
                Circle()
                    .trim(from: 0, to: normalizedFrequency)
                    .stroke(
                        LinearGradient(
                            colors: [.red, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: knobSize - 4, height: knobSize - 4)
                    .rotationEffect(.degrees(-90))
                
                // Center dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                
                // Knob indicator line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: knobSize * 0.3)
                    .offset(y: -knobSize * 0.2)
                    .rotationEffect(.degrees(angle))
            }
            .background(
                Circle()
                    .stroke(Color.red, lineWidth: 1)
                    .frame(width: knobSize + 4, height: knobSize + 4)
            )
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isDragging)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startAngle = angle
                        }
                        
                        // Calculate angle change based on vertical drag
                        let sensitivity: Double = 2.0
                        let angleChange = -Double(value.translation.height) * sensitivity
                        let newAngle = max(minAngle, min(maxAngle, startAngle + angleChange))
                        
                        if newAngle != angle {
                            angle = newAngle
                            updateFrequency()
                            
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            
            // Frequency display
            Text(frequencyDisplayString)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(minWidth: 50)
        }
        .onAppear {
            // Initialize angle based on current frequency
            angle = frequencyToAngle(frequency)
        }
        .onChange(of: frequency) { newFreq in
            // Update angle if frequency changed externally
            let newAngle = frequencyToAngle(newFreq)
            if abs(newAngle - angle) > 1.0 { // Avoid feedback loops
                angle = newAngle
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var normalizedFrequency: Double {
        // Convert frequency to 0-1 range for arc display
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logCurrent = log10(frequency)
        return Double((logCurrent - logMin) / (logMax - logMin))
    }
    
    private var frequencyDisplayString: String {
        if frequency >= 1000 {
            let kHz = frequency / 1000.0
            if kHz >= 10.0 {
                return String(format: "%.0fkHz", kHz)
            } else {
                return String(format: "%.1fkHz", kHz)
            }
        } else {
            return String(format: "%.0fHz", frequency)
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateFrequency() {
        let newFreq = angleToFrequency(angle)
        frequency = newFreq
        onFrequencyChange(newFreq)
    }
    
    private func angleToFrequency(_ angle: Double) -> Float {
        // Convert angle to normalized position (0-1)
        let normalizedPosition = (angle - minAngle) / (maxAngle - minAngle)
        
        // Use logarithmic scale for frequency (sounds more natural)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = logMin + Float(normalizedPosition) * (logMax - logMin)
        
        return pow(10, logFreq)
    }
    
    private func frequencyToAngle(_ freq: Float) -> Double {
        // Convert frequency to normalized position using log scale
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)
        let logFreq = log10(freq)
        let normalizedPosition = Double((logFreq - logMin) / (logMax - logMin))
        
        // Convert to angle
        return minAngle + normalizedPosition * (maxAngle - minAngle)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)
        
        FilterKnob(
            frequency: .constant(2000.0),
            onFrequencyChange: { freq in
                print("Filter frequency: \(freq)Hz")
            }
        )
    }
}
