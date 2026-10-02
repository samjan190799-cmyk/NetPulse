#!/usr/bin/env bash
# Справка по SDK рекламы Яндекса (Yandex Mobile Ads): скачивает пакет во временный проект и печатает объявления
# нужных типов из его Swift-интерфейса, а также список SKAdNetwork-идентификаторов.
#
# Яндекс-серверы из среды разработки недоступны, поэтому точные сигнатуры берутся здесь, на раннере CI,
# а не из памяти: SDK поставляется бинарным пакетом, исходников у него нет.
#
# Переменные окружения: YANDEX_SDK_VERSION (по умолчанию 8.6.0), YANDEX_PATTERN (регулярное выражение egrep;
# по умолчанию — основные типы баннера, межстраничной и вознаграждаемой рекламы).
set -o pipefail

VERSION="${YANDEX_SDK_VERSION:-8.6.0}"
PATTERN="${YANDEX_PATTERN:-}"

if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$'; then
  echo "Недопустимая версия: $VERSION"
  exit 2
fi
if [ -n "$PATTERN" ] && ! printf '%s' "$PATTERN" | grep -Eq '^[A-Za-z0-9_ .:,()<>|?*+\\-]+$'; then
  echo "В шаблоне есть недопустимые символы"
  exit 2
fi

DEFAULT_PATTERN='(struct|class|enum|protocol|extension) (Banner|BannerState|BannerSize|BannerAdSize|BannerAdView|AdRequest|AdInfo|YandexAds|Reward|ImpressionData|InterstitialAdEvent|RewardedAdEvent|InterstitialAdLoader|InterstitialAd|RewardedAdLoader|RewardedAd|ConsentManagementPlatform)\b|func (initializeSDK|setLocationTracking|setAgeRestricted|enableLogging|setUserConsent|onAdLoad|onAdFailure|onAdClick|onAdImpression|interstitialAd|rewardedAd|loadAd|show|setAdapterIdentity)\b|static (func|var) (sticky|fixed|inline)\b'
[ -n "$PATTERN" ] || PATTERN="$DEFAULT_PATTERN"

echo "Версия SDK: $VERSION"
swift --version 2>&1 | head -n 2

work="$(mktemp -d)"
cd "$work" || exit 1
mkdir -p Sources/Probe
cat > Package.swift <<EOF
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Probe",
    platforms: [.iOS("17.0")],
    dependencies: [
        .package(url: "https://github.com/yandexmobile/yandex-ads-sdk-ios", exact: "$VERSION")
    ],
    targets: [
        .target(name: "Probe", dependencies: [.product(name: "YandexMobileAds", package: "yandex-ads-sdk-ios")])
    ]
)
EOF
echo 'import YandexMobileAds' > Sources/Probe/Probe.swift

echo
echo "=== swift package resolve ==="
swift package resolve 2>&1 | tail -n 25

echo
echo "=== Бинарные артефакты ==="
find .build -maxdepth 7 -name '*.xcframework' 2>/dev/null | head -n 20

echo
echo "=== Swift-интерфейсы Яндекса ==="
interfaces=()
while IFS= read -r file; do
  interfaces+=("$file")
done < <(find .build -name '*.swiftinterface' -path '*YandexMobileAds*' ! -name '*.private.swiftinterface' ! -name '*.package.swiftinterface' 2>/dev/null | sort)
printf '%s\n' "${interfaces[@]}" | head -n 12

# Берём интерфейс для устройства (arm64-apple-ios), а не для симулятора, чтобы не печатать одно и то же дважды
chosen=""
for file in "${interfaces[@]}"; do
  case "$file" in *ios-arm64/*|*arm64-apple-ios.swiftinterface) chosen="$file"; break ;; esac
done
[ -n "$chosen" ] || chosen="${interfaces[0]:-}"

if [ -n "$chosen" ]; then
  echo
  echo "=== Объявления из: ${chosen#"$work"/} ($(wc -l < "$chosen") строк) ==="
  grep -nE -B1 -A9 "$PATTERN" "$chosen" | head -n 700
else
  echo "Текстового интерфейса нет: пробую выгрузить символы компилятором"
  framework="$(find .build -maxdepth 8 -type d -name 'YandexMobileAds.framework' | grep -E 'ios-arm64($|/)' | head -n 1)"
  echo "framework: ${framework:-не найден}"
  if [ -n "$framework" ]; then
    out="$work/symbols"
    mkdir -p "$out"
    xcrun swift-symbolgraph-extract -module-name YandexMobileAds -F "$(dirname "$framework")" \
      -target arm64-apple-ios17.0 -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" -output-dir "$out" 2>&1 | tail -n 5
    python3 - "$out" <<'PY'
import glob, json, re, sys
pattern = re.compile(r"Banner|AdRequest|YandexAds|initializeSDK|Reward|Interstitial|setLocation|setAgeRestricted|onAd|sticky|fixed|inline")
for path in glob.glob(sys.argv[1] + "/YandexMobileAds*.symbols.json"):
    data = json.load(open(path))
    for symbol in data.get("symbols", []):
        fragments = "".join(f.get("spelling", "") for f in symbol.get("declarationFragments", []))
        if pattern.search(fragments):
            print(fragments)
PY
  fi
fi

echo
echo "=== SKAdNetwork-идентификаторы Яндекса (yastatic.net) ==="
if curl -sf --max-time 20 -o skad.xml "https://yastatic.net/pcode-static/skadnetwork/skadids.xml"; then
  grep -ioE '[a-z0-9]+\.skadnetwork' skad.xml | tr '[:upper:]' '[:lower:]' | sort -u > skad.txt
  echo "найдено: $(wc -l < skad.txt)"
  tr '\n' ' ' < skad.txt
  echo
else
  echo "yastatic.net недоступен с раннера"
fi
exit 0
