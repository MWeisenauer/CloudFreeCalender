//
//  CloudFreeCalenderApp.swift
//  CloudFreeCalender
//
//  Created by Markus Weisenauer on 01.07.26.
//

import SwiftUI
import CoreData

@main
struct CloudFreeCalenderApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
