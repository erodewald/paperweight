// Paperweight/Views/DayExceptionsView.swift
import SwiftUI

/// Planned days off and quiet days. A `List` rather than a `GroupedCard` so
/// swipe-to-remove comes for free; styled to sit with the grouped cards.
struct DayExceptionsView: View {
    @ObservedObject var vm: HomeViewModel

    /// One sheet, one presentation target: SwiftUI honours only one `.sheet`
    /// per view, so add and edit share it.
    private enum SheetTarget: Identifiable {
        case add
        case edit(DayException)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let e): return e.id.uuidString
            }
        }
    }
    @State private var sheet: SheetTarget?

    private var today: DayKey { .today() }
    private var upcoming: [DayException] { vm.config.upcomingDayExceptions() }
    private var current: DayException? { upcoming.first { $0.covers(today) } }
    private var later: [DayException] { upcoming.filter { !$0.covers(today) } }

    var body: some View {
        List {
            if let current {
                section("Today") { row(current) }
            }
            section("Upcoming") {
                if later.isEmpty && current == nil {
                    empty
                } else if later.isEmpty {
                    Text("Nothing more planned.")
                        .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                        .listRowBackground(PW.surface)
                } else {
                    ForEach(later) { row($0) }
                }
            }
            Section {
                VStack(spacing: 2) {
                    Text("A day off has to be set the day before.")
                    Text("A quiet day can start right now.")
                }
                .font(.grotesk(13)).foregroundStyle(PW.textFaint)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .pwScreen()
        .safeAreaInset(edge: .bottom) {
            AccentButton(title: String(localized: "Add a day", bundle: L10n.bundle)) { sheet = .add }
                .padding(.horizontal, 20).padding(.bottom, 12)
                .background(PW.black.opacity(0.9))
        }
        .navigationTitle("Days off & quiet days")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { sheet = .add } label: {
                    Image(systemName: "plus").foregroundStyle(PW.sage)
                }
            }
        }
        .sheet(item: $sheet) { target in
            switch target {
            case .add:
                AddDayExceptionSheet(vm: vm, editing: nil)
                    .presentationDragIndicator(.visible)
            case .edit(let e):
                AddDayExceptionSheet(vm: vm, editing: e)
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Section {
            content()
        } header: {
            Text(title).pwScreenLabel()
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("Nothing planned.")
                .font(.spectral(16, italic: true)).foregroundStyle(PW.textPrimary)
            Text("Holidays, trips, exam days. Add one and the week bends around it.")
                .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .listRowBackground(PW.surface)
    }

    private func row(_ e: DayException) -> some View {
        Button { sheet = .edit(e) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.dateLabel())
                        .font(.grotesk(15)).foregroundStyle(PW.textPrimary)
                    Spacer(minLength: 8)
                    pill(e.treatment)
                }
                if let line = secondLine(e) {
                    Text(line)
                        .font(.grotesk(13)).foregroundStyle(PW.textMuted)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(PW.surface)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                vm.removeDayException(id: e.id)
            } label: { Text("Remove") }
                .tint(PW.clay)
        }
    }

    /// Short facts under the date, joined by a middle dot. Each fact is its own
    /// key so nothing is glued from fragments.
    private func secondLine(_ e: DayException) -> String? {
        let b = L10n.bundle
        var parts: [String] = []
        if e.lastDay == today {
            parts.append(String(localized: "Ends tonight", bundle: b, comment: "A planned day whose last day is today"))
            if vm.truncatedDayExceptionIDs.contains(e.id) {
                parts.append(String(localized: "the change lands tomorrow", bundle: b,
                                    comment: "After 'Ends tonight': an edit or removal applies from tomorrow"))
            } else if !e.note.isEmpty {
                parts.append(e.note)
            }
        } else if !e.note.isEmpty {
            parts.append(e.note)
        }
        if e.dayCount() > 1 {
            parts.append(String(localized: "\(e.dayCount()) days", bundle: b,
                                comment: "Length of a planned range; has a plural rule"))
        }
        guard !parts.isEmpty else { return nil }
        let separator = String(localized: " · ", bundle: b, comment: "Joins short facts on one line; keep the spaces")
        return parts.joined(separator: separator)
    }

    private func pill(_ t: DayException.Treatment) -> some View {
        let (fg, bg, border): (Color, Color, Color) = {
            switch t {
            case .openAllDay: return (PW.sage, .clear, PW.sage.opacity(0.5))
            case .quietAllDay: return (PW.moss, PW.moss.opacity(0.18), PW.moss.opacity(0.7))
            case .likeWeekday: return (PW.textMuted, .clear, Color.white.opacity(0.18))
            }
        }()
        return Text(t.title())
            .font(.grotesk(13))
            .foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(bg)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
