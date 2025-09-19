//
//  ReverbKnob.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 6/18/25.
//


import SwiftUI

struct ReverbKnob: View {
    @Binding var reverbAmount: Float
    let onReverbChange: (Float) -> Void
    
    // Knob state
    @State private var angle: Double = 0
    @State private var startAngle: Double = 0
    @State private var isDragging: Bool = false
    
    // Constants
    private let minAmount: Float = 0.0      // 0% = completely dry
    private let maxAmount: Float = 100.0    // 100% = very wet with long decay
    private let minAngle: Double = -135     // Start angle
    private let maxAngle: Double = 135      // End angle
    private let knobSize: CGFloat = 45
    
    var body: some View {
        VStack(spacing: 4) {
            Text("REVERB")
                .font(.caption2)
                .foregroundColor(.gray)
            
            // Main knob
            ZStack {
                // Background circle
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: knobSize, height: knobSize)
                
                // Active arc showing reverb amount
                Circle()
                    .trim(from: 0, to: normalizedAmount)
                    .stroke(
                        LinearGradient(
                            colors: reverbGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: knobSize - 8, height: knobSize - 8)
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
                    .stroke(reverbBorderColor, lineWidth: 1)
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
                            updateReverbAmount()
                            
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            
            // Reverb amount display
            Text(reverbDisplayString)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(minWidth: 50)
        }
        .onAppear {
            // Initialize angle based on current reverb amount
            angle = amountToAngle(reverbAmount)
        }
        .onChange(of: reverbAmount) { newAmount in
            // Update angle if reverb amount changed externally
            let newAngle = amountToAngle(newAmount)
            if abs(newAngle - angle) > 1.0 { // Avoid feedback loops
                angle = newAngle
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var normalizedAmount: Double {
        // Convert reverb amount to 0-1 range for arc display
        return Double((reverbAmount - minAmount) / (maxAmount - minAmount))
    }
    
    private var reverbDisplayString: String {
        if reverbAmount < 1.0 {
            return "DRY"
        } else if reverbAmount < 10.0 {
            return String(format: "%.0f%%", reverbAmount)
        } else {
            return String(format: "%.0f%%", reverbAmount)
        }
    }
    
    private var reverbGradientColors: [Color] {
        // Color gradient based on reverb amount
        if reverbAmount < 20 {
            return [.gray, .blue]  // Dry to subtle
        } else if reverbAmount < 60 {
            return [.blue, .purple]  // Subtle to medium
        } else {
            return [.purple, .pink]  // Medium to ethereal
        }
    }
    
    private var reverbBorderColor: Color {
        if reverbAmount < 5 {
            return .gray
        } else if reverbAmount < 30 {
            return .blue
        } else if reverbAmount < 70 {
            return .purple  
        } else {
            return .pink
        }
    }
    
    // MARK: - Helper Methods
    
    private func updateReverbAmount() {
        let newAmount = angleToAmount(angle)
        reverbAmount = newAmount
        onReverbChange(newAmount)
    }
    
    private func angleToAmount(_ angle: Double) -> Float {
        // Convert angle to normalized position (0-1)
        let normalizedPosition = (angle - minAngle) / (maxAngle - minAngle)
        
        // Linear mapping from 0-100%
        return minAmount + Float(normalizedPosition) * (maxAmount - minAmount)
    }
    
    private func amountToAngle(_ amount: Float) -> Double {
        // Convert reverb amount to normalized position
        let normalizedPosition = Double((amount - minAmount) / (maxAmount - minAmount))
        
        // Convert to angle
        return minAngle + normalizedPosition * (maxAngle - minAngle)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)
        
        HStack(spacing: 20) {
            ReverbKnob(
                reverbAmount: .constant(0.0),
                onReverbChange: { amount in
                    print("Reverb: \(amount)%")
                }
            )
            
            ReverbKnob(
                reverbAmount: .constant(50.0),
                onReverbChange: { amount in
                    print("Reverb: \(amount)%")
                }
            )
            
            ReverbKnob(
                reverbAmount: .constant(85.0),
                onReverbChange: { amount in
                    print("Reverb: \(amount)%")
                }
            )
        }
    }
}
