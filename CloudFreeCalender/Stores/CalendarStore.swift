import SwiftUI
import Combine

@MainActor
final class CalendarStore: ObservableObject {
    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var settings: FTPSSettings = FTPSSettings.load()

    func events(for date: Date) -> [CalendarEvent] {
        events.filter { $0.occursOn(date) }
            .sorted { $0.startDate < $1.startDate }
    }

    func events(forWeekContaining date: Date) -> [Date: [CalendarEvent]] {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        var result: [Date: [CalendarEvent]] = [:]
        for i in 0..<7 {
            let day = cal.date(byAdding: .day, value: i, to: weekStart)!
            result[cal.startOfDay(for: day)] = events(for: day)
        }
        return result
    }

    func loadEvents() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        let svc = CalendarService(settings: settings)
        Task {
            do {
                let fetched = try await svc.fetchAllEvents()
                self.events = fetched
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func saveEvent(_ event: CalendarEvent) async throws {
        var e = event
        e.modifiedDate = Date()
        if e.remoteFilename.isEmpty {
            e.remoteFilename = CalendarEvent.filename(for: e)
        }
        let svc = CalendarService(settings: settings)
        try await svc.uploadEvent(e)
        if let idx = events.firstIndex(where: { $0.id == e.id }) {
            events[idx] = e
        } else {
            events.append(e)
            events.sort { $0.startDate < $1.startDate }
        }
    }

    func deleteEvent(_ event: CalendarEvent) async throws {
        let svc = CalendarService(settings: settings)
        try await svc.deleteEvent(filename: event.remoteFilename)
        events.removeAll { $0.id == event.id }
    }

    func saveSettings(_ newSettings: FTPSSettings) {
        settings = newSettings
        settings.save()
    }
}
