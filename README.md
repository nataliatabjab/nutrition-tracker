# Nutrition Tracker

A personal iPhone app for tracking calories, macronutrients and micronutrients. All data stays on the phone.

## What it does so far

- Log foods to breakfast, lunch, dinner or snacks, by serving ("2 eggs"), by household portion ("1 cup") or by weight in grams.
- Search the USDA FoodData Central database, or create foods by hand.
- Daily totals against editable targets for calories, protein, carbs, fat, fiber, added sugar, sodium, vitamin D, selenium, iron, zinc, iodine, magnesium, vitamin B12, calcium and omega-3.
- A warning when a nutrient goes above its upper intake limit.
- Recipes: add ingredients and the number of servings, and the app works out the nutrients per serving.
- Log by whole units like 1 apple or 2 eggs. Units come from USDA, and you can add your own.
- Photos on recipes, and categories to filter My Foods.
- Insights: calorie trend, where your calories come from, nutrients that are often low or over the limit, and top protein sources.

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

## Tell me what you ate

On the Today screen, tap **Tell me what you ate** and describe your meals out loud, for example: "For breakfast I had 3 scrambled eggs and a cold brew with about a cup of Silk Original oat milk, and for lunch…". You can also type, and add photos of a plate or a nutrition label.

1. Your voice is turned into text by Apple's speech recognition, on the iPhone itself where the phone supports it (it does for English on recent iPhones). You can edit the text before sending.
2. Claude splits it into foods and meals, looks each one up in My Foods and the USDA database, and works out the amounts in grams.
3. If an amount really matters and is unclear ("some pasta", oil used for cooking), it asks a few quick questions with tap-to-answer suggestions. Answer by tapping, talking or typing.
4. You get a list grouped by meal with calories and macros. Tap an item to change its name, meal or portion, swipe to remove it, or just say what's wrong ("it was 2 eggs, not 3"). Nothing is logged until you tap **Log all**.

Foods matched from USDA are saved to My Foods (you can turn this off on the review screen), so the next time you mention them they're found straight away. Where USDA has no value for a nutrient (often iodine), Claude's estimate fills the gap; items with no good match use Claude's estimate entirely and are marked as such.

This needs a Claude API key: create one at <https://console.anthropic.com/settings/keys> and paste it into Settings. It's stored in the iPhone Keychain. A logging session usually costs about 10 to 30 cents. The text and any photos are sent to Claude; the audio recording isn't.
