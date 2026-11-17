import SwiftUI
import PhotosUI
import UIKit

/// What the My Foods list is narrowed to.
enum FoodFilter: Hashable {
    case all
    case recipes
    case category(FoodCategory)
}

extension Food {
    func matches(_ filter: FoodFilter, query: String) -> Bool {
        if !query.isEmpty && !name.localizedCaseInsensitiveContains(query) && !brand.localizedCaseInsensitiveContains(query) {
            return false
        }
        switch filter {
        case .all: return true
        case .recipes: return isRecipe
        case .category(let category): return foodCategory == category
        }
    }
}

/// A scrolling row of chips: All, Recipes, then each category that has foods in it.
struct CategoryFilterBar: View {
    @Binding var selection: FoodFilter
    let foods: [Food]

    private var usedCategories: [FoodCategory] {
        FoodCategory.allCases.filter { category in foods.contains { $0.foodCategory == category } }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", filter: .all)
                if foods.contains(where: \.isRecipe) {
                    chip("📖 Recipes", filter: .recipes)
                }
                ForEach(usedCategories) { category in
                    chip("\(category.emoji) \(category.title)", filter: .category(category))
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func chip(_ title: String, filter: FoodFilter) -> some View {
        let isSelected = selection == filter
        return Button {
            selection = isSelected ? .all : filter
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A recipe photo when there is one, otherwise the category emoji or a generic icon.
struct FoodThumbnail: View {
    let food: Food?
    /// Shown when there is no saved food, e.g. for a USDA search result.
    var fallbackCategory: FoodCategory? = nil
    var size: CGFloat = 40

    var body: some View {
        if let data = food?.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else if let category = food?.foodCategory ?? fallbackCategory {
            Text(category.emoji)
                .font(.system(size: size * 0.5))
                .frame(width: size, height: size)
                .background(Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            IconBadge(symbol: food?.isRecipe == true ? "book.fill" : "fork.knife",
                      color: food?.isRecipe == true ? .orange : .accentColor, size: size)
        }
    }
}

/// A list row for a saved food or recipe.
struct FoodRow: View {
    let food: Food

    var body: some View {
        HStack(spacing: 12) {
            FoodThumbnail(food: food)
            VStack(alignment: .leading) {
                Text(food.name)
                Text("\(formatAmount(food.nutrients[.calories])) kcal per \(food.servingLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CategoryPicker: View {
    @Binding var category: String
    var recipe = false

    var body: some View {
        Picker("Category", selection: $category) {
            Text("None").tag("")
            ForEach(recipe ? FoodCategory.recipeFirst : FoodCategory.allCases) { category in
                Text("\(category.emoji) \(category.title)").tag(category.rawValue)
            }
        }
    }
}

extension FoodCategory {
    /// Dish-style categories first, for recipes.
    static var recipeFirst: [FoodCategory] {
        let dishes: [FoodCategory] = [.breakfast, .meals, .salads, .desserts, .snacksSweets, .drinks]
        return dishes + allCases.filter { !dishes.contains($0) }
    }
}

/// Lets the user pick a photo from their library and stores it downsized.
struct PhotoField: View {
    @Binding var photoData: Data?
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 12) {
            if let data = photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(photoData == nil ? "Add photo" : "Change photo", systemImage: "photo")
                }
                if photoData != nil {
                    Spacer()
                    Button("Remove", role: .destructive) {
                        photoData = nil
                        item = nil
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .onChange(of: item) { _, newItem in
            Task {
                guard let data = try? await newItem?.loadTransferable(type: Data.self) else { return }
                photoData = Self.downsized(data)
            }
        }
    }

    /// Recipe photos only need to look good on a phone, so keep them small.
    static func downsized(_ data: Data, maxDimension: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
