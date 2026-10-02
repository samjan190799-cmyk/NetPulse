#!/usr/bin/env bash
# Проверка фрагментов Swift настоящим компилятором из установленного Xcode: только проверка типов, приложение не собирается.
# Код приложения пишется без компилятора под рукой, и когда неясно, существует ли API и как он вызывается
# (например, какие конструкторы у UserAnnotation), фрагмент с вариантами проверяется здесь за пару минут.
#
# Использование: swift_probe.sh [ИМЯ.swift ...]   (файлы лежат в ios/ci/probes; без аргументов проверяются все)
# Для каждого файла печатается «ПРОШЁЛ» или «НЕ ПРОШЁЛ» и сообщения компилятора. Заведомо неверный вызов
# (например, UserAnnotation(zzz: 1)) удобен тем, что компилятор перечисляет в ответ все подходящие конструкторы.
set -o pipefail
set -f

dir="$(cd "$(dirname "$0")" && pwd)/probes"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
echo "SDK: $sdk"
xcrun swiftc --version 2>&1 | head -n 2

files=()
if [ $# -eq 0 ]; then
  for file in "$dir"/*.swift; do
    [ -f "$file" ] && files+=("$file")
  done
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
  output="$(xcrun swiftc -typecheck -sdk "$sdk" -target arm64-apple-ios17.0-simulator -swift-version 6 "$file" 2>&1)"
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
