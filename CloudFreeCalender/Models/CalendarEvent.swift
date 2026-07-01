import Foundation

nonisolated struct CalendarEvent: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date().addingTimeInterval(3600)
    var isAllDay: Bool = false
    var farbe: CalendarEventColor = .blau
    var notes: String = ""
    var modifiedDate: Date = Date()
    var remoteFilename: String = ""

    var displayTitle: String { title.isEmpty ? "Neuer Termin" : title }

    var durationMinutes: Int {
        max(1, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    // File format:
    // TITLE:Meeting
    // START:2026-07-01T10:00:00Z
    // END:2026-07-01T11:00:00Z
    // MODIFIED:2026-07-01T09:00:00Z
    // ALLDAY:0
    // ---
    // optional notes

    static func encode(_ event: CalendarEvent) -> String {
        let iso = ISO8601DateFormatter()
        let header = [
            "TITLE:\(event.title)",
            "START:\(iso.string(from: event.startDate))",
            "END:\(iso.string(from: event.endDate))",
            "MODIFIED:\(iso.string(from: event.modifiedDate))",
            "ALLDAY:\(event.isAllDay ? 1 : 0)",
            "COLOR:\(event.farbe.rawValue)"
        ].joined(separator: "\n")
        return "\(header)\n---\n\(event.notes)"
    }

    static func decode(_ text: String, filename: String) -> CalendarEvent? {
        let iso = ISO8601DateFormatter()
        let parts = text.components(separatedBy: "\n---\n")
        guard parts.count >= 1 else { return nil }
        let headerLines = parts[0].components(separatedBy: "\n")
        let notes = parts.count >= 2 ? parts[1...].joined(separator: "\n---\n") : ""

        var event = CalendarEvent()
        event.notes = notes
        event.remoteFilename = filename
        let uuidStr = filename.hasSuffix(".txt") ? String(filename.dropLast(4)) : filename
        event.id = UUID(uuidString: uuidStr) ?? UUID()

        for line in headerLines {
            if line.hasPrefix("TITLE:")    { event.title        = String(line.dropFirst(6)) }
            else if line.hasPrefix("START:")    { event.startDate    = iso.date(from: String(line.dropFirst(6))) ?? Date() }
            else if line.hasPrefix("END:")      { event.endDate      = iso.date(from: String(line.dropFirst(4))) ?? Date() }
            else if line.hasPrefix("MODIFIED:") { event.modifiedDate = iso.date(from: String(line.dropFirst(9))) ?? Date() }
            else if line.hasPrefix("ALLDAY:")   { event.isAllDay     = line.dropFirst(7) == "1" }
            else if line.hasPrefix("COLOR:")    { event.farbe        = CalendarEventColor(rawValue: String(line.dropFirst(6))) ?? .blau }
        }
        guard !event.title.isEmpty else { return nil }
        return event
    }

    static func filename(for event: CalendarEvent) -> String {
        "\(event.id.uuidString).txt"
    }
}

extension CalendarEvent {
    func occursOn(_ date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        return startDate < nextDay && endDate > day
    }
}
