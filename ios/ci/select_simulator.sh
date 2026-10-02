#!/usr/bin/env bash
# Печатает через табуляцию: идентификатор, имя, версию iOS и признак Dynamic Island у самого подходящего симулятора iPhone.
# Выбирается самый новый из доступных iOS и модель «Pro» (у неё есть Dynamic Island); если таких нет — любой iPhone.
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json
import re
import sys

data = json.load(sys.stdin)
candidates = []
for runtime, devices in data["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        name = device["name"]
        if not name.startswith("iPhone"):
            continue
        number_match = re.search(r"iPhone (\d+)", name)
        number = int(number_match.group(1)) if number_match else 0
        is_pro = bool(re.match(r"iPhone \d+ Pro$", name))
        candidates.append((version, is_pro, number, name, device["udid"]))

if not candidates:
    sys.exit("Нет доступных симуляторов iPhone")

candidates.sort(reverse=True)
version, is_pro, number, name, udid = candidates[0]
island = "да" if is_pro else "не гарантирован"
print(f"{udid}\t{name}\tiOS {version[0]}.{version[1]}\tDynamic Island: {island}")
'
