import SwiftUI

struct EventEditorView: View {
    @EnvironmentObject var store: CalendarStore
    @Environment(\.dismiss) private var dismiss

    var existingEvent: CalendarEvent?
    var prefillStart: Date = Date()

    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var isAllDay = false
    @State private var farbe: CalendarEventColor = .blau
    @State private var notes = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isNew: Bool { existingEvent == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Termin") {
                    TextField("Titel", text: $title)
                    Toggle("Ganztägig", isOn: $isAllDay.animation())
                    HStack {
                        Text("Farbe")
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(CalendarEventColor.allCases, id: \.rawValue) { c in
                                Circle()
                                    .fill(c.gradient)
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(.white.opacity(farbe == c ? 1 : 0), lineWidth: 2.5))
                                    .scaleEffect(farbe == c ? 1.15 : 1)
                                    .animation(.spring(duration: 0.2), value: farbe)
                                    .onTapGesture { farbe = c }
                            }
                        }
                    }
                }

                Section("Zeit") {
                    if isAllDay {
                        DatePicker("Datum", selection: $startDate, displayedComponents: .date)
                    } else {
                        DatePicker("Beginn", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Ende", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Notizen") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }

                if !isNew {
                    Section {
                        Button("Termin löschen", role: .destructive) {
                            deleteEvent()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Neuer Termin" : "Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Sichern") { saveEvent() }
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { prefill() }
        }
    }

    private func prefill() {
        if existingEvent == nil {
            startDate = prefillStart
            endDate = prefillStart.addingTimeInterval(3600)
        }
        guard let e = existingEvent else { return }
        title = e.title
        startDate = e.startDate
        endDate = e.endDate
        isAllDay = e.isAllDay
        farbe = e.farbe
        notes = e.notes
    }

    private func saveEvent() {
        isLoading = true
        errorMessage = nil
        var event = existingEvent ?? CalendarEvent()
        event.title = title.trimmingCharacters(in: .whitespaces)
        event.startDate = startDate
        event.endDate = isAllDay ? Calendar.current.startOfDay(for: startDate).addingTimeInterval(86399) : max(endDate, startDate + 60)
        event.isAllDay = isAllDay
        event.farbe = farbe
        event.notes = notes

        Task {
            do {
                try await store.saveEvent(event)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func deleteEvent() {
        guard let event = existingEvent else { return }
        isLoading = true
        Task {
            do {
                try await store.deleteEvent(event)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

#Preview {
    EventEditorView()
        .environmentObject(CalendarStore())
        .preferredColorScheme(.dark)
}
