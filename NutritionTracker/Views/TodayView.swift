import SwiftUI
import SwiftData

struct TodayView: View {
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            DayView(date: date)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(Calendar.current.isDateInToday(date))
                    }
                }
        }
    }

    private var title: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday().month().day())
    }

    private func shiftDay(_ days: Int) {
        date = Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
}

struct DayView: View {
    let date: Date
    @Query private var entries: [LogEntry]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var goals: GoalStore
    @State private var addingTo: Meal?

    init(date: Date) {
        self.date = date
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(
            filter: #Predicate<LogEntry> { $0.date >= start && $0.date < end },
            sort: \LogEntry.date
        )
    }

    private var totals: NutrientValues {
        entries.reduce(into: [:]) { $0 = $0.adding($1.nutrients) }
    }

    var body: some View {
        List {
            Section {
                CalorieSummary(eaten: totals[.calories], target: goals.target(for: .calories))
                ForEach(Nutrient.macros) { nutrient in
                    NutrientRow(nutrient: nutrient, value: totals[nutrient], target: goals.target(for: nutrient))
                }
            }

            ForEach(Meal.allCases) { meal in
                Section(meal.title) {
                    ForEach(entries.filter { $0.meal == meal.rawValue }) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(entry.foodName)
                                Text(entry.amountText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(formatAmount(entry.nutrients[.calories])) kcal")
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { context.delete(entry) }
                        }
                    }
                    Button {
                        addingTo = meal
                    } label: {
                        Label("Add food", systemImage: "plus")
                    }
                }
            }

            Section("Micronutrients") {
                ForEach(Nutrient.micros) { nutrient in
                    NutrientRow(nutrient: nutrient, value: totals[nutrient], target: goals.target(for: nutrient))
                }
            }
        }
        .sheet(item: $addingTo) { meal in
            AddFoodView(meal: meal, date: logDate)
        }
    }

    /// New entries on past days are stamped at noon of that day.
    private var logDate: Date {
        if Calendar.current.isDateInToday(date) { return Date() }
        return Calendar.current.startOfDay(for: date).addingTimeInterval(12 * 3600)
    }
}

struct CalorieSummary: View {
    let eaten: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(formatAmount(eaten))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("/ \(formatAmount(target)) kcal")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(remainingText)
                    .font(.subheadline)
                    .foregroundStyle(eaten > target ? .orange : .secondary)
            }
            ProgressView(value: min(eaten, target), total: max(target, 1))
        }
        .padding(.vertical, 4)
    }

    private var remainingText: String {
        eaten > target ? "\(formatAmount(eaten - target)) over" : "\(formatAmount(target - eaten)) left"
    }
}

struct NutrientRow: View {
    let nutrient: Nutrient
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nutrient.name)
                if overUpperLimit {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("\(formatAmount(value)) / \(formatAmount(target)) \(nutrient.unit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, target), total: max(target, 1))
                .tint(barColor)
            if overUpperLimit, let limit = nutrient.upperLimit {
                Text("Above the upper limit of \(formatAmount(limit)) \(nutrient.unit)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var overUpperLimit: Bool {
        guard let limit = nutrient.upperLimit else { return false }
        return value > limit
    }

    private var barColor: Color {
        if overUpperLimit { return .orange }
        if nutrient.isLimit { return value > target ? .red : .accentColor }
        return value >= target ? .green : .accentColor
    }
}
