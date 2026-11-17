# Nutrition Tracker

A personal iPhone app for tracking calories, macronutrients and micronutrients. All data stays on the phone.

## What it does so far

- Log foods to breakfast, lunch, dinner or snacks, by serving ("2 eggs"), by household portion ("1 cup") or by weight in grams.
- Search the USDA FoodData Central database, or create foods by hand.
- Daily totals against editable targets for calories, protein, carbs, fat, fiber, added sugar, sodium, vitamin D, selenium, iron, zinc, iodine, magnesium, vitamin B12, calcium and omega-3.
- A warning when a nutrient goes above its upper intake limit.
- Recipes: add ingredients and the number of servings, and the app works out the nutrients per serving.

Planned: barcode scanning, recipe import from a photo or text, and Apple Health / Oura sync.

## Installing on your iPhone

1. Install Xcode 16 or later from the Mac App Store.
2. Download this repository and open `NutritionTracker.xcodeproj`.
3. In Xcode, select the **NutritionTracker** target, open **Signing & Capabilities**, and choose your Apple ID under **Team**.
4. Plug in your iPhone, pick it as the run destination at the top of the window, and press **Run** (▶).
5. The first time, the phone asks you to turn on Developer Mode (Settings → Privacy & Security) and to trust your developer certificate (Settings → General → VPN & Device Management).

With a free Apple ID the app stops opening after 7 days until you press Run again. Your data is kept.

## USDA search

Search works straight away with a shared demo key, which allows only a few searches per hour. For normal use, get a free key at <https://fdc.nal.usda.gov/api-key-signup> and paste it into the app's Settings tab.

USDA data has gaps: iodine and added sugar are missing for many foods, so those totals can read low.
