import SwiftUI

struct ContentView: View {
    @StateObject private var store = CalendarStore()

    var body: some View {
        TabView {
            DayView()
                .tabItem {
                    Label("Tag", systemImage: "calendar.day.timeline.left")
                }

            WeekView()
                .tabItem {
                    Label("Woche", systemImage: "calendar")
                }

            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gear")
                }
        }
        .environmentObject(store)
        .preferredColorScheme(.dark)
        .task { store.loadEvents() }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
