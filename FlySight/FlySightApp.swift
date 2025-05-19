//
//  FlySightApp.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI
import FlySightCore // Ensure this is imported

@main
struct FlySightApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject var bluetoothManager = FlySightCore.BluetoothManager() // Correct: Use @StateObject

    var body: some Scene {
        WindowGroup {
            ContentView(bluetoothManager: bluetoothManager) // Pass as an ObservedObject
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
