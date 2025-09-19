//
//  RootView.swift
//  jerry_for_loops
//
//  Created by Kevin Griffing on 9/16/25.
//


import SwiftUI

struct RootView: View {
    @AppStorage("hasSeenLanding") private var hasSeenLanding = false

    var body: some View {
        Group {
            if hasSeenLanding {
                LoopJamView()
            } else {
                LandingScreen()
            }
        }
    }
}
