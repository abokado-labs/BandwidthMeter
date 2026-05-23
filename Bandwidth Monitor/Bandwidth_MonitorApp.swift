//
//  Bandwidth_MonitorApp.swift
//  Bandwidth Monitor
//
//  Created by Bob Kitchen on 5/23/26.
//

import SwiftUI
import CoreData

@main
struct Bandwidth_MonitorApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
