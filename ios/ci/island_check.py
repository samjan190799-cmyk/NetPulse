#!/usr/bin/env python3
"""Проверка Dynamic Island по результатам распознавания текста на скриншотах (вывод ocr_screenshots.swift).

В UI-тесте приложение уходит на главный экран, и через равные паузы делаются снимки экрана:
  *--continuous-bg-N.png   прогон с включённым «Непрерывным режимом»
  *--control-bg-N.png      контрольный прогон без него
Скрипт достаёт числа из верхней полосы экрана (там находится остров) и сравнивает кадры между собой:
если числа в серии не менялись, остров «замёрз», и это нужно заметить.

Важно: симулятор не усыпляет свёрнутое приложение, поэтому замирание, характерное для реального iPhone,
он не воспроизводит. Проверка ловит другое: остров вообще не обновляется (сломан конвейер от счётчиков
интерфейсов до Live Activity).

Использование: island_check.py ФАЙЛ_С_РАСПОЗНАННЫМ_ТЕКСТОМ
Переменная окружения ISLAND_STRICT=1 включает ненулевой код возврата, если в серии с режимом числа не менялись.
"""
import os
import re
import sys
from pathlib import Path

HEADER = re.compile(r"^=== (?P<name>\S+\.png) \(\d+x\d+\)$")
CLOCK = re.compile(r"\b\d{1,2}:\d{2}\b")
NUMBER = re.compile(r"\d+(?:\.\d+)?")
SERIES = re.compile(r"^(?P<test>[^-]+)--(?P<series>continuous-bg|control-bg)-(?P<index>\d+)\.png$")


def parse(text: str):
    """Возвращает {(серия): {индекс: [числа верхней полосы]}} и подписи кадров."""
    result = {}
    current = None
    for line in text.splitlines():
        header = HEADER.match(line.strip())
        if header:
            match = SERIES.match(header.group("name"))
            current = (match.group("series"), int(match.group("index"))) if match else None
            continue
        if current and line.startswith("верхняя полоса:"):
            band = line.split(":", 1)[1]
            band = CLOCK.sub(" ", band)           # часы в строке состояния — не скорость
            numbers = NUMBER.findall(band)
            result.setdefault(current[0], {})[current[1]] = numbers
            current = None
    return result


def verdict(frames):
    ordered = [frames[i] for i in sorted(frames)]
    if len(ordered) < 2:
        return "мало кадров для сравнения", None
    if all(not numbers for numbers in ordered):
        return "числа на острове распознать не удалось", None
    changed = any(ordered[i] != ordered[i + 1] for i in range(len(ordered) - 1))
    return ("числа менялись: остров обновляется" if changed else "числа НЕ менялись: остров мог замёрзнуть"), changed


def main() -> int:
    if len(sys.argv) < 2 or not Path(sys.argv[1]).exists():
        print("файл с распознанным текстом не найден: проверка острова пропущена")
        return 0

    series = parse(Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace"))
    if not series:
        print("кадры острова (continuous-bg / control-bg) в распознанном тексте не найдены")
        return 0

    titles = {"continuous-bg": "С непрерывным режимом", "control-bg": "Контрольный прогон (без режима)"}
    strict_failure = False
    for key in ("control-bg", "continuous-bg"):
        frames = series.get(key)
        if not frames:
            print(f"{titles[key]}: кадров нет")
            continue
        print(f"{titles[key]}:")
        for index in sorted(frames):
            print(f"  кадр {index}: {' | '.join(frames[index]) if frames[index] else '(чисел нет)'}")
        text, changed = verdict(frames)
        print(f"  итог: {text}")
        if key == "continuous-bg" and changed is False:
            strict_failure = True

    if strict_failure and os.environ.get("ISLAND_STRICT") == "1":
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
