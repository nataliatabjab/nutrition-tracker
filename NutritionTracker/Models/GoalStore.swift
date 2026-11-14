import Foundation

/// Daily targets, saved on the device. Nutrients without a custom target use their default.
final class GoalStore: ObservableObject {
    private static let key = "nutrientTargets"

    @Published var targets: NutrientValues {
        didSet { UserDefaults.standard.set(targets, forKey: Self.key) }
    }

    init() {
        targets = UserDefaults.standard.dictionary(forKey: Self.key) as? NutrientValues ?? [:]
    }

    func target(for nutrient: Nutrient) -> Double {
        targets[nutrient.rawValue] ?? nutrient.defaultTarget
    }

    func reset() {
        targets = [:]
    }
}
