#!/usr/bin/env bash
# Refreshes the bundled exercise database from free-exercise-db (public domain).
set -euo pipefail
cd "$(dirname "$0")/.."
curl -fsSL https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json \
  | python3 -c "import json,sys; json.dump(json.load(sys.stdin), sys.stdout, separators=(',',':'), ensure_ascii=False)" \
  > AngelinasNutrition/Resources/exercises.json
echo "Updated $(python3 -c "import json; print(len(json.load(open('AngelinasNutrition/Resources/exercises.json'))))") exercises"
