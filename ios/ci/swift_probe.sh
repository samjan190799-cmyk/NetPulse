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
set -o pipefail
set -f

ios_dir="$(cd "$(dirname "$0")/.." && pwd)"
extra=()
for rel in ${PROBE_WITH:-}; do
  if ! printf '%s' "$rel" | grep -Eq '^[A-Za-z0-9_./-]+\.swift$' || printf '%s' "$rel" | grep -q '\.\.'; then
    echo "Недопустимый путь в PROBE_WITH: $rel"
    exit 2
  fi
  extra+=("$ios_dir/$rel")
done

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
  output="$(xcrun swiftc -typecheck -sdk "$sdk" -target arm64-apple-ios17.0-simulator -swift-version 6 "$file" "${extra[@]}" 2>&1)"
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
