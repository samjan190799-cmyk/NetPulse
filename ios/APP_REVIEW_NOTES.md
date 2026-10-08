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

The app contains no advertising, no third-party SDKs, no analytics and does not track users: it does not use the
AppTrackingTransparency framework and does not request the App Tracking Transparency permission. The App Privacy
answers are "Data Not Collected". The app has no account and no server.

The AI audit runs entirely on the device: the app uses no external AI services and sends no measurements
anywhere. The app has no microphone or speech-recognition features and asks for neither permission.

SUBSCRIPTION (NetPulse PRO)

NetPulse PRO is ONE auto-renewable subscription (group "NetPulse PRO", product com.samvel.netpulse.pro.monthly2,
USD 0.99 per month). It unlocks exactly three features:
1. Speed in the Dynamic Island / Live Activity (Settings -> "Dynamic Island", or the "Островок" button on the map).
2. The floating game HUD inside the app (Settings -> "Плавающий игровой оверлей (HUD)").
3. The deep AI audit (the "AI-аудит" tile in the "Инструменты" tab: network health score, anomaly prediction, troubleshooting wizard,
   ISP complaint letter).
Everything else is free: speed test, route recording and the network map, traffic accounting, DNS / bufferbloat /
LAN / gaming tools, the Home Screen widget, the quick AI verdict after a speed test.

How to see the paywall: tap the slider button on the map -> "NetPulse PRO" (or tap "Островок", or open the
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

1. **App Privacy.** В версии 1.0 нет ни рекламы, ни сторонних SDK, ни аналитики, поэтому ответ: «Данные не собираются», отслеживания нет (ни одного типа данных с пометкой «Используется для отслеживания»). Проверьте, что в App Store Connect → App Privacy именно так: раньше там были отмечены ID устройства, рекламные данные, взаимодействие с продуктом и примерная геолокация «для сторонней рекламы», что противоречит сборке без рекламы. Менять App Privacy может Account Holder или Admin.
2. **Рекламы нет, есть подписка PRO.** Реклама Яндекса вместе с ATT удалена из сборки (запрос ATT приводил к отказу 2.1: окно не показывалось, потому что стояли демо-блоки). Подписка NetPulse PRO (1 USD в месяц) открывает остров, игровой HUD и глубокий AI-аудит. Подписку нужно создать в App Store Connect (группа «NetPulse PRO», продукт `com.samvel.netpulse.pro.monthly2`, цена 0.99 USD, локализация, скриншот окна подписки для проверки) и отправить на проверку вместе с версией: первая подписка проверяется только вместе с приложением. Если реклама вернётся, обновите App Privacy, политику конфиденциальности и этот файл до выхода версии.
3. **Манифест приватности.** `PrivacyInfo.xcprivacy` лежит в приложении и в расширении виджетов: UserDefaults (CA92.1 и 1C8F.1 для общей группы приложений) и время загрузки системы (35F9.1, `kern.boottime` для счётчиков трафика). Сборка без отслеживания и без собираемых данных. Если добавите SDK или новые API из списка Apple, обновите манифест.
4. **Виджеты.** В Notes можно ответить на вопрос рецензента о виджетах: они есть (см. выше, раздел WIDGETS AND LIVE ACTIVITY).
5. **Политика конфиденциальности** (ссылка обязательна) должна упоминать запись маршрутов: что именно сохраняется (положение, качество сети, время), что всё хранится на устройстве, как удалить.
6. **Проверка на устройстве перед отправкой:** значок геолокации в строке состояния во время записи; запись продолжается при заблокированном экране и в другом приложении; «Остановить и сохранить» сохраняет маршрут; в запросе разрешения видны все кнопки (в том числе «При использовании приложения»); «Удалить все» стирает маршруты.
7. **Скриншоты для App Store:** карта с маршрутом (в развёрнутой панели кнопка «Показать пример маршрута» рисует демо-маршрут с пометкой «Пример · демо-данные» — в скриншоте для магазина лучше использовать настоящую запись).
8. **Фоновая запись.** Фоновая геолокация включается только записью, которую начал сам пользователь. В «Настройки → Запись маршрута» есть тумблер «Записывать маршрут в фоне» (по умолчанию включён; выключенный — свёрнутое приложение не получает геолокацию и значок в строке состояния не появляется) и тумблер автоостановки: через 20 минут без движения маршрут сохраняется, запись останавливается.
9. **Если ревью отклонит запись маршрута** — убрать `location` из `UIBackgroundModes` и экран записи в магазинной сборке (функции в сборке просто не будет), а не прятать её. Остров продолжит обновляться, пока приложение открыто, и покажет «паузу» в фоне.
