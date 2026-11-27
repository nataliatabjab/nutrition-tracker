import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @State private var days = 7

    var body: some View {
        NavigationStack {
            InsightsContent(days: days, range: $days)
                .navigationTitle("Insights")
        }
    }
}

/// One day's totals, for days with at least one logged item.
private struct DayTotal: Identifiable {
    let day: Date
    let totals: NutrientValues
    var id: Date { day }
}

private struct NutrientAverage: Identifiable {
    let nutrient: Nutrient
    let average: Double
    let fraction: Double
    /// Days over a limit or over the upper intake level.
    let daysOver: Int
    var id: String { nutrient.rawValue }
}

private struct MacroPart: Identifiable {
    let name: String
    let kcal: Double
    let color: Color
    var id: String { name }
}

private struct FoodAmount: Identifiable {
    let name: String
    let amount: Double
    var id: String { name }
}

private struct InsightsContent: View {
    let days: Int
    @Binding var range: Int
    @Query private var entries: [LogEntry]
    @EnvironmentObject private var goals: GoalStore

    init(days: Int, range: Binding<Int>) {
        self.days = days
        _range = range
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        _entries = Query(filter: #Predicate<LogEntry> { $0.date >= start }, sort: \LogEntry.date)
    }

    private var dayTotals: [DayTotal] {
        let byDay = Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.date) }
        return byDay
            .map { day, items in
                DayTotal(day: day, totals: items.reduce(into: NutrientValues()) { $0 = $0.adding($1.nutrients) })
            }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        let logged = dayTotals
        List {
            Picker("Range", selection: $range) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if logged.isEmpty {
                EmptyIllustration(symbol: "chart.bar.xaxis", title: "No insights yet",
                                  message: "Log a few days of meals and your trends will show up here.")
            } else {
                overview(logged)
                caloriesChart(logged)
                macroSplit(logged)
                nutrientsToWatch(logged)
                topSources(.protein)
            }
        }
    }

    private func average(_ nutrient: Nutrient, _ logged: [DayTotal]) -> Double {
        logged.reduce(0) { $0 + $1.totals[nutrient] } / Double(max(logged.count, 1))
    }

    // MARK: Sections

    private func overview(_ logged: [DayTotal]) -> some View {
        let calories = average(.calories, logged)
        let protein = average(.protein, logged)
        return Section {
            HStack(spacing: 12) {
                StatTile(symbol: "calendar", color: .accentColor,
                         value: "\(logged.count)/\(days)", label: "days logged")
                StatTile(symbol: Nutrient.calories.symbol, color: Nutrient.calories.color,
                         value: formatAmount(calories), label: "avg kcal")
                StatTile(symbol: Nutrient.protein.symbol, color: Nutrient.protein.color,
                         value: "\(formatAmount(protein)) g", label: "avg protein")
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } footer: {
            Text("Averages count only the days you logged food.")
        }
    }

    private func caloriesChart(_ logged: [DayTotal]) -> some View {
        let target = goals.target(for: .calories)
        return Section("Calories") {
            Chart {
                ForEach(logged) { day in
                    BarMark(x: .value("Day", day.day, unit: .day),
                            y: .value("Calories", day.totals[.calories]))
                        .foregroundStyle(day.totals[.calories] > target ? Color.red.gradient : Color.orange.gradient)
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Target").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .frame(height: 180)
            .padding(.vertical, 8)
        }
    }

    private func macroSplit(_ logged: [DayTotal]) -> some View {
        let parts = [
            MacroPart(name: "Protein", kcal: average(.protein, logged) * 4, color: Nutrient.protein.color),
            MacroPart(name: "Carbs", kcal: average(.carbs, logged) * 4, color: Nutrient.carbs.color),
            MacroPart(name: "Fat", kcal: average(.fat, logged) * 9, color: Nutrient.fat.color),
        ]
        let total = max(parts.reduce(0) { $0 + $1.kcal }, 1)
        return Section("Where your calories come from") {
            HStack(spacing: 20) {
                Chart(parts) { part in
                    SectorMark(angle: .value("Calories", part.kcal), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(part.color.gradient)
                        .cornerRadius(4)
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(parts) { part in
                        HStack(spacing: 8) {
                            Circle().fill(part.color).frame(width: 10, height: 10)
                            Text(part.name)
                            Spacer()
                            Text("\(Int((part.kcal / total * 100).rounded()))%")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func nutrientsToWatch(_ logged: [DayTotal]) -> some View {
        let stats = Nutrient.micros.map { nutrient -> NutrientAverage in
            let avg = average(nutrient, logged)
            let target = goals.target(for: nutrient)
            let daysOver = logged.filter { day in
                let value = day.totals[nutrient]
                if nutrient.isLimit && value > target { return true }
                if let limit = nutrient.upperLimit, value > limit { return true }
                return false
            }.count
            return NutrientAverage(nutrient: nutrient, average: avg,
                                   fraction: target > 0 ? avg / target : 0, daysOver: daysOver)
        }
        let over = stats.filter { $0.daysOver > 0 }
        let low = stats.filter { !$0.nutrient.isLimit && $0.daysOver == 0 && $0.fraction < 0.7 }
            .sorted { $0.fraction < $1.fraction }
        let onTrack = stats.filter { !$0.nutrient.isLimit && $0.daysOver == 0 && $0.fraction >= 1 }

        return Group {
            if !over.isEmpty {
                Section("Over the limit") {
                    ForEach(over) { stat in
                        InsightRow(nutrient: stat.nutrient, color: .orange,
                                   headline: "Over on \(stat.daysOver) of \(logged.count) days",
                                   detail: stat.nutrient.isLimit
                                       ? "Averaging \(formatAmount(stat.average)) \(stat.nutrient.unit) a day."
                                       : "Above the upper limit of \(formatAmount(stat.nutrient.upperLimit ?? 0)) \(stat.nutrient.unit). Check supplements and very rich foods.")
                    }
                }
            }
            if !low.isEmpty {
                Section {
                    ForEach(low) { stat in
                        InsightRow(nutrient: stat.nutrient, color: stat.nutrient.color,
                                   headline: "\(Int((stat.fraction * 100).rounded()))% of your target on average",
                                   detail: "Try: \(stat.nutrient.goodSources)")
                    }
                } header: {
                    Text("Often low")
                } footer: {
                    Text("USDA data is missing some nutrients (often iodine and vitamin D) for many foods, so these can read lower than reality. Supplements aren't counted.")
                }
            }
            if !onTrack.isEmpty {
                Section("On track") {
                    Text(onTrack.map { $0.nutrient.name }.joined(separator: " · "))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func topSources(_ nutrient: Nutrient) -> some View {
        let byFood = Dictionary(grouping: entries, by: \.foodName)
            .map { name, items in FoodAmount(name: name, amount: items.reduce(0) { $0 + $1.nutrients[nutrient] }) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
        return Section("Top \(nutrient.name.lowercased()) sources") {
            ForEach(Array(byFood)) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text("\(formatAmount(item.amount)) \(nutrient.unit)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct StatTile: View {
    let symbol: String
    let color: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            IconBadge(symbol: symbol, color: color, size: 32)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct InsightRow: View {
    let nutrient: Nutrient
    let color: Color
    let headline: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: nutrient.symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(nutrient.name).font(.subheadline.weight(.semibold))
                Text(headline).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

extension Nutrient {
    /// Everyday foods that are good sources, shown when a nutrient runs low.
    var goodSources: String {
        switch self {
        case .calories: return "more regular meals and snacks"
        case .protein: return "Greek yogurt, eggs, chicken, fish, tofu, lentils"
        case .carbs: return "oats, rice, potatoes, fruit, bread"
        case .fat: return "olive oil, avocado, nuts, salmon"
        case .fiber: return "oats, lentils, beans, berries, chia seeds"
        case .addedSugar, .sodium: return "nothing extra needed"
        case .vitaminD: return "salmon, sardines, eggs, fortified milk. Most people in Canada need a supplement in winter, so ask your doctor."
        case .selenium: return "1–2 Brazil nuts, tuna, sardines, eggs, chicken"
        case .iron: return "lentils, spinach, beef, pumpkin seeds, with vitamin C to help absorption"
        case .zinc: return "pumpkin seeds, beef, chickpeas, cashews, yogurt"
        case .iodine: return "iodized salt, dairy, eggs, a little seaweed"
        case .magnesium: return "pumpkin seeds, almonds, spinach, black beans, dark chocolate"
        case .vitaminB12: return "fish, eggs, dairy, meat, fortified nutritional yeast"
        case .calcium: return "yogurt, milk, cheese, sardines, tofu. Keep it 4 hours away from levothyroxine."
        case .omega3: return "salmon, sardines, chia, flax, walnuts"
        }
    }
}
