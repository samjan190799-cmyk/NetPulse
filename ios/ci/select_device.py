#!/usr/bin/env python3
"""Выбор симулятора нужного размера для скриншотов App Store.

  select_device.py iphone   — iPhone Pro Max (6,9″, снимок 1320×2868)
  select_device.py ipad     — iPad Pro 13″ (снимок 2064×2752)

Печатает через табуляцию: идентификатор, имя, версию iOS. Берётся самый новый iOS и самая новая модель.
"""
import json
import re
import subprocess
import sys

kind = sys.argv[1] if len(sys.argv) > 1 else "iphone"
patterns = {
    "iphone": r"iPhone (\d+) Pro Max",
    "ipad": r"iPad Pro 13-inch \(M(\d+)\)",
}
if kind not in patterns:
    sys.exit(f"Неизвестный вид устройства: {kind}")

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))
candidates = []
for runtime, devices in data["devices"].items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        found = re.fullmatch(patterns[kind], device["name"])
        if found:
            candidates.append((version, int(found.group(1)), device["name"], device["udid"]))

if not candidates:
    print("Подходящих симуляторов нет. Доступные:", file=sys.stderr)
    subprocess.call(["xcrun", "simctl", "list", "devices", "available"], stdout=sys.stderr)
    sys.exit(1)

candidates.sort(reverse=True)
version, _, name, udid = candidates[0]
print(f"{udid}\t{name}\tiOS {version[0]}.{version[1]}")
