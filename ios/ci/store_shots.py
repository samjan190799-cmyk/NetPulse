#!/usr/bin/env python3
"""Подготовка скриншотов для App Store Connect из вложений UI-теста.

  store_shots.py ВИД КАТАЛОГ_ВЛОЖЕНИЙ КАТАЛОГ_РЕЗУЛЬТАТА

Берёт файлы вида `testCaptureStoreScreenshots--01-home.png`, убирает альфа-канал (App Store не принимает
прозрачность), сохраняет как `01-home.png` и проверяет размер: для iPhone 6,9″ это 1320×2868 (или 1290×2796),
для iPad 13″ — 2064×2752 (или 2048×2732). Код возврата 1, если нужных снимков нет или размер не подходит.
"""
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow не установлен")

ALLOWED = {
    "iphone": {(1320, 2868), (1290, 2796)},
    "ipad": {(2064, 2752), (2048, 2732)},
}


def main(argv):
    if len(argv) != 4 or argv[1] not in ALLOWED:
        print(__doc__)
        return 2
    kind, source, target = argv[1], Path(argv[2]), Path(argv[3])
    target.mkdir(parents=True, exist_ok=True)

    produced, problems = [], []
    for path in sorted(source.glob("*.png")):
        match = re.search(r"--(\d{2}-[A-Za-z0-9_-]+?)(?:-\d+)?\.png$", path.name)
        if not match:
            continue
        name = match.group(1)
        image = Image.open(path)
        size = image.size
        flat = Image.new("RGB", size, (0, 0, 0))
        flat.paste(image.convert("RGBA"), mask=image.convert("RGBA").split()[3])
        out = target / f"{name}.png"
        flat.save(out, "PNG", optimize=True)
        ok = size in ALLOWED[kind]
        produced.append((name, size, ok, out.stat().st_size))
        if not ok:
            problems.append(f"{name}: размер {size[0]}×{size[1]} не подходит для {kind}")

    print(f"=== Скриншоты ({kind}) ===")
    for name, size, ok, nbytes in produced:
        print(f"  {name:<24} {size[0]}×{size[1]}  {nbytes / 1024:7.0f} КБ  {'ок' if ok else 'НЕВЕРНЫЙ РАЗМЕР'}")
    if not produced:
        print("Снимков нет")
        return 1
    for problem in problems:
        print("ОШИБКА:", problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
