# Angelina's Nutrition

An iOS fitness app where your eating plan shapes your training. Pick a goal (lose fat, tone, build muscle, stay healthy), where you train (gym or home, with the equipment you own), and your level. The app builds a daily workout from an exercise database of about 870 exercises.

## Requirements

- Xcode 26+
- iOS 18+

## Getting started

```sh
open AngelinasNutrition.xcodeproj
```

Choose an iPhone simulator and press Run. The project uses Xcode's synchronized folders, so new files under `AngelinasNutrition/` are picked up without editing the project file.

## Structure

| Folder | What's inside |
| --- | --- |
| `App/` | App entry point, onboarding/tab routing |
| `DesignSystem/` | Color, type and spacing tokens (light + dark), shared components |
| `Models/` | `Exercise`, `UserProfile`, `FitnessGoal`, `PersonalPlan` (eating plan + training program) |
| `Services/` | `ExerciseLibrary` (bundled DB), `PlanLibrary` (personal plans), `ProfileStore` (persistence), `WorkoutPlanner` |
| `Features/` | Onboarding, Today, Workouts (program + library), Nutrition (menu, recipes, guides), Profile |
| `Resources/exercises.json` | Bundled exercise database |
| `Resources/Plans/*.json` | Personal plans (Tsveti, Hristomir), bilingual BG/EN |

## Personal plans

Each file in `Resources/Plans/` holds one person's coach-written plan:

- **Nutrition**: daily targets, every meal option (breakfast, lunch, dinner, snacks) with ingredients, preparation, kcal and protein, a sample week, rules and the adjustment table.
- **Training**: weekly schedule (with A/B rotation), workouts with sets, rest, starting weights and cues, warm-up, safety notes and progression rules. Exercises link to the exercise database by `exerciseID` for photos and instructions.

Each program exercise also has `tracking` (sets, rep/second range, load type, starting weight, increment, rest) used by `ProgressionCoach`, and `alternatives` the user can swap in. Adjustment table rows carry a `trigger` that `PlanAdvisor` matches against weekly check-in averages. Workouts and check-ins are stored on-device by `TrainingLog` (`Application Support/training-log.json`).

Ingredients carry a `shop` array (product key from `Resources/grocery-catalog.json`, quantity, unit) that `GroceryCalculator` totals into the weekly shopping list; lines without an amount (spices, herbs) are listed as "to taste". The user's chosen meal per day is stored by `WeekMenuStore` (`Application Support/week-menus.json`) and starts from the plan's sample week.

All text is `{ "bg": …, "en": … }`; the app shows Bulgarian by default with a BG/EN switch on plan screens. Add a new plan by dropping in a JSON file and adding its name to `PlanLibrary.planFiles`.

## Exercise data

Exercises come from [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense / public domain). Images load from that repository's GitHub hosting. To refresh the bundled data:

```sh
./scripts/update-exercises.sh
```

## Roadmap

1. ~~Foundation: design system, exercise database, onboarding, daily workout~~
2. ~~Personal plans: Tsveti's and Hristomir's eating plans and training programs~~
3. ~~Workout tracking: live sessions, the program's "Дневник", progression rules, exercise alternatives, weekly check-ins with plan advice~~
4. ~~Weekly groceries: pick meals for the week from all the plan's options, get a shopping list~~
5. ~~Ask Claude (own API key) and one-page plan/program summaries~~
6. ~~Food diary and calorie calculator (MyFitnessPal-style)~~
7. Plan sync: training adapts to what was eaten that day

## AI assistant

The ✨ button opens a chat with the user's choice of **Claude** (Anthropic), **ChatGPT** (OpenAI) or **Gemini** (Google), connected with that provider's API key (consumer subscriptions can't be used by other apps). The connect screen opens the provider's console in-app to create a key or takes a pasted one, checks it by listing the models, and lets the user pick a model (`AIProviders.swift`; keys per provider in the Keychain). PDF import always uses Claude.

For Claude, the ✨ button on Today, Workouts, Nutrition and Progress opens a chat with Claude (`claude-opus-5-5`, streamed, server-side refusal fallback). It uses the user's own Anthropic API key, stored in the Keychain (`APIKeyStore`) and sent only to `api.anthropic.com`. The system prompt is the full plan rendered by `PlanSummary` (cached) plus a per-request block with today's session, chosen menu, check-ins and recent workouts. There is no Swift SDK, so `ClaudeClient` uses raw HTTP + Server-Sent Events.

## More exercises

Workouts → **More exercises** lists database exercises the user can do with their equipment (Profile → My equipment: power rack, barbell, bench, dumbbells, pull-up bar, bands, kettlebell, gym). `Exercise.isDoable(with:)` infers rack, bench and bar needs from the exercise name. A curated power-rack collection (`PowerRackCollection`) comes first, then exercises by muscle area. Plans can exclude categories via `training.extraExercises` (Tsveti: no plyometrics postpartum).

## Food diary

The **Diary** tab is a MyFitnessPal-style calorie counter: goal − food = remaining, protein/carbs/fat, and Breakfast/Lunch/Dinner/Snacks entries per day. Food can be added from the plan (one tap, or "log the day's menu"), the built-in basic foods (`Resources/basic-foods.json`, ≈ per 100 g), [Open Food Facts](https://world.openfoodfacts.org) search and barcode scanning (VisionKit), or quick add. The goal defaults to the middle of the plan's kcal and protein ranges; the calorie calculator (Mifflin-St Jeor, pre-filled from the plan's `body` stats, +400 kcal and an 1800 kcal floor while breastfeeding) can set a custom one. Stored by `FoodDiaryStore` in `Application Support/food-diary.json`. Profile moved to the 👤 button on Today.

## Accounts (Supabase)

Email + password accounts run on the owner's own [Supabase](https://supabase.com) project (free tier), over REST in `SupabaseClient` (no SDK). The session lives in the Keychain; the whole app state (profile, imported plans, workouts, check-ins, week menus, diary) is backed up as one JSON row in `public.user_data`, protected by row-level security, when the app goes to the background or on demand, and can be restored on another phone.

Setup: create a project → SQL Editor → run the script shown in the app (Profile → Account, also `SupabaseSetupSection.sql`) → Project Settings → API → paste the Project URL and anon public key in the app, or set `SupabaseConfig.builtInURL` / `builtInAnonKey`. Supabase sends a confirmation email on sign-up by default.

## Import a plan from PDF

Profile or Nutrition → **Import plan from PDF**. Claude (`claude-opus-5-5`, the user's API key) reads the PDF and answers in a fixed JSON schema (structured outputs, `PlanImporter.schema`): targets, every meal option with ingredients mapped to grocery items, the sample week, rules and adjustments, in Bulgarian and English. The plan is saved in `Application Support/ImportedPlans/` as a new person, or replaces an existing person's eating plan (their training program is kept; "Restore the coach's original plan" undoes it).

## Recommended programs

Workouts → **Recommended programs** (also Profile → Goal) builds a full program for each goal from the exercise database (`ProgramRecommender`): fat loss (3 × 12–15, short rests, cardio finisher, steps days), tone & sculpt (glute emphasis), build muscle (4 × 6–10 main lifts, 2 min rests) and stay healthy. The split follows workouts per week (2–3 full body A/B, 4 upper/lower, 5–6 push/pull/legs for muscle), and exercises are picked from movement-pattern lists by the user's equipment and level, with alternatives. Starting one replaces the coach's training program (`ProfileStore.trainingPlan`) until "Back to the coach's program"; logging and progression work the same.

## Body measurements

Progress → **Measurements** (or the Progress tab itself without a personal plan): weight, waist, hips, chest, neck, upper arm, thigh, calf and body fat %, with how-to tips, latest values, change since last time and since the start, a chart per measurement, and an optional weekly reminder notification. Stored as check-ins (`CheckIn.extra` for the extra measurements), so they're part of the account backup.
