#!/usr/bin/env bash
# Справка по SDK: печатает объявления API из установленного Xcode (текстовые файлы .swiftinterface).
# Код приложения пишется без компилятора под рукой, и когда нужно точно знать сигнатуру (например, какие
# конструкторы у UserAnnotation), эта справка заменяет догадки: ответ приходит в журнал CI за пару минут.
#
# Использование: sdk_probe.sh ШАБЛОН [ЧАСТИ_ПУТИ]
#   ШАБЛОН       — регулярное выражение (egrep), например "UserAnnotation|struct UserLocation";
#   ЧАСТИ_ПУТИ   — через пробел, по каким словам в пути выбирать интерфейсы (по умолчанию MapKit).
set -o pipefail
set -f

pattern="${1:-}"
parts_text="${2:-MapKit}"

if [ -z "$pattern" ]; then
  echo "Использование: $0 ШАБЛОН [ЧАСТИ_ПУТИ]"
  exit 2
fi
if ! printf '%s' "$pattern" | grep -Eq '^[A-Za-z0-9_ .:,()<>|?*+\\-]+$'; then
  echo "В шаблоне есть недопустимые символы"
  exit 2
fi
if ! printf '%s' "$parts_text" | grep -Eq '^[A-Za-z0-9_. -]+$'; then
  echo "В частях пути есть недопустимые символы"
  exit 2
fi

IFS=' ' read -r -a parts <<< "$parts_text"

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
echo "SDK: $sdk"
xcodebuild -version | head -n 1

# По одному интерфейсу на каталог модуля: архитектуры отличаются только именем файла
selected=()
seen_dirs=""
while IFS= read -r file; do
  case "$file" in *.private.swiftinterface|*.package.swiftinterface) continue ;; esac
  matched=0
  for part in "${parts[@]}"; do
    case "$file" in *"$part"*) matched=1; break ;; esac
  done
  [ "$matched" -eq 1 ] || continue
  dir="$(dirname "$file")"
  case "$seen_dirs" in *"|$dir|"*) continue ;; esac
  seen_dirs="$seen_dirs|$dir|"
  selected+=("$file")
done < <(find "$sdk" -name '*.swiftinterface' 2>/dev/null | sort)

echo "Подходящих интерфейсов: ${#selected[@]}"
for file in "${selected[@]}"; do
  echo "  ${file#"$sdk"/}"
done

for file in "${selected[@]}"; do
  count="$(grep -cE "$pattern" "$file" || true)"
  [ "${count:-0}" -gt 0 ] || continue
  echo
  echo "=== ${file#"$sdk"/}: совпадений $count"
  grep -nE -B1 -A7 "$pattern" "$file" | head -n 260
done
