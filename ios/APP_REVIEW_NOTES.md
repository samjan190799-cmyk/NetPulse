# NetPulse: сведения для App Review

Файл нужен при отправке сборки в App Store. Первый раздел — текст для поля **App Store Connect → App Review Information → Notes** (на английском, как его читает рецензент). Второй — чек-лист для владельца приложения.

Фоновая геолокация (`UIBackgroundModes = location`) нужна ровно одной функции — записи маршрута в «Карте сети». Не включайте и не описывайте её иначе, чем она работает: скрытые или недокументированные функции — основание для удаления приложения (правило 2.3.1), а использование фонового режима не по назначению — для отказа (правило 2.5.4).

---

## 1. Текст для Notes for Review (English)

```
BACKGROUND LOCATION

NetPulse declares the "location" background mode (UIBackgroundModes). It is used by ONE feature only:
Home screen ("Сеть" tab, the map) → "Record route" (Russian UI: «Сеть» → «Записать маршрут»).

What it does: while the user is recording a route, the app saves, every few seconds, the device position
and the quality of the network at that place (TCP connection time to 1.1.1.1, connection type
Wi-Fi / 5G / 4G / 3G / 2G, optionally a short download-speed sample). The map then shows the route coloured
by network quality (good / fair / poor / no connection) and marks places with no connectivity.
This needs continuous location while the phone is in a pocket, a car or a train. Without background
location the map would cover only the places where the app happens to be open.

User control and transparency:
- Recording starts ONLY when the user taps "Record route". It never starts by itself
  (not at launch, not after a restart).
- While recording, the iOS location indicator is visible in the status bar, the map screen shows a red
  "Recording" pill with a timer, and recording ends when the user taps "Stop and save".
- Location permission ("While Using the App") is requested only after that tap. The purpose string says
  the location is used to record a route and show where the network was fast, slow or lost, and that the
  data stays on the device.
- Data stays on the device: routes are stored in the app's Application Support directory, excluded from
  backups, never uploaded; the user can delete one route or all routes in the app. No account, no server.
- Settings → "Запись маршрута" (Route recording): "Записывать маршрут в фоне" (record in the background; on by
  default; when off, the app uses no location in the background and recording simply waits until the user returns),
  an automatic stop after 20 minutes without movement (on by default), and "Продолжать запись после закрытия
  приложения" (continue recording after the app is closed), OFF by default.
- Only if the user turns that last switch on, the app also asks for "Always" location access (the purpose string
  says: to keep recording the route if the app is closed; the data stays on the device). Then, WHILE a route is being
  recorded and never otherwise, the app uses significant-location-change monitoring: if the user swipes the app away,
  iOS may relaunch it in the background after the phone has moved about 500 m, and the recording continues in the
  same route (the gap is not drawn as a line). Nothing else is done on that launch; the monitoring stops when the
  recording stops or the user opens the app. Without the switch the app never asks for "Always".
- Settings → "Экономия заряда" (Battery saver; off by default): one switch that makes the app work less often (coarser
  location of about 100 m, fewer route points, no speed sampling on routes, slower Dynamic Island and widget updates,
  no coverage zones). It does not add any data collection.
- All other features (speed test, diagnostics, widgets, Dynamic Island) work without location permission.
  Nothing is gated behind location.

A side effect of recording: while the app records in the background, the Dynamic Island keeps showing
live network speed.

The map is the home screen of the app (Apple's MapKit, Apple Maps). It is visible before any permission is
requested (without location access it shows an overview of European Russia). The user's position is shown by MapKit's user-location annotation only while the screen is open and location is
authorized (the app supplies only its look, a blue dot); the route lines are drawn from the points recorded by the app.

Route lines: the route is drawn as a line in the colour of the connection quality (green good, yellow fair, orange
poor, red dashed no connection). It is drawn live while recording and, on the home screen, earlier routes are drawn
too as thinner lines (the "Прежние маршруты" / Earlier routes button hides them). There are no wide bands: colour
exists only where the user actually was.

Optional coverage zones (Settings → "Зоны на карте" / Zones on the map, on by default): once at least three routes are
saved, the home screen also shows coloured squares of about 100 x 100 m under the lines, only where the user has been
at least twice and the app has at least four measurements; the colour is the typical (middle) measurement. Nothing is
drawn around the measured places. The zones are computed on the device from the saved routes and disappear together
with them. All of it comes from the app's own measurements; no data about operators' coverage is used or sent.

HOW TO TEST
1. The first screen ("Сеть" tab) is the map with the bottom panel (network speed and two buttons).
2. Tap "Мои маршруты" (My routes) or drag the panel up → "Показать пример маршрута" (Show example route):
   a clearly labelled DEMO route (not real data) is drawn on the map. "Скрыть пример" hides it.
3. Tap "Записать маршрут" (Record route) → allow location "While Using the App".
4. Walk or drive. Within seconds the points counter grows. Lock the device or switch to another app:
   recording continues (location indicator in the status bar).
5. Return and tap "Остановить и сохранить" (Stop and save): the route summary appears on the map; the route
   is saved under "Мои маршруты" (My routes) and can be deleted ("Удалить").
Note: if the phone stays on a desk, points are written only every 30 seconds. In the Simulator use
Features → Location → City Run / Freeway Drive.

ADVERTISING

The app shows ads from the Yandex Advertising Network (Yandex Mobile Ads SDK): a small banner at the bottom of
the screens, an interstitial after some speed tests, and an optional rewarded video (the "Deep AI audit" card on
the AI tab). The device location is NOT passed to the ad SDK (location tracking is switched off for it); location
permission is requested only for the route recording described above. After launch the app shows the system
App Tracking Transparency prompt once. Ads work if the user declines ("Ask App Not to Track"); they are just not
personalised.

The app's interface is in Russian.
```

---

## 2. Чек-лист перед отправкой на ревью

1. **App Privacy.** Код NetPulse координаты никуда не отправляет, а рекламному SDK Яндекса геолокация отключена в коде (`YandexAds.setLocationTracking(false)` в `YandexAdManager.start()`). Но SDK Яндекса (внутри него работает AppMetrica) собирает свои данные: как минимум идентификаторы устройства и рекламы (IDFA, если пользователь разрешил отслеживание), сведения о показах и нажатиях на рекламу, диагностику (сбои, производительность). Откройте документацию Яндекса о данных, которые собирает SDK, и отметьте в App Privacy всё перечисленное там; данные, которые используются для рекламы и отслеживания, отметьте как «Используются для отслеживания». Приложение показывает окно App Tracking Transparency, поэтому ответ «не отслеживаем» был бы неверным. Ответ должен совпадать с действительностью.
2. **Рекламные блоки.** В `YandexAdConfig` стоят демо-блоки Яндекса: реклама тестовая и дохода не приносит. Перед выпуском создайте приложение и три блока в кабинете РСЯ и подставьте их идентификаторы (подробнее — в `README.md`, раздел «Что настроить перед выпуском»). Политика конфиденциальности должна упоминать рекламу Яндекса.
3. **Подписки нет.** PRO удалён: приложение бесплатное, игровой HUD и глубокий AI-аудит доступны всем. Реклама Яндекса в выпускной сборке включается только с боевыми блоками (с демо-блоками она выключена).
4. **Показ рекламы в странах ЕС.** Окна согласия на персонализацию (CMP) в приложении нет, `YandexAds.setUserConsent` не вызывается: по документации Яндекса значение по умолчанию — «согласия нет». Если приложение будет доступно в странах ЕС, подумайте о форме согласия (модуль `YandexMobileAdsConsentManagement` в том же пакете) или ограничьте страны распространения.
5. **Политика конфиденциальности** (ссылка обязательна) должна упоминать запись маршрутов: что именно сохраняется (положение, качество сети, время), что всё хранится на устройстве, как удалить.
6. **Проверка на устройстве перед отправкой:** значок геолокации в строке состояния во время записи; запись продолжается при заблокированном экране и в другом приложении; «Остановить и сохранить» сохраняет маршрут; в запросе разрешения видны все кнопки (в том числе «При использовании приложения»); «Удалить все» стирает маршруты.
7. **Скриншоты для App Store:** карта с маршрутом (в развёрнутой панели кнопка «Показать пример маршрута» рисует демо-маршрут с пометкой «Пример · демо-данные» — в скриншоте для магазина лучше использовать настоящую запись).
8. **Фоновая запись.** Фоновая геолокация включается только записью, которую начал сам пользователь. В «Настройки → Запись маршрута» есть тумблер «Записывать маршрут в фоне» (по умолчанию включён; выключенный — свёрнутое приложение не получает геолокацию и значок в строке состояния не появляется) и тумблер автоостановки: через 20 минут без движения маршрут сохраняется, запись останавливается.
   **Запись после закрытия приложения** — отдельный тумблер «Продолжать запись после закрытия приложения» (по умолчанию выключен). Включённый, он просит доступ «Всегда» (текст запроса в `NSLocationAlwaysAndWhenInUseUsageDescription`) и, пока идёт запись, включает слежение за значительными перемещениями: iOS может запустить закрытое приложение, и запись продолжится в том же маршруте. Это единственное место, где нужен «Всегда»; без тумблера приложение его не просит. Рецензент может спросить, зачем «Всегда»: ответ уже есть в тексте Notes (только пока идёт запись, только по желанию пользователя, ничего другого при запуске не делается). Если Apple откажет именно из-за «Всегда», уберите тумблер и ключ `NSLocationAlwaysAndWhenInUseUsageDescription`, остальное можно оставить.
   **Режим экономии заряда** («Настройки», первый раздел, по умолчанию выключен) не добавляет сбора данных: он только ослабляет работу приложения. В описание для ревью его вносить не обязательно, но он упомянут в Notes.
9. **Манифест приватности.** В проекте нет `PrivacyInfo.xcprivacy`, хотя приложение использует API, требующие объявления причины (например, `UserDefaults`, отметки времени файлов). При загрузке в App Store Connect могут прийти замечания `ITMS-91053`. Это отдельная задача: нужно добавить манифест приложения и убедиться, что SDK приносят свои.
10. **Если ревью отклонит запись маршрута** — убрать `location` из `UIBackgroundModes` и экран записи в магазинной сборке (функции в сборке просто не будет), а не прятать её. Остров продолжит обновляться, пока приложение открыто, и покажет «паузу» в фоне.
