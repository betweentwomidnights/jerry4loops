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
            RootView()
                             .environment(\.managedObjectContext, persistenceController.container.viewContext)
                             .preferredColorScheme(.dark)
                             .statusBarHidden(true)
        }
    }
    
    init() {
        // Configure global app appearance for loop jam
        setupLoopJamAppearance()
    }
    
    private func setupLoopJamAppearance() {
        // Configure navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.black
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        
        // Configure tab bar appearance
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.black
        
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
}
