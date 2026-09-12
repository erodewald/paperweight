// Paperweight/Views/AddDayExceptionSheet.swift
import SwiftUI

/// One sheet for adding and editing. Treatment comes first because it decides
/// which dates are allowed: a loosening treatment cannot start today, so today
/// is left out of the picker's range and one line says why.
struct AddDayExceptionSheet: View {
    @ObservedObject var vm: HomeViewModel
    let editing: DayException?
    @Environment(\.dismiss) private var dismiss

    private enum Kind: Hashable { case open, quiet, like }
    private enum Field { case from, to }

    @State private var kind: Kind = .open
    @State private var weekday: Int = DayKey.today().weekdayIndex()
    @State private var from: DayKey = DayKey.today().next()
    @State private var to: DayKey? = nil
    @State private var note: String = ""
    @State private var field: Field = .from
    @State private var errorText: String?

    private static let weekdayShort = ["S", "M", "T", "W", "T", "F", "S"]
    private static let kinds: [(value: Kind, label: String)] = [
        (.open, "Open all day"), (.quiet, "Quiet all day"), (.like, "Like a weekday…")]
    private static let weekdays: [(value: Int, label: String)] = (0..<7).map { ($0, weekdayShort[$0]) }

    private var treatment: DayException.Treatment {
        switch kind {
        case .open: return .openAllDay
        case .quiet: return .quietAllDay
        case .like: return .likeWeekday(weekday)
        }
    }

    /// Whether today is off the table for the chosen treatment.
    private var todayLoosens: Bool {
        vm.config.exceptionLoosens(treatment, on: .today())
    }

    private var earliestStart: DayKey {
        todayLoosens ? DayKey.today().next() : DayKey.today()
    }

    private var pickerRange: ClosedRange<Date> {
        let lower = (field == .from ? min(from, earliestStart) : from).date()
        return lower...Calendar.current.date(byAdding: .year, value: 2, to: lower)!
    }

    private var pickerSelection: Binding<Date> {
        Binding(
            get: { (field == .from ? from : (to ?? from)).date() },
            set: { picked in
                let key = DayKey(picked)
                if field == .from {
                    from = key
                    if let t = to, t < key { to = nil }
                } else {
                    to = key == from ? nil : key
                }
                errorText = nil
            })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PWSegmented(options: Self.kinds, selection: $kind)
                    if kind == .like {
                        PWSegmented(options: Self.weekdays, selection: $weekday)
                    }

                    GroupedCard {
                        fieldRow("From", value: from.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                 active: field == .from) { field = .from }
                        CardDivider()
                        fieldRow("To", value: to.map { $0.date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? "Same day",
                                 active: field == .to, muted: to == nil) { field = .to }
                        CardDivider()
                        HStack {
                            Text("Note").font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                            Spacer(minLength: 12)
                            TextField("Optional", text: $note)
                                .font(.grotesk(15))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(PW.textMuted)
                                .onChange(of: note) { _, new in
                                    if new.count > PaperweightConfig.dayExceptionNoteLimit {
                                        note = String(new.prefix(PaperweightConfig.dayExceptionNoteLimit))
                                    }
                                }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }

                    DatePicker("", selection: pickerSelection, in: pickerRange, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(PW.sage)
                        .labelsHidden()

                    if todayLoosens {
                        Text("Opening up takes effect from tomorrow, so today isn't offered.")
                            .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                            .frame(maxWidth: .infinity)
                    }
                    if let errorText {
                        Text(errorText)
                            .font(.grotesk(13)).foregroundStyle(PW.clay)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
            }
            .pwScreen()
            .navigationTitle(editing == nil ? "Add a day" : "Edit day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(PW.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.foregroundStyle(PW.sage)
                }
            }
        }
        .tint(PW.sage)
        .onAppear(perform: seed)
        .onChange(of: kind) { _, _ in clampStart() }
        .onChange(of: weekday) { _, _ in clampStart() }
    }

    private func fieldRow(_ title: String, value: String, active: Bool, muted: Bool = false,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.grotesk(15))
                    .foregroundStyle(muted ? PW.textMuted : PW.sage)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(active ? PW.sage.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func seed() {
        guard let e = editing else { return }
        switch e.treatment {
        case .openAllDay: kind = .open
        case .quietAllDay: kind = .quiet
        case .likeWeekday(let w): kind = .like; weekday = w
        }
        from = e.firstDay
        to = e.lastDay == e.firstDay ? nil : e.lastDay
        note = e.note
        clampStart()
    }

    /// If the treatment changed to one that cannot start today, move a
    /// today-start to tomorrow rather than leaving an unsaveable form. A start
    /// already in the past (a range that is running) is left alone: the replace
    /// rule keeps today as it is and applies the change from tomorrow.
    private func clampStart() {
        if from >= .today(), from < earliestStart { from = earliestStart }
        errorText = nil
    }

    private func save() {
        let new = DayException(id: editing?.id ?? UUID(), firstDay: from, lastDay: to ?? from,
                                treatment: treatment, note: note, createdAt: editing?.createdAt ?? Date())
        do {
            if let old = editing {
                try vm.replaceDayException(id: old.id, with: new)
            } else {
                try vm.addDayException(new)
            }
            dismiss()
        } catch let error as PaperweightConfig.ExceptionError {
            switch error {
            case .overlaps(let other):
                errorText = "Overlaps \(other.dateLabel()). Remove that one first."
            case .loosensToday:
                errorText = "Opening up takes effect from tomorrow."
            case .endsBeforeStart:
                errorText = "The last day is before the first."
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
