import SwiftUI

struct WeekView: View {
    @EnvironmentObject var store: CalendarStore
    @State private var weekStart = Calendar.current.startOfWeek(for: Date())
    @State private var showEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var tapDate = Date()

    private let calendar = Calendar.current
    private let columnCount = 7

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekNavigator
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
                weekHeader
                Divider()
                ScrollView {
                    weekGrid
                }
            }
            .navigationTitle(weekTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        editingEvent = nil
                        tapDate = Date()
                        showEditor = true
                    } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Heute") {
                        weekStart = calendar.startOfWeek(for: Date())
                    }
                }
            }
            .sheet(isPresented: $showEditor) {
                EventEditorView(existingEvent: editingEvent, prefillStart: tapDate)
            }
            .refreshable { store.loadEvents() }
        }
    }

    // MARK: - Navigator

    private var weekNavigator: some View {
        HStack {
            Button { changeWeek(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(weekTitle).font(.subheadline).fontWeight(.semibold)
            Spacer()
            Button { changeWeek(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    // MARK: - Header (Mon–Sun)

    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekDays, id: \.self) { day in
                VStack(spacing: 2) {
                    Text(weekdayAbbr(day))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ZStack {
                        Circle()
                            .fill(calendar.isDateInToday(day) ? Color.accentColor : Color.clear)
                            .frame(width: 28, height: 28)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.caption)
                            .fontWeight(calendar.isDateInToday(day) ? .bold : .regular)
                            .foregroundStyle(calendar.isDateInToday(day) ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Week grid

    private var weekGrid: some View {
        let byDay = weekDays.map { day -> (Date, [CalendarEvent]) in
            (day, store.events(for: day))
        }
        return HStack(alignment: .top, spacing: 0) {
            ForEach(byDay, id: \.0) { day, events in
                VStack(spacing: 4) {
                    ForEach(events) { event in
                        Button {
                            editingEvent = event
                            showEditor = true
                        } label: {
                            Text(event.title)
                                .font(.caption2)
                                .lineLimit(2)
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(event.farbe.gradient)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                    if events.isEmpty {
                        Color.clear.frame(height: 4)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    tapDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                    editingEvent = nil
                    showEditor = true
                }
                if day != weekDays.last {
                    Divider()
                }
            }
        }
        .padding(.top, 8)
        .frame(minHeight: 300)
    }

    // MARK: - Helpers

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekTitle: String {
        let f = DateFormatter()
        f.dateFormat = "d. MMM"
        f.locale = Locale(identifier: "de_DE")
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let yearF = DateFormatter(); yearF.dateFormat = "yyyy"
        return "\(f.string(from: weekStart)) – \(f.string(from: end)), \(yearF.string(from: weekStart))"
    }

    private func changeWeek(_ delta: Int) {
        weekStart = calendar.date(byAdding: .weekOfYear, value: delta, to: weekStart) ?? weekStart
    }

    private func weekdayAbbr(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; f.locale = Locale(identifier: "de_DE")
        return f.string(from: date).capitalized
    }
}

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        var comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Montag
        return self.date(from: comps) ?? startOfDay(for: date)
    }
}

#Preview {
    WeekView()
        .environmentObject(CalendarStore())
        .preferredColorScheme(.dark)
}
