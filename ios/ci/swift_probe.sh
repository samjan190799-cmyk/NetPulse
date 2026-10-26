#!/usr/bin/env bash
# Проверка фрагментов Swift настоящим компилятором из установленного Xcode: только проверка типов, приложение не собирается.
# Код приложения пишется без компилятора под рукой, и когда неясно, существует ли API и как он вызывается
# (например, какие конструкторы у UserAnnotation), фрагмент с вариантами проверяется здесь за пару минут.
#
# Использование: swift_probe.sh [ИМЯ.swift ...]   (файлы лежат в ios/ci/probes; без аргументов проверяются все)
# Для каждого файла печатается «ПРОШЁЛ» или «НЕ ПРОШЁЛ» и сообщения компилятора. Заведомо неверный вызов
# (например, UserAnnotation(zzz: 1)) удобен тем, что компилятор перечисляет в ответ все подходящие конструкторы.
#
# Переменная PROBE_WITH: файлы приложения (пути от каталога ios, через пробел), которые проверяются вместе с
# фрагментом. Так новые экраны и модификаторы проверяются вместе с темой оформления, не собирая всё приложение.
# Метки вместо путей: @app — все файлы фазы Sources цели NetPulse, @widgets — цели NetPulseWidgets, @tests — приложение и тесты (список берётся
# из project.pbxproj, см. target_sources.py). Так вся цель проверяется на типы за пару минут, без сборки и симулятора.
set -o pipefail
set -f

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
extra=()
flags=()
for rel in ${PROBE_WITH:-}; do
  case "$rel" in
    @app|@widgets)
      case "$rel" in
        @app) target_name="NetPulse" ;;
        @widgets) target_name="NetPulseWidgets" ;;
      esac
      listed="$(python3 "$ios_dir/ci/target_sources.py" "$target_name")" || { echo "$listed"; exit 2; }
      while IFS= read -r path; do
        extra+=("$path")
      done <<< "$listed"
      continue
      ;;
    @tests)
      # Тесты проверяются вместе с приложением как один модуль: строка `@testable import NetPulse` в копиях убирается,
      # а XCTest берётся из платформы симулятора
      listed="$(python3 "$ios_dir/ci/target_sources.py" NetPulse)" || { echo "$listed"; exit 2; }
      while IFS= read -r path; do
        extra+=("$path")
      done <<< "$listed"
      listed="$(python3 "$ios_dir/ci/target_sources.py" NetPulseTests)" || { echo "$listed"; exit 2; }
      stripped_dir="$(mktemp -d)"
      while IFS= read -r path; do
        sed '/^@testable import NetPulse$/d' "$path" > "$stripped_dir/$(basename "$path")"
        extra+=("$stripped_dir/$(basename "$path")")
      done <<< "$listed"
      platform_dir="$(xcrun --sdk iphonesimulator --show-sdk-platform-path)"
      flags+=(-F "$platform_dir/Developer/Library/Frameworks" -I "$platform_dir/Developer/usr/lib")
      continue
      ;;
  esac
  if ! printf '%s' "$rel" | grep -Eq '^[A-Za-z0-9_./-]+\.swift$' || printf '%s' "$rel" | grep -q '\.\.'; then
    echo "Недопустимый путь в PROBE_WITH: $rel"
    exit 2
  fi
  extra+=("$ios_dir/$rel")
done

# Целые цели проверяются без предупреждений: в них их много, а нужны только ошибки. Одной проверки типов для них мало:
# ошибки изоляции потоков («sending ... risks causing data races») находятся уже при разборе SIL, поэтому цели
# проходят через `-emit-sil` (без генерации кода и линковки).
mode=(-typecheck)
case "${PROBE_WITH:-}" in
  *@*)
    flags+=(-suppress-warnings)
    mode=(-emit-sil -wmo -Onone -o /dev/null)
    ;;
esac

dir="$(cd "$(dirname "$0")" && pwd)/probes"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
echo "SDK: $sdk"
xcrun swiftc --version 2>&1 | head -n 2

files=()
if [ $# -eq 0 ]; then
  # Через find, а не через звёздочку: раскрытие шаблонов выше отключено (set -f)
  while IFS= read -r file; do
    files+=("$file")
  done < <(find "$dir" -maxdepth 1 -name '*.swift' | sort)
else
  for name in "$@"; do
    if ! printf '%s' "$name" | grep -Eq '^[A-Za-z0-9_.-]+\.swift$'; then
      echo "Недопустимое имя файла: $name"
      exit 2
    fi
    files+=("$dir/$name")
  done
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "Нет файлов для проверки в $dir"
  exit 0
fi

failed=0
for file in "${files[@]}"; do
  echo
  echo "=== ${file#"$dir"/}"
  if [ ! -f "$file" ]; then
    echo "НЕТ ФАЙЛА"
    failed=$((failed + 1))
    continue
  fi
  output="$(xcrun swiftc "${mode[@]}" -sdk "$sdk" -target arm64-apple-ios17.0-simulator -swift-version 6 "${flags[@]}" "$file" "${extra[@]}" 2>&1)"
  code=$?
  printf '%s\n' "$output" | head -n 90
  if [ "$code" -eq 0 ]; then
    echo "ПРОШЁЛ"
  else
    echo "НЕ ПРОШЁЛ (код $code)"
    failed=$((failed + 1))
  fi
done
echo
echo "Не прошло файлов: $failed из ${#files[@]}"
# Результат читается из журнала, поэтому сама справка всегда завершается успешно
exit 0
