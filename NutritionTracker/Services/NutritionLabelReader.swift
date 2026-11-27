import Foundation

/// What Claude read from a photo of a nutrition label.
struct LabelReading {
    /// The serving size in household terms, e.g. "2/3 cup" or "1 bar".
    var servingLabel: String
    /// Weight of one serving in grams, when the label gives it.
    var servingGrams: Double?
    /// Nutrients for one serving. Only nutrients the label shows are present.
    var nutrients: NutrientValues
    var productName: String
    var brand: String
    var note: String
}

/// Reads a nutrition facts label from a photo or screenshot with Claude.
enum NutritionLabelReader {
    enum ReadError: LocalizedError {
        case notRead(String)

        var errorDescription: String? {
            switch self {
            case .notRead(let message):
                return message.isEmpty ? "Couldn't read a nutrition label in that photo. Try a closer, sharper photo." : message
            }
        }
    }

    static func read(photo: Data, name: String, brand: String, apiKey: String) async throws -> LabelReading {
        var request = "Read this nutrition label and call record_label."
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty {
            request += " The food is \(trimmedName)\(trimmedBrand.isEmpty ? "" : " by \(trimmedBrand)")."
        }
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": [ClaudeClient.imageBlock(jpeg: photo), ClaudeClient.textBlock(request)],
        ]]

        let response = try await ClaudeClient.send(apiKey: apiKey, system: system, tools: [tool], messages: messages)
        let stopReason = response["stop_reason"] as? String ?? ""
        if stopReason == "refusal" { throw ClaudeClient.ClaudeError.refused }
        if stopReason == "max_tokens" { throw ClaudeClient.ClaudeError.cutOff }
        let content = response["content"] as? [[String: Any]] ?? []

        guard let use = content.first(where: { ($0["type"] as? String) == "tool_use" && ($0["name"] as? String) == "record_label" }),
              let input = use["input"] as? [String: Any] else {
            // Claude answered in words, usually because the photo isn't a readable label.
            let text = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: " ")
            throw ReadError.notRead(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let readable = input["readable"] as? Bool, !readable {
            throw ReadError.notRead(input["note"] as? String ?? "")
        }

        var nutrients: NutrientValues = [:]
        let raw = input["nutrients"] as? [String: Any] ?? [:]
        for nutrient in Nutrient.allCases {
            if let value = jsonNumber(raw[nutrient.rawValue]) {
                nutrients[nutrient] = max(value, 0)
            }
        }
        let grams = jsonNumber(input["serving_grams"])
        return LabelReading(
            servingLabel: (input["serving_size"] as? String ?? "").trimmingCharacters(in: .whitespaces),
            servingGrams: (grams ?? 0) > 0 ? grams : nil,
            nutrients: nutrients,
            productName: input["product_name"] as? String ?? "",
            brand: input["brand"] as? String ?? "",
            note: input["note"] as? String ?? ""
        )
    }

    private static let system = """
    You read nutrition facts labels from photos for Natalia's personal nutrition tracking app. The photo may be \
    a picture of a package or a screenshot, possibly at an angle, cropped or from another country.

    Record the values for ONE serving as printed on the label:
    - serving_size: the household measure only, without the weight, e.g. "2/3 cup", "1 bar", "3 cookies", \
    "1 container". If the label gives only a weight, use that, e.g. "30 g".
    - serving_grams: the weight of one serving in grams, e.g. 55 for "2/3 cup (55g)". For drinks given in ml, \
    use the ml value (1 ml is about 1 g). Use null if the label shows no weight or volume.
    - If the label has two columns (per serving and per package), use the per-serving column. If it only gives \
    values per 100 g, record serving_size "100 g" and serving_grams 100.
    - Convert units to the ones in the schema (sodium in mg, vitamin D in mcg; 1 mcg vitamin D = 40 IU). If a \
    vitamin or mineral is shown only as % Daily Value, convert it with the US FDA daily values (vitamin D 20 mcg, \
    calcium 1300 mg, iron 18 mg, magnesium 420 mg, zinc 11 mg, selenium 55 mcg, iodine 150 mcg, \
    vitamin B12 2.4 mcg).
    - Use null for any nutrient the label doesn't show. Don't estimate missing nutrients.
    - "Total sugars" is not added sugar; only record addedSugar from an "Includes Xg Added Sugars" line.

    If the photo isn't a nutrition label or is too blurry to read, call record_label with readable false and \
    say what went wrong in note. Always respond by calling record_label.
    """

    private static let tool: [String: Any] = {
        var nutrientProperties: [String: Any] = [:]
        for nutrient in Nutrient.allCases {
            nutrientProperties[nutrient.rawValue] = [
                "type": ["number", "null"],
                "description": "\(nutrient.name) in \(nutrient.unit) per serving, or null if not on the label",
            ] as [String: Any]
        }
        return [
            "name": "record_label",
            "description": "Record the nutrition facts read from the label.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "readable": ["type": "boolean", "description": "False if no nutrition label could be read."] as [String: Any],
                    "serving_size": ["type": "string", "description": "Household serving size, e.g. \"2/3 cup\"."] as [String: Any],
                    "serving_grams": ["type": ["number", "null"], "description": "Weight of one serving in grams."] as [String: Any],
                    "nutrients": [
                        "type": "object",
                        "properties": nutrientProperties,
                        "required": Nutrient.allCases.map(\.rawValue),
                    ] as [String: Any],
                    "product_name": ["type": "string", "description": "Product name if visible, else empty."] as [String: Any],
                    "brand": ["type": "string", "description": "Brand if visible, else empty."] as [String: Any],
                    "note": ["type": "string", "description": "Anything uncertain, or an empty string."] as [String: Any],
                ] as [String: Any],
                "required": ["readable", "serving_size", "serving_grams", "nutrients", "product_name", "brand", "note"],
            ] as [String: Any],
        ]
    }()
}
