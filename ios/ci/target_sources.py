#!/usr/bin/env python3
"""Печатает пути Swift-файлов, которые входят в фазу Sources цели из project.pbxproj (по одному в строке).

Использование: target_sources.py ЦЕЛЬ   (NetPulse, NetPulseWidgets, NetPulseTests, NetPulseUITests)
Нужен проверке типов (swift_probe.sh, метка @app / @widgets): список берётся из самого проекта, поэтому файл,
который забыли зарегистрировать, там не окажется, и компилятор сразу покажет неразрешённые имена.
"""
import re
import sys
from pathlib import Path

ios_dir = Path(__file__).resolve().parent.parent
text = (ios_dir / "NetPulse.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8")

if len(sys.argv) != 2:
    sys.exit("Нужно имя цели")
target = sys.argv[1]

refs = {}
for m in re.finditer(r"^\t\t([0-9A-F]{24}) /\* .*? \*/ = \{isa = PBXFileReference;.*?path = (.*?); sourceTree", text, re.M):
    refs[m.group(1)] = m.group(2).strip('"')

builds = {}
for m in re.finditer(r"^\t\t([0-9A-F]{24}) /\* .*? in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})", text, re.M):
    builds[m.group(1)] = m.group(2)

tm = re.search(r"^\t\t[0-9A-F]{24} /\* " + re.escape(target) + r" \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);", text, re.S | re.M)
if not tm:
    sys.exit(f"Цель {target} не найдена")
phase_ids = re.findall(r"([0-9A-F]{24}) /\* Sources \*/", tm.group(1))
if len(phase_ids) != 1:
    sys.exit(f"У цели {target} ожидалась одна фаза Sources")
pm = re.search(r"^\t\t" + phase_ids[0] + r" /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);", text, re.S | re.M)
for build_id in re.findall(r"([0-9A-F]{24}) /\* .*? in Sources \*/", pm.group(1)):
    ref = builds.get(build_id)
    path = refs.get(ref or "")
    if path is None:
        sys.exit(f"Для записи {build_id} нет файла")
    full = ios_dir / path
    if not full.is_file():
        sys.exit(f"Файла нет на диске: {path}")
    print(full)
