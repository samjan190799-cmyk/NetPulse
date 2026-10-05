"""Доли цветных пикселей на скриншотах: по ним в журнале CI видно, нарисованы ли цветные линии маршрутов (зелёная,
жёлтая, оранжевая, красная), хотя сами картинки в журнал не попадают. Тонкую линию грубая сетка символов
(screen_map.py) не показывает, а доля пикселей показывает: сравните «прежние маршруты показаны» и «скрыты»
на одном месте карты.

Использование: screen_tint.py КАТАЛОГ часть_имени [часть_имени ...]
Для каждого подходящего PNG печатает долю пикселей каждого цвета (в процентах) для всего экрана и для центральной
части карты (по ширине 20–80%, по высоте 15–50%: там лежит точка «вы здесь» и последний маршрут)."""
import colorsys
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow не установлен: доли цветов не считаются")
    sys.exit(0)

COLS = 300
ROWS = 650

# Цвет — диапазон оттенка в градусах; тёмная подложка карты синеватая (около 225°), поэтому синие тона не считаются
CLASSES = [
    ("красный", lambda h: h >= 345 or h < 12),
    ("оранжевый", lambda h: 12 <= h < 38),
    ("жёлтый", lambda h: 38 <= h < 70),
    ("зелёный", lambda h: 95 <= h < 185),
]
MIN_SATURATION = 0.18
MIN_VALUE = 0.22


def box_filter():
    resampling = getattr(Image, "Resampling", Image)
    return getattr(resampling, "BOX")


def classify(r, g, b):
    hue, saturation, value = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if saturation < MIN_SATURATION or value < MIN_VALUE:
        return None
    degrees = hue * 360
    for name, matches in CLASSES:
        if matches(degrees):
            return name
    return None


def shares(pixels, x0, x1, y0, y1):
    counts = {name: 0 for name, _ in CLASSES}
    total = max(1, (x1 - x0) * (y1 - y0))
    for y in range(y0, y1):
        for x in range(x0, x1):
            name = classify(*pixels[x, y])
            if name:
                counts[name] += 1
    return {name: 100 * count / total for name, count in counts.items()}


def render(path: Path):
    image = Image.open(path).convert("RGB")
    small = image.resize((COLS, ROWS), box_filter())
    pixels = small.load()
    whole = shares(pixels, 0, COLS, 0, ROWS)
    center = shares(pixels, int(COLS * 0.2), int(COLS * 0.8), int(ROWS * 0.15), int(ROWS * 0.5))
    print(f"=== {path.name} ({image.size[0]}x{image.size[1]}): доля пикселей, % [весь экран | центр карты]")
    for name, _ in CLASSES:
        print(f"  {name:<10} {whole[name]:6.2f} | {center[name]:6.2f}")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    folder = Path(argv[1])
    parts = argv[2:]
    files = sorted(p for p in folder.glob("*.png") if any(part in p.name for part in parts))
    if not files:
        print("Подходящих скриншотов нет")
        return 0
    for path in files:
        render(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
