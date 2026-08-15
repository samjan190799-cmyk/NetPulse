# 🚀 Инструкция по автоматической выгрузке NetPulse в TestFlight

В репозитории настроен автоматический CI/CD пайплайн GitHub Actions: [`.github/workflows/testflight.yml`](.github/workflows/testflight.yml), который собирает проект на виртуальной машине macOS, подписывает его и автоматически отправляет в Apple TestFlight.

---

## 🔑 1. Необходимые секреты GitHub (Repository Secrets)

Перейдите в вашем репозитории на GitHub в:
**Settings -> Secrets and variables -> Actions -> New repository secret** и добавьте следующие ключи:

| Имя секрета | Описание | Пример значения |
|:------------|:---------|:----------------|
| `APP_STORE_CONNECT_API_KEY_ID` | Идентификатор ключа App Store Connect API | `2X9R4HXF34` |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID учетной записи Apple Developer | `57246542-96fe-1a63-e053-0824d011072a` |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Полное текстовое содержимое файла ключа `.p8` | `-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMG...` |
| `APPLE_TEAM_ID` | Идентификатор команды разработчика (Team ID) | `V7J345DY58` |

---

## 📋 2. Как получить App Store Connect API Key

1. Войдите на портал [App Store Connect](https://appstoreconnect.apple.com/).
2. Перейдите в раздел **Users and Access (Пользователи и доступ) -> Integrations (Интеграции) -> App Store Connect API**.
3. Нажмите **Generate API Key (Создать ключ API)**:
   - **Name:** `GitHub Actions TestFlight`
   - **Access:** `App Manager` или `Admin`.
4. Скопируйте **Key ID** и **Issuer ID**.
5. Скачайте файл ключа `AuthKey_XXXXXX.p8` *(скачивается только 1 раз)*.
6. Откройте файл `.p8` в любом текстовом редакторе и скопируйте его содержимое целиком в секрет `APP_STORE_CONNECT_API_KEY_CONTENT`.

---

## 📲 3. Запуск сборки и выгрузки в TestFlight

Выгрузка запускается двумя способами:

### Способ A: Автоматически
При каждом `git push` в ветку `main` при изменении файлов в каталоге `ios/`.

### Способ B: Ручной запуск (One-Click)
1. В репозитории на GitHub перейдите на вкладку **Actions**.
2. В левом меню выберите **Выгрузка в TestFlight (Apple App Store Connect)**.
3. Нажмите кнопку **Run workflow**.
4. При необходимости укажите маркетинговую версию (например, `1.0.0`) и описание сборки, затем нажмите **Run workflow**.

---

## 🛡️ Встроенные проверки соответствия (Pre-commit Audit)

* В `Info.plist` установлен ключ `ITSAppUsesNonExemptEncryption = NO` для пропуска опросника шифрования в TestFlight.
* Включен строгий режим проверки многопоточности Swift 6 (`SWIFT_STRICT_CONCURRENCY = complete`).
* Настроена автоматическая генерация номеров билда на базе номера выполнения GitHub Actions (`github.run_number`).
