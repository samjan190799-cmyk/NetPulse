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
- All other features (speed test, diagnostics, widgets, Dynamic Island) work without location permission.
  Nothing is gated behind location.

A side effect of recording: while the app records in the background, the Dynamic Island keeps showing
live network speed.

The map is the home screen of the app (Apple's MapKit, Apple Maps). It is visible before any permission is
requested (without location access it shows an overview of European Russia). The user's position is shown by MapKit's user-location annotation only while the screen is open and location is
authorized (the app supplies only its look, a blue dot); the route lines are drawn from the points recorded by the app.

Coverage layer: along each recorded route the map draws a wide translucent band in the colour of the line
(green good, yellow fair, orange poor, red no connection). It is drawn live while recording and, on the home
screen, for earlier routes too (the "Покрытие сети" / Network coverage button hides it). Around the user's dot
there is a coloured zone with the quality of the connection right now; its colour comes from the app's own
network check (ping), not from location data. All of it is computed on the device from the app's own
measurements; no data about operators' coverage is used or sent.

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

ADVERTISING AND TRACKING

The app shows ads from the Yandex Advertising Network (Yandex Mobile Ads SDK) to users without a subscription: a small
banner at the bottom of the screens and an interstitial after some speed tests. Subscribers of NetPulse PRO (see below)
see no ads and no tracking prompt. The device location is NOT passed to the ad SDK (location tracking is switched off
for it); location permission is requested only for the route recording described above.

On the first launch the app shows the system App Tracking Transparency prompt once (it appears right after the
app starts, before the first ad request). Ads also work if the user declines ("Ask App Not to Track"); they are just
not personalised. The App Privacy answers in App Store Connect declare the data of the ad SDK: Device ID (linked, used
for tracking), Product Interaction, Crash Data, Performance Data, Other Diagnostic Data and Other Data.
The app has no account and no server.

The AI audit runs entirely on the device: the app uses no external AI services and sends no measurements
anywhere. The app has no microphone or speech-recognition features and asks for neither permission.

SUBSCRIPTION (NetPulse PRO)

NetPulse PRO is ONE auto-renewable subscription (group "NetPulse PRO", product com.samvel.netpulse.pro.monthly2,
USD 0.99 per month). It unlocks these features (the main three first):
1. Speed in the Dynamic Island / Live Activity ("Настройки" tab -> "Dynamic Island", or the "Островок" button on the map).
2. The floating game HUD inside the app ("Настройки" tab -> "Плавающий игровой оверлей (HUD)").
3. The deep AI audit (the "AI-аудит" tile in the "Инструменты" tab: network health score, anomaly prediction, troubleshooting wizard,
   ISP complaint letter).
4. Also included: service availability check, speed-test history with charts, a PDF report for the ISP, the speed map during
   route recording, network alerts and route export (GPX / map image).
It also removes the ads. Everything else is free: speed test, route recording and the network map, traffic accounting, DNS / bufferbloat /
LAN / gaming tools, the Home Screen widget, the quick AI verdict after a speed test.

How to see the paywall: open the "Настройки" tab -> "NetPulse PRO" (or tap "Островок", or open the
"Инструменты" tab -> "AI-аудит"). The paywall shows the price from the App Store, the billing period, the auto-renewal terms,
links to the Terms of Use (Apple standard EULA) and the Privacy Policy, and a "Восстановить покупки"
(Restore Purchases) button. Purchases are handled only by StoreKit; the app has no account and no server.

WIDGETS AND LIVE ACTIVITY

The app includes a Home Screen widget ("NetPulse Монитор", WidgetKit: network status, latency, connection speed and
data usage) and a Live Activity shown on the Lock Screen and in the Dynamic Island with live speed and latency.
Both work without location permission.

The app's interface is in Russian.
```

---

## 2. Чек-лист перед отправкой на ревью

1. **App Privacy.** Приложение показывает рекламу Яндекса и запрашивает IDFA после разрешения пользователя, поэтому в App Store Connect → App Privacy должны быть заявлены шесть типов данных: ID устройства (связано с пользователем, для отслеживания; цели — сторонняя реклама, реклама разработчика, аналитика), взаимодействие с продуктом, данные о сбоях, данные о производительности, другие данные диагностики и другие данные (не связаны с пользователем, без отслеживания). Это уже сделано; `PrivacyInfo.xcprivacy` объявляет то же самое (`NSPrivacyTracking = true`). Геолокация рекламному SDK отключена в коде (`YandexAds.setLocationTracking(false)` в `YandexAdManager.start()`), маршруты остаются на устройстве. Менять App Privacy может Account Holder или Admin.
2. **Реклама и подписка PRO.** Бесплатные пользователи видят рекламу Яндекса (баннер, межстраничную после замеров) и один раз после запуска системное окно ATT; подписчики PRO не видят ни рекламы, ни окна. Окно ATT показывается при первом запуске (раньше отказ 2.1 был из-за того, что в сборке для ревью реклама, а значит и окно, не включалась). В выпускной сборке работают боевые блоки РСЯ приложения 20229806 (`YandexAdConfig.live…`); владение приложением в кабинете РСЯ подтверждено, модерация пройдена. Подписка NetPulse PRO (0,99 USD в месяц) открывает остров, игровой HUD, глубокий AI-аудит и другие платные возможности. Подписку нужно создать в App Store Connect (группа «NetPulse PRO», продукт `com.samvel.netpulse.pro.monthly2`, цена 0.99 USD, локализация, скриншот окна подписки для проверки) и отправить на проверку вместе с версией: первая подписка проверяется только вместе с приложением.
3. **Манифест приватности.** `PrivacyInfo.xcprivacy` лежит в приложении и в расширении виджетов: UserDefaults (CA92.1 и 1C8F.1 для общей группы приложений) и время загрузки системы (35F9.1, `kern.boottime` для счётчиков трафика). В манифесте приложения заявлены отслеживание и шесть типов данных рекламного SDK (как в App Privacy). Если добавите SDK или новые API из списка Apple, обновите манифест.
4. **Показ рекламы в странах ЕС.** Окна согласия на персонализацию (CMP) в приложении нет, `YandexAds.setUserConsent` не вызывается: по документации Яндекса значение по умолчанию — «согласия нет». Если приложение будет доступно в странах ЕС, подумайте о форме согласия (модуль `YandexMobileAdsConsentManagement` в том же пакете) или ограничьте страны распространения.
5. **Виджеты.** В Notes можно ответить на вопрос рецензента о виджетах: они есть (см. выше, раздел WIDGETS AND LIVE ACTIVITY).
6. **Политика конфиденциальности** (ссылка обязательна) должна упоминать запись маршрутов: что именно сохраняется (положение, качество сети, время), что всё хранится на устройстве, как удалить.
7. **Проверка на устройстве перед отправкой:** значок геолокации в строке состояния во время записи; запись продолжается при заблокированном экране и в другом приложении; «Остановить и сохранить» сохраняет маршрут; в запросе разрешения видны все кнопки (в том числе «При использовании приложения»); «Удалить все» стирает маршруты.
8. **Скриншоты для App Store:** карта с маршрутом (в развёрнутой панели кнопка «Показать пример маршрута» рисует демо-маршрут с пометкой «Пример · демо-данные» — в скриншоте для магазина лучше использовать настоящую запись).
9. **Фоновая запись.** Фоновая геолокация включается только записью, которую начал сам пользователь. В «Настройки → Запись маршрута» есть тумблер «Записывать маршрут в фоне» (по умолчанию включён; выключенный — свёрнутое приложение не получает геолокацию и значок в строке состояния не появляется) и тумблер автоостановки: через 20 минут без движения маршрут сохраняется, запись останавливается.
10. **Если ревью отклонит запись маршрута** — убрать `location` из `UIBackgroundModes` и экран записи в магазинной сборке (функции в сборке просто не будет), а не прятать её. Остров продолжит обновляться, пока приложение открыто, и покажет «паузу» в фоне.
