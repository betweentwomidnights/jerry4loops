//
//  jerry_for_loopsApp.swift
//  jerry-for-loops
//
//  Created by Kevin Griffing on 6/17/25.
//

import SwiftUI

@main
struct jerry_for_loopsApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
