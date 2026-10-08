#!/usr/bin/env bash
# Все проверки проекта: формат, линтер, типы, юнит-тесты баланса и смоук-тест мира.
# Нужны инструменты из rokit.toml (`rokit install`) и lune (https://github.com/lune-org/lune).
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=(src/shared src/client src/server/Services src/server/init.server.luau tests)

echo "== StyLua"
stylua --check "${SOURCES[@]}"

echo "== Selene"
selene src/shared src/client src/server/Services src/server/init.server.luau

echo "== luau-lsp (strict, типы Roblox API)"
rojo sourcemap default.project.json -o sourcemap.json
if [ ! -f globalTypes.d.luau ]; then
	curl -sSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.1/scripts/globalTypes.d.luau
fi
output=$(luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json --ignore="**/Packages/**" src/ 2>&1 | grep -v "^\[INFO\]\|^\[WARN\]" || true)
if [ -n "$output" ]; then
	echo "$output"
	exit 1
fi

echo "== Юнит-тесты баланса"
python3 tests/run.py "${LUAU:-luau}"

echo "== Смоук-тест мира (Lune)"
mkdir -p build
rojo build default.project.json -o build/game.rbxl
lune run tests/world.lune.luau build/game.rbxl

echo "Все проверки пройдены"
