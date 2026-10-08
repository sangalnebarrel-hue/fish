#!/usr/bin/env python3
"""
Запускает юнит-тесты чистых модулей (Config, FishData, ShopData, Formulas, Format) через luau CLI.

Модули в игре подключаются как require(script.Parent.X). Здесь каждый модуль оборачивается в функцию
с подменёнными `script` и `require`, всё склеивается в один файл и запускается.

    python3 tests/run.py [путь-к-luau]
"""

import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED = os.path.join(ROOT, "src", "shared")
PURE_MODULES = ["Config", "FishData", "ShopData", "Formulas", "Format"]
TEST_DIR = os.path.join(ROOT, "tests")


def wrap_module(name: str) -> str:
    with open(os.path.join(SHARED, name + ".luau"), encoding="utf-8") as f:
        source = f.read()
    # `export type` разрешён только на верхнем уровне файла, а здесь модуль оказывается внутри функции.
    source = re.sub(r"^export type ", "type ", source, flags=re.MULTILINE)
    return f'__sources["{name}"] = function(script, require)\n{source}\nend\n'


PRELUDE = """
local __sources = {}
local __cache = {}
local __shared = setmetatable({}, { __index = function(_, key) return { __module = key } end })
local function __require(target)
    local name = target.__module
    if __cache[name] == nil then
        local loader = __sources[name]
        assert(loader, "module not found: " .. tostring(name))
        __cache[name] = loader({ Parent = __shared, Name = name }, __require)
    end
    return __cache[name]
end
"""

TEST_PRELUDE = """
local Shared = setmetatable({}, { __index = function(_, key) return __require({ __module = key }) end })
local __passed, __failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        __passed += 1
    else
        __failed += 1
        print("FAIL  " .. name .. "\\n      " .. tostring(err))
    end
end
local function expect(cond, message)
    if not cond then error(message or "expectation failed", 2) end
end
local function near(a, b, eps)
    return math.abs(a - b) <= (eps or 1e-9)
end
"""

TEST_EPILOGUE = """
print(string.format("%d passed, %d failed", __passed, __failed))
if __failed > 0 then error("tests failed") end
"""


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LUAU", "luau")
    parts = [PRELUDE]
    parts += [wrap_module(name) for name in PURE_MODULES]
    parts.append(TEST_PRELUDE)
    for file in sorted(os.listdir(TEST_DIR)):
        if file.endswith(".spec.luau"):
            with open(os.path.join(TEST_DIR, file), encoding="utf-8") as f:
                parts.append(f"do -- {file}\n{f.read()}\nend\n")
    parts.append(TEST_EPILOGUE)

    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as bundle:
        bundle.write("\n".join(parts))
        path = bundle.name
    try:
        result = subprocess.run([luau, path])
        return result.returncode
    finally:
        os.unlink(path)


if __name__ == "__main__":
    sys.exit(main())
