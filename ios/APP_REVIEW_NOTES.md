# NetPulse: сведения для App Review

Файл нужен при отправке сборки в App Store. Первый раздел — текст для поля **App Store Connect → App Review Information → Notes** (на английском, как его читает рецензент). Второй — чек-лист для владельца приложения.

Фоновая геолокация (`UIBackgroundModes = location`) нужна ровно одной функции — записи маршрута в «Карте сети». Не включайте и не описывайте её иначе, чем она работает: скрытые или недокументированные функции — основание для удаления приложения (правило 2.3.1), а использование фонового режима не по назначению — для отказа (правило 2.5.4).

---

## 1. Текст для Notes for Review (English)

```
BACKGROUND LOCATION

NetPulse declares the "location" background mode (UIBackgroundModes). It is used by ONE feature only:
Network Map → "Start route recording" (Russian UI: «Карта сети» → «Начать запись маршрута»).

What it does: while the user is recording a route, the app saves, every few seconds, the device position
and the quality of the network at that place (TCP connection time to 1.1.1.1, connection type
Wi-Fi / 5G / 4G / 3G / 2G, optionally a short download-speed sample). The map then shows the route coloured
by network quality (good / fair / poor / no connection) and marks places with no connectivity.
This needs continuous location while the phone is in a pocket, a car or a train. Without background
location the map would cover only the places where the app happens to be open.

User control and transparency:
- Recording starts ONLY when the user taps "Start route recording". It never starts by itself
  (not at launch, not after a restart).
- While recording, the iOS location indicator is visible in the status bar, the dashboard shows a
  "Route recording in progress" banner, and recording ends when the user taps "Stop and save".
- Location permission ("While Using the App") is requested only after that tap. The purpose string says
  the location is used to record a route and show where the network was fast, slow or lost, and that the
  data stays on the device.
- Data stays on the device: routes are stored in the app's Application Support directory, excluded from
  backups, never uploaded; the user can delete one route or all routes in the app. No account, no server.
- All other features (speed test, diagnostics, widgets, Dynamic Island) work without location permission.
  Nothing is gated behind location.

A side effect of recording: while the app records in the background, the Dynamic Island keeps showing
live network speed.

HOW TO TEST
1. Dashboard ("Скорость" tab) → tap the "Карта сети" (Network Map) chip. (Also: Settings → "Карта сети".)
2. Tap "Показать пример" (Show example): a clearly labelled DEMO route (not real data) is drawn on the map.
3. Tap "Начать запись маршрута" (Start route recording) → allow location "While Using the App".
4. Walk or drive. Within seconds the points counter grows. Lock the device or switch to another app:
   recording continues (location indicator in the status bar).
5. Return and tap "Остановить и сохранить" (Stop and save): the route appears on the map and under
   "Мои маршруты" (My routes), with a summary and a delete button.
Note: if the phone stays on a desk, points are written only every 30 seconds. In the Simulator use
Features → Location → City Run / Freeway Drive.

The app's interface is in Russian.
```

---

## 2. Чек-лист перед отправкой на ревью

1. **App Privacy.** Код NetPulse координаты никуда не отправляет, но **сторонние SDK** (Meta Audience Network, Google Mobile Ads) могут собирать геолокацию, если пользователь выдал разрешение. Откройте их документацию «какие данные собирает SDK» и отметьте в App Privacy то, что они собирают (в том числе «Precise/Coarse Location» для рекламы), а если не собирают — укажите «не собирается». Ответ должен совпадать с действительностью.
2. **Политика конфиденциальности** (ссылка обязательна) должна упоминать запись маршрутов: что именно сохраняется (положение, качество сети, время), что всё хранится на устройстве, как удалить.
3. **Проверка на устройстве перед отправкой:** значок геолокации в строке состояния во время записи; запись продолжается при заблокированном экране и в другом приложении; «Остановить и сохранить» сохраняет маршрут; в запросе разрешения видны все кнопки (в том числе «При использовании приложения»); «Удалить все» стирает маршруты.
4. **Скриншоты для App Store:** карта с маршрутом (кнопка «Показать пример» рисует демо-маршрут с пометкой «ПРИМЕР · ДЕМО-ДАННЫЕ» — в скриншоте для магазина лучше использовать настоящую запись).
5. **PRO.** Если запись маршрута станет платной функцией, учтите правило 5.1.1(ii): платная функция не должна требовать от пользователя разрешения на данные, которые не нужны для самой функции. Здесь геолокация — основа функции, поэтому это допустимо, но экран покупки не должен подталкивать к выдаче разрешения.
6. **Манифест приватности.** В проекте нет `PrivacyInfo.xcprivacy`, хотя приложение использует API, требующие объявления причины (например, `UserDefaults`, отметки времени файлов). При загрузке в App Store Connect могут прийти замечания `ITMS-91053`. Это отдельная задача: нужно добавить манифест приложения и убедиться, что SDK приносят свои.
7. **Если ревью отклонит запись маршрута** — убрать `location` из `UIBackgroundModes` и экран записи в магазинной сборке (функции в сборке просто не будет), а не прятать её. Остров продолжит обновляться, пока приложение открыто, и покажет «паузу» в фоне.
