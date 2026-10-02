"""Грубая «карта» скриншота символами: по ней в журнале CI видно раскладку экрана (где панель, плашки, кнопки,
цветные линии маршрута), хотя сами картинки в журнал не попадают.

Использование: screen_map.py КАТАЛОГ часть_имени [часть_имени ...]
Печатает для каждого подходящего PNG сетку символов. Яркость (с поправкой на тёмные тона) передаётся символами « .:-=+*#%@» (от тёмного к светлому),
насыщенный цвет — буквами: R красный, O оранжевый, Y жёлтый, G зелёный, C голубой, B синий, M фиолетовый.
Каждая строка начинается с доли высоты экрана (в процентах), чтобы сопоставлять с положением элементов."""
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow не установлен: карта экрана не строится")
    sys.exit(0)

COLS = 70
ROWS = 120
SHADES = " .:-=+*#%@"


def resample_box():
    resampling = getattr(Image, "Resampling", Image)
    return getattr(resampling, "BOX")


def color_letter(r, g, b):
    top, low = max(r, g, b), min(r, g, b)
    if top - low < 70 or top < 90:
        return None
    if r >= g and r >= b:
        if g > 0.75 * r and b < 0.5 * r:
            return "Y"
        if g > 0.45 * r and b < 0.4 * r:
            return "O"
        if b > 0.7 * r:
            return "M"
        return "R"
    if g >= r and g >= b:
        if b > 0.8 * g:
            return "C"
        if r > 0.8 * g:
            return "Y"
        return "G"
    if r > 0.75 * b:
        return "M"
    return "B"


def render(path: Path):
    image = Image.open(path).convert("RGB")
    small = image.resize((COLS, ROWS), resample_box())
    pixels = small.load()
    print(f"=== {path.name} ({image.size[0]}x{image.size[1]}), сетка {COLS}x{ROWS}")
    for y in range(ROWS):
        chars = []
        for x in range(COLS):
            r, g, b = pixels[x, y]
            letter = color_letter(r, g, b)
            if letter:
                chars.append(letter)
            else:
                # Корень растягивает тёмные тона: интерфейс приложения тёмный, и без него всё слилось бы в точки
                lightness = ((0.299 * r + 0.587 * g + 0.114 * b) / 255) ** 0.5
                level = int(lightness * len(SHADES))
                chars.append(SHADES[min(level, len(SHADES) - 1)])
        print(f"{int(y * 100 / ROWS):3d}|" + "".join(chars))


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
