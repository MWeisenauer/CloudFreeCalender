import SwiftUI

struct DayView: View {
    @EnvironmentObject var store: CalendarStore
    @State private var selectedDate = Date()
    @State private var showEditor = false
    @State private var editingEvent: CalendarEvent?
    @State private var newEventHour: Int = Calendar.current.component(.hour, from: Date())

    private let hourHeight: CGFloat = 60
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dayNavigator
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            timelineBackground
                            eventsLayer
                        }
                        .frame(height: hourHeight * 24)
                        .padding(.horizontal, 4)
                    }
                    .onAppear {
                        let hour = max(0, calendar.component(.hour, from: Date()) - 1)
                        proxy.scrollTo(hour, anchor: .top)
                    }
                }
            }
            .navigationTitle(formattedDate(selectedDate))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newEventHour = calendar.component(.hour, from: Date())
                        editingEvent = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Heute") {
                        selectedDate = Date()
                    }
                    .disabled(calendar.isDateInToday(selectedDate))
                }
            }
            .sheet(isPresented: $showEditor) {
                EventEditorView(existingEvent: editingEvent, prefillStart: prefillStart())
            }
            .refreshable { store.loadEvents() }
        }
    }

    // MARK: - Day navigator

    private var dayNavigator: some View {
        HStack {
            Button { changeDay(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
            Spacer()
            Button { changeDay(1) } label: { Image(systemName: "chevron.right") }
        }
    }

    // MARK: - Timeline background (hour lines + labels)

    private var timelineBackground: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 4) {
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                        .padding(.top, 8)
                }
                .frame(height: hourHeight)
                .id(hour)
            }
        }
    }

    // MARK: - Events layer

    private var eventsLayer: some View {
        let dayEvents = store.events(for: selectedDate).filter { !$0.isAllDay }
        return ZStack(alignment: .topLeading) {
            ForEach(dayEvents) { event in
                eventBlock(event)
                    .onTapGesture {
                        editingEvent = event
                        showEditor = true
                    }
            }
        }
    }

    private func eventBlock(_ event: CalendarEvent) -> some View {
        let start = minutesSinceMidnight(event.startDate)
        let duration = max(30, event.durationMinutes)
        let top  = CGFloat(start) / 60 * hourHeight
        let height = CGFloat(duration) / 60 * hourHeight

        return VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
            Text(timeRange(event))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(Color.accentColor.opacity(0.7))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.leading, 44)
        .padding(.trailing, 4)
        .offset(y: top)
    }

    // MARK: - Helpers

    private func changeDay(_ delta: Int) {
        selectedDate = calendar.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
    }

    private func minutesSinceMidnight(_ date: Date) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func hourLabel(_ hour: Int) -> String {
        let comps = DateComponents(hour: hour)
        let date = calendar.date(from: comps) ?? Date()
        let f = DateFormatter(); f.dateFormat = "HH"
        return f.string(from: date) + ":00"
    }

    private func timeRange(_ event: CalendarEvent) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "\(f.string(from: event.startDate)) – \(f.string(from: event.endDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d. MMMM"
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: date)
    }

    private func prefillStart() -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        comps.hour = newEventHour; comps.minute = 0
        return calendar.date(from: comps) ?? selectedDate
    }
}

#Preview {
    DayView()
        .environmentObject(CalendarStore())
        .preferredColorScheme(.dark)
}
