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
    @State private var talkingAboutMeals = false

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
                DaySummaryCard(totals: totals)
            }

            Section {
                Button {
                    talkingAboutMeals = true
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "mic.fill", color: .accentColor, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tell me what you ate")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Say it or snap it, and I'll log it")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ForEach(Meal.allCases) { meal in
                let mealEntries = entries.filter { $0.meal == meal.rawValue }
                Section {
                    ForEach(mealEntries) { entry in
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
                        .contentShape(Rectangle())
                        .draggable(dragToken(for: entry))
                        .dropDestination(for: String.self) { tokens, _ in
                            move(tokens, to: meal)
                        }
                        .contextMenu {
                            MoveToMealButtons(current: entry.meal) { entry.meal = $0.rawValue }
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(entry) }
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { context.delete(entry) }
                        }
                    }
                    Button {
                        addingTo = meal
                    } label: {
                        Label("Add food", systemImage: "plus.circle.fill")
                    }
                    .dropDestination(for: String.self) { tokens, _ in
                        move(tokens, to: meal)
                    }
                } header: {
                    MealHeader(meal: meal, calories: mealEntries.reduce(0) { $0 + $1.nutrients[.calories] })
                        .dropDestination(for: String.self) { tokens, _ in
                            move(tokens, to: meal)
                        }
                } footer: {
                    if meal == .breakfast && !entries.isEmpty {
                        Text("Hold a food to move it to another meal, or drag it onto one.")
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
        .sheet(isPresented: $talkingAboutMeals) {
            VoiceLogView(date: logDate)
        }
    }

    /// Identifies a log entry while it's dragged between meals.
    private func dragToken(for entry: LogEntry) -> String {
        guard let data = try? JSONEncoder().encode(entry.persistentModelID) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Moves dragged entries to `meal`. Returns false for anything that isn't one of today's entries.
    private func move(_ tokens: [String], to meal: Meal) -> Bool {
        var moved = false
        for token in tokens {
            guard let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(token.utf8)),
                  let entry = entries.first(where: { $0.persistentModelID == id }) else { continue }
            entry.meal = meal.rawValue
            moved = true
        }
        return moved
    }

    /// New entries on past days are stamped at noon of that day.
    private var logDate: Date {
        if Calendar.current.isDateInToday(date) { return Date() }
        return Calendar.current.startOfDay(for: date).addingTimeInterval(12 * 3600)
    }
}

/// "Move to Lunch" etc. for every meal except the current one, for context menus.
struct MoveToMealButtons: View {
    let current: String
    let onMove: (Meal) -> Void

    var body: some View {
        ForEach(Meal.allCases.filter { $0.rawValue != current }) { meal in
            Button("Move to \(meal.title)", systemImage: "arrow.right.circle") { onMove(meal) }
        }
    }
}

/// The calorie ring with the three macros beside it.
struct DaySummaryCard: View {
    let totals: NutrientValues
    @EnvironmentObject private var goals: GoalStore

    private var eaten: Double { totals[.calories] }
    private var target: Double { goals.target(for: .calories) }

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                RingView(progress: eaten / max(target, 1), color: eaten > target ? .red : .orange)
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text(formatAmount(eaten))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(remainingText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
            }
            .frame(width: 124, height: 124)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Nutrient.macros) { nutrient in
                    MacroBar(nutrient: nutrient, value: totals[nutrient], target: goals.target(for: nutrient))
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var remainingText: String {
        eaten > target ? "\(formatAmount(eaten - target)) over" : "\(formatAmount(target - eaten)) left"
    }
}

struct MacroBar: View {
    let nutrient: Nutrient
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(nutrient.name, systemImage: nutrient.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(nutrient.color)
                Spacer()
                Text("\(formatAmount(value)) / \(formatAmount(target)) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            CapsuleBar(progress: value / max(target, 1), color: nutrient.color, height: 6)
        }
    }
}

struct MealHeader: View {
    let meal: Meal
    let calories: Double

    var body: some View {
        HStack(spacing: 8) {
            IconBadge(symbol: meal.symbol, color: meal.color, size: 26)
            Text(meal.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if calories > 0 {
                Text("\(formatAmount(calories)) kcal")
                    .font(.subheadline)
            }
        }
        .textCase(nil)
        .padding(.bottom, 4)
    }
}

struct NutrientRow: View {
    let nutrient: Nutrient
    let value: Double
    let target: Double

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: nutrient.symbol, color: nutrient.color)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(nutrient.name)
                    if reachedGoal {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                    if overUpperLimit || overLimit {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                    Spacer()
                    Text("\(formatAmount(value)) / \(formatAmount(target)) \(nutrient.unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                CapsuleBar(progress: value / max(target, 1), color: barColor)
                if overUpperLimit, let limit = nutrient.upperLimit {
                    Text("Above the upper limit of \(formatAmount(limit)) \(nutrient.unit)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var overUpperLimit: Bool {
        guard let limit = nutrient.upperLimit else { return false }
        return value > limit
    }

    /// Over a "stay under" target such as sodium.
    private var overLimit: Bool {
        nutrient.isLimit && value > target
    }

    private var reachedGoal: Bool {
        !nutrient.isLimit && !overUpperLimit && value >= target
    }

    private var barColor: Color {
        overUpperLimit || overLimit ? .orange : nutrient.color
    }
}
