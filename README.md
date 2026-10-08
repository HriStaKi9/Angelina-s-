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
| `Models/` | `Exercise`, `UserProfile`, `FitnessGoal` |
| `Services/` | `ExerciseLibrary` (bundled DB), `ProfileStore` (persistence), `WorkoutPlanner` |
| `Features/` | Onboarding, Today, Workouts, Nutrition, Profile screens |
| `Resources/exercises.json` | Bundled exercise database |

## Exercise data

Exercises come from [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (Unlicense / public domain). Images load from that repository's GitHub hosting. To refresh the bundled data:

```sh
./scripts/update-exercises.sh
```

## Roadmap

1. ~~Foundation: design system, exercise database, onboarding, daily workout~~
2. Nutrition: calorie and macro targets, food diary, meal plans
3. Workout tracking: log sets, history, progress
4. Plan sync: training adapts to what was eaten that day
