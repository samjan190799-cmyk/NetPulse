#!/usr/bin/env python3
"""Работа с App Store Connect API: проверка состояния карточки приложения, заполнение и отправка на проверку.

Использование:  asc.py inspect|prepare|submit

Ключ берётся из окружения (секреты репозитория): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT (содержимое .p8).
Репозиторий публичный, поэтому журнал запуска видят все: контактные данные (имена, телефоны, почта) в него не
печатаются, а ключ и токен не печатаются никогда.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.samvel.netpulse")

# Поля с персональными данными: значения в журнал не попадают
SECRET_FIELDS = {
    "contactFirstName", "contactLastName", "contactPhone", "contactEmail",
    "demoAccountName", "demoAccountPassword",
}


class ApiError(Exception):
    def __init__(self, status, errors, method, path):
        self.status = status
        self.errors = errors
        super().__init__(f"{method} {path}: HTTP {status}: {errors}")


_token_cache = {"value": None, "exp": 0}


def token() -> str:
    now = int(time.time())
    if _token_cache["value"] and _token_cache["exp"] - now > 60:
        return _token_cache["value"]
    key_id = os.environ.get("ASC_KEY_ID", "")
    issuer = os.environ.get("ASC_ISSUER_ID", "")
    key = os.environ.get("ASC_KEY_CONTENT", "")
    if not (key_id and issuer and key):
        sys.exit("Нет секретов ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_CONTENT: ключ App Store Connect не настроен")
    exp = now + 1100
    value = jwt.encode(
        {"iss": issuer, "iat": now, "exp": exp, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )
    _token_cache.update(value=value, exp=exp)
    return value


def request(method, path, params=None, body=None, raw=None, headers=None, absolute=False):
    url = path if absolute else API + path
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params, safe="[],")
    data = raw
    hdrs = dict(headers or {})
    if not absolute:
        hdrs["Authorization"] = "Bearer " + token()
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = resp.read()
            if not payload:
                return {}
            try:
                return json.loads(payload)
            except ValueError:
                return {"_raw": payload.decode("utf-8", "replace")}
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", "replace")
        try:
            errors = json.loads(text).get("errors", text)
        except ValueError:
            errors = text[:500]
        raise ApiError(exc.code, errors, method, path) from None


def get(path, params=None):
    return request("GET", path, params=params)


def get_all(path, params=None):
    """Все страницы списка; возвращает (данные, включённые объекты)."""
    out, included = [], []
    page = get(path, params)
    while True:
        out.extend(page.get("data", []))
        included.extend(page.get("included", []))
        nxt = page.get("links", {}).get("next")
        if not nxt:
            return out, included
        page = request("GET", nxt, absolute=True, headers={"Authorization": "Bearer " + token()})


def mask(attrs):
    result = {}
    for key, value in (attrs or {}).items():
        if key in SECRET_FIELDS:
            result[key] = "<задано>" if value else "<пусто>"
        elif isinstance(value, str) and len(value) > 160:
            result[key] = f"<текст, {len(value)} симв.> " + value[:60].replace("\n", " ") + "…"
        else:
            result[key] = value
    return result


def show(title, obj):
    print(f"--- {title}")
    print(json.dumps(obj, ensure_ascii=False, indent=1, default=str))


def attempt(title, func):
    """Выполняет запрос; ошибку печатает и идёт дальше: так видно, что именно API не разрешает."""
    try:
        return func()
    except ApiError as exc:
        print(f"--- {title}: ОШИБКА HTTP {exc.status}")
        if isinstance(exc.errors, list):
            for err in exc.errors:
                print(f"    {err.get('code')}: {err.get('title')} — {err.get('detail')}")
        else:
            print(f"    {exc.errors}")
        return None


def find_app():
    data = get("/v1/apps", {"filter[bundleId]": BUNDLE_ID, "limit": 5}).get("data", [])
    if not data:
        sys.exit(f"Приложение с bundle id {BUNDLE_ID} в App Store Connect не найдено")
    return data[0]


# ---------------------------------------------------------------------------------------------------------------------
# inspect
# ---------------------------------------------------------------------------------------------------------------------

def inspect():
    app = find_app()
    app_id = app["id"]
    show("Приложение", {"id": app_id, **mask(app["attributes"])})

    versions = attempt("Версии", lambda: get_all(f"/v1/apps/{app_id}/appStoreVersions", {"limit": 20})[0]) or []
    for version in versions:
        show("Версия " + version["attributes"].get("versionString", "?"), {"id": version["id"], **mask(version["attributes"])})
    for version in versions:
        vid = version["id"]
        label = version["attributes"].get("versionString", "?")
        locs = attempt(f"Локализации версии {label}", lambda: get_all(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")[0]) or []
        for loc in locs:
            show(f"Локализация версии {label} / {loc['attributes'].get('locale')}", {"id": loc["id"], **mask(loc["attributes"])})
            sets = attempt("Наборы скриншотов", lambda: get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")[0]) or []
            for shot_set in sets:
                shots = attempt("Скриншоты", lambda: get_all(f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")[0]) or []
                print(f"    набор {shot_set['attributes'].get('screenshotDisplayType')}: скриншотов {len(shots)}")
        detail = attempt(f"Сведения для рецензента {label}", lambda: get(f"/v1/appStoreVersions/{vid}/appStoreReviewDetail"))
        if detail:
            show(f"Сведения для рецензента {label}", mask((detail.get("data") or {}).get("attributes")))
        build = attempt(f"Сборка версии {label}", lambda: get(f"/v1/appStoreVersions/{vid}/build"))
        if build:
            show(f"Сборка версии {label}", mask((build.get("data") or {}).get("attributes")))

    infos = attempt("appInfos", lambda: get_all(f"/v1/apps/{app_id}/appInfos", {"include": "primaryCategory,secondaryCategory"})) or ([], [])
    for info in infos[0]:
        show("appInfo", {"id": info["id"], **mask(info["attributes"]), "relationships": {
            k: (v.get("data") or {}) for k, v in info.get("relationships", {}).items() if k in ("primaryCategory", "secondaryCategory")}})
        locs = attempt("Локализации appInfo", lambda: get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations")[0]) or []
        for loc in locs:
            show("appInfoLocalization " + str(loc["attributes"].get("locale")), {"id": loc["id"], **mask(loc["attributes"])})
        age = attempt("Возрастной рейтинг", lambda: get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration"))
        if age:
            show("Возрастной рейтинг", {"id": (age.get("data") or {}).get("id"), **mask((age.get("data") or {}).get("attributes"))})

    builds = attempt("Сборки", lambda: get("/v1/builds", {"filter[app]": app_id, "limit": 20, "sort": "-uploadedDate"}).get("data", [])) or []
    for build in builds:
        a = build["attributes"]
        print(f"    сборка {a.get('version')}: {a.get('processingState')}, загружена {a.get('uploadedDate')}, "
              f"истекла={a.get('expired')}, шифрование={a.get('usesNonExemptEncryption')}, iOS от {a.get('minOsVersion')}")

    schedule = attempt("Цена", lambda: get(f"/v1/apps/{app_id}/appPriceSchedule", {"include": "manualPrices,baseTerritory"}))
    if schedule:
        show("Цена", {"data": schedule.get("data"), "включено": [(i.get("type"), i.get("id")) for i in schedule.get("included", [])]})
    avail = attempt("Доступность (v1)", lambda: get(f"/v1/apps/{app_id}/appAvailability", {"include": "availableTerritories", "limit[availableTerritories]": 200}))
    if avail:
        terr = [i.get("id") for i in avail.get("included", []) if i.get("type") == "territories"]
        show("Доступность", {"attributes": (avail.get("data") or {}).get("attributes"), "стран": len(terr), "список": terr[:60]})

    iaps = attempt("Покупки в приложении", lambda: get_all(f"/v1/apps/{app_id}/inAppPurchasesV2", {"limit": 50})[0])
    if iaps is not None:
        print(f"--- Покупки в приложении: {len(iaps)}")
        for iap in iaps:
            print("    ", {k: iap["attributes"].get(k) for k in ("productId", "name", "inAppPurchaseType", "state")})
    groups = attempt("Группы подписок", lambda: get_all(f"/v1/apps/{app_id}/subscriptionGroups")[0])
    if groups is not None:
        print(f"--- Группы подписок: {len(groups)}")

    subs = attempt("Отправки на проверку", lambda: get(f"/v1/apps/{app_id}/reviewSubmissions", {"limit": 10}).get("data", [])) or []
    for sub in subs:
        print("    отправка", sub["id"], mask(sub["attributes"]))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    command = sys.argv[1]
    if command == "inspect":
        inspect()
    else:
        print(f"Неизвестная команда: {command}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
