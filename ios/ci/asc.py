#!/usr/bin/env python3
"""Работа с App Store Connect API: проверка состояния карточки приложения, заполнение и отправка на проверку.

Использование:  asc.py inspect|prepare|submit

Ключ берётся из окружения (секреты репозитория): ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_CONTENT (содержимое .p8).
Репозиторий публичный, поэтому журнал запуска видят все: контактные данные (имена, телефоны, почта) в него не
печатаются, а ключ и токен не печатаются никогда.
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.samvel.netpulse")
ROOT = Path(__file__).resolve().parents[2]   # корень репозитория (ios/ci/asc.py)
META = ROOT / "appstore"                     # тексты карточки, настройки, скриншоты

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



# ---------------------------------------------------------------------------------------------------------------------
# prepare: заполнение карточки
# ---------------------------------------------------------------------------------------------------------------------

def load_config():
    return json.loads((META / "config.json").read_text(encoding="utf-8"))


def meta_text(relative, default=None):
    path = META / relative
    if path.exists():
        text = path.read_text(encoding="utf-8").strip()
        return text or default
    return default


def payload(type_, attributes=None, relationships=None, id_=None):
    data = {"type": type_}
    if id_:
        data["id"] = id_
    if attributes is not None:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    return {"data": data}


def link(type_, id_):
    return {"data": {"type": type_, "id": id_}}


def report(ok, text):
    print(("  ✅ " if ok else "  ❌ ") + text)
    return ok


def safe_step(title, func):
    """Шаг заполнения: ошибка печатается подробно, но остальные шаги всё равно выполняются."""
    print(f"=== {title}")
    result = attempt(title, func)
    return result


def upsert_localization(kind, parent_path, parent_type, parent_id, locale, attrs, patch_keys):
    """Создаёт или обновляет локализацию. kind: appInfoLocalizations | appStoreVersionLocalizations."""
    existing = [l for l in get_all(parent_path)[0] if l["attributes"].get("locale") == locale]
    clean = {k: v for k, v in attrs.items() if v is not None}
    if existing:
        loc_id = existing[0]["id"]
        patch = {k: v for k, v in clean.items() if k in patch_keys}
        request("PATCH", f"/v1/{kind}/{loc_id}", body=payload(kind, patch, id_=loc_id))
        print(f"    {kind} {locale}: обновлено ({', '.join(sorted(patch))})")
        return loc_id
    parent_rel = {"appInfo": link("appInfos", parent_id)} if parent_type == "appInfos" else {"appStoreVersion": link("appStoreVersions", parent_id)}
    created = request("POST", f"/v1/{kind}", body=payload(kind, {"locale": locale, **clean}, parent_rel))
    print(f"    {kind} {locale}: создано")
    return created["data"]["id"]


def current_version(app_id):
    versions = get_all(f"/v1/apps/{app_id}/appStoreVersions", {"filter[platform]": "IOS"})[0]
    editable = [v for v in versions if v["attributes"].get("appStoreState") in (
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    if not editable:
        sys.exit("Нет версии, которую можно редактировать (все уже отправлены или выпущены)")
    return editable[0]


def upload_screenshots(loc_id, display_candidates, files):
    sets = get_all(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")[0]
    by_type = {s["attributes"]["screenshotDisplayType"]: s for s in sets}
    set_id, used_type = None, None
    for display_type in display_candidates:
        try:
            if display_type in by_type:
                set_id = by_type[display_type]["id"]
            else:
                created = request("POST", "/v1/appScreenshotSets", body=payload(
                    "appScreenshotSets", {"screenshotDisplayType": display_type},
                    {"appStoreVersionLocalization": link("appStoreVersionLocalizations", loc_id)}))
                set_id = created["data"]["id"]
            used_type = display_type
            break
        except ApiError as exc:
            print(f"    набор {display_type}: {exc.status} {exc.errors if not isinstance(exc.errors, list) else [e.get('detail') for e in exc.errors]}")
    if not set_id:
        raise ApiError(0, "не удалось создать набор скриншотов ни для одного из вариантов " + ", ".join(display_candidates), "POST", "appScreenshotSets")

    for old in get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots")[0]:
        request("DELETE", f"/v1/appScreenshots/{old['id']}")

    ids = []
    for path in files:
        data = path.read_bytes()
        created = request("POST", "/v1/appScreenshots", body=payload(
            "appScreenshots", {"fileName": path.name, "fileSize": len(data)},
            {"appScreenshotSet": link("appScreenshotSets", set_id)}))
        shot_id = created["data"]["id"]
        for op in created["data"]["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]: op["offset"] + op["length"]]
            headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            request(op["method"], op["url"], raw=chunk, headers=headers, absolute=True)
        request("PATCH", f"/v1/appScreenshots/{shot_id}", body=payload(
            "appScreenshots", {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}, id_=shot_id))
        state = "?"
        for _ in range(60):
            info = get(f"/v1/appScreenshots/{shot_id}")["data"]["attributes"]
            state = (info.get("assetDeliveryState") or {}).get("state", "?")
            if state in ("COMPLETE", "FAILED"):
                if state == "FAILED":
                    print("      ошибки:", (info.get("assetDeliveryState") or {}).get("errors"))
                break
            time.sleep(2)
        print(f"    {used_type}: {path.name} → {state}")
        ids.append(shot_id)
    if ids:
        request("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
                body={"data": [{"type": "appScreenshots", "id": i} for i in ids]})
    return used_type


def set_free_price(app_id):
    existing = attempt("Цена (проверка)", lambda: get(f"/v1/apps/{app_id}/appPriceSchedule"))
    if existing and existing.get("data"):
        print("    цена уже задана")
        return
    points, _ = get_all(f"/v1/apps/{app_id}/appPricePoints", {"filter[territory]": "USA", "limit": 200})
    free = [p for p in points if str(p["attributes"].get("customerPrice")) in ("0", "0.0", "0.00")]
    if not free:
        raise ApiError(0, "не нашлась точка цены «бесплатно»", "GET", "appPricePoints")
    request("POST", "/v1/appPriceSchedules", body={
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": link("apps", app_id),
            "baseTerritory": link("territories", "USA"),
            "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
        "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": link("appPricePoints", free[0]["id"])}}],
    })
    print("    цена: бесплатно")


def set_availability(app_id, territories):
    all_ids = [t["id"] for t in get_all("/v1/territories", {"limit": 200})[0]]
    chosen = all_ids if territories == "ALL" else [t for t in territories if t in all_ids]
    if not chosen:
        raise ApiError(0, "список стран пуст", "GET", "territories")
    existing = attempt("Доступность (проверка)", lambda: get(f"/v1/apps/{app_id}/appAvailabilityV2"))
    if existing and existing.get("data"):
        print("    доступность уже задана")
        return
    included = []
    for index, territory in enumerate(chosen):
        included.append({"type": "territoryAvailabilities", "id": f"${{t{index}}}", "attributes": {"available": True},
                         "relationships": {"territory": link("territories", territory)}})
    request("POST", "/v2/appAvailabilities", body={
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": territories == "ALL"},
                 "relationships": {"app": link("apps", app_id),
                                   "territoryAvailabilities": {"data": [{"type": i["type"], "id": i["id"]} for i in included]}}},
        "included": included,
    })
    print(f"    страны: {len(chosen)}")


def attach_build(app_id, version_id, number):
    found = get("/v1/builds", {"filter[app]": app_id, "filter[version]": str(number), "include": "preReleaseVersion", "limit": 5})
    builds = found.get("data", [])
    if not builds:
        raise ApiError(0, f"сборка {number} не найдена", "GET", "builds")
    build = builds[0]
    state = build["attributes"].get("processingState")
    pre = next((i for i in found.get("included", []) if i.get("type") == "preReleaseVersions"), None)
    print(f"    сборка {number}: {state}, версия в сборке {(pre or {}).get('attributes', {}).get('version')}")
    if state != "VALID":
        raise ApiError(0, f"сборка {number} ещё не готова: {state}", "GET", "builds")
    request("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", body={"data": {"type": "builds", "id": build["id"]}})
    print(f"    к версии привязана сборка {number}")


def prepare():
    cfg = load_config()
    locale = cfg.get("locale", "ru")
    app = find_app()
    app_id = app["id"]
    print(f"Приложение {app['attributes'].get('name')} ({app_id}), основной язык сейчас {app['attributes'].get('primaryLocale')}")

    version = current_version(app_id)
    version_id = version["id"]
    infos = get_all(f"/v1/apps/{app_id}/appInfos")[0]
    info_id = infos[0]["id"]

    # 1. Приложение: права на контент
    def step_app():
        request("PATCH", f"/v1/apps/{app_id}", body=payload("apps", {"contentRightsDeclaration": cfg.get("contentRightsDeclaration", "DOES_NOT_USE_THIRD_PARTY_CONTENT")}, id_=app_id))
        print("    права на контент заявлены")
    safe_step("Приложение", step_app)

    # 2. Тексты: информация о приложении (название, подзаголовок, политика) и версии (описание, ключевые слова…)
    def step_info():
        upsert_localization("appInfoLocalizations", f"/v1/appInfos/{info_id}/appInfoLocalizations", "appInfos", info_id, locale, {
            "name": cfg.get("name"),
            "subtitle": meta_text(f"metadata/{locale}/subtitle.txt"),
            "privacyPolicyUrl": meta_text(f"metadata/{locale}/privacy_url.txt"),
        }, {"name", "subtitle", "privacyPolicyUrl"})
    safe_step("Информация о приложении", step_info)

    loc_id_holder = {}

    def step_version_text():
        loc_id_holder["id"] = upsert_localization(
            "appStoreVersionLocalizations", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations",
            "appStoreVersions", version_id, locale, {
                "description": meta_text(f"metadata/{locale}/description.txt"),
                "keywords": meta_text(f"metadata/{locale}/keywords.txt"),
                "promotionalText": meta_text(f"metadata/{locale}/promotional_text.txt"),
                "supportUrl": meta_text(f"metadata/{locale}/support_url.txt"),
                "marketingUrl": meta_text(f"metadata/{locale}/marketing_url.txt"),
            }, {"description", "keywords", "promotionalText", "supportUrl", "marketingUrl"})
    safe_step("Тексты версии", step_version_text)

    # 3. Основной язык — русский (если не получится, остаётся прежний, а тексты лежат в обоих языках)
    def step_primary():
        if app["attributes"].get("primaryLocale") == locale:
            print("    основной язык уже", locale)
            return
        request("PATCH", f"/v1/apps/{app_id}", body=payload("apps", {"primaryLocale": locale}, id_=app_id))
        print("    основной язык теперь", locale)
        # Прежняя локализация с пустым описанием больше не нужна и мешала бы отправке
        for loc in get_all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")[0]:
            if loc["attributes"].get("locale") != locale and not loc["attributes"].get("description"):
                request("DELETE", f"/v1/appStoreVersionLocalizations/{loc['id']}")
                print("    удалена пустая локализация версии", loc["attributes"].get("locale"))
        for loc in get_all(f"/v1/appInfos/{info_id}/appInfoLocalizations")[0]:
            if loc["attributes"].get("locale") != locale:
                request("DELETE", f"/v1/appInfoLocalizations/{loc['id']}")
                print("    удалена локализация сведений", loc["attributes"].get("locale"))
    if cfg.get("switchPrimaryLocale", True):
        safe_step("Основной язык", step_primary)

    # 4. Категории и возрастной рейтинг
    def step_categories():
        rels = {"primaryCategory": link("appCategories", cfg.get("primaryCategory", "UTILITIES"))}
        secondary = cfg.get("secondaryCategory")
        rels["secondaryCategory"] = link("appCategories", secondary) if secondary else {"data": None}
        request("PATCH", f"/v1/appInfos/{info_id}", body=payload("appInfos", None, rels, id_=info_id))
        print("    категории заданы")
    safe_step("Категории", step_categories)

    def step_age():
        declaration = get(f"/v1/appInfos/{info_id}/ageRatingDeclaration")["data"]
        request("PATCH", f"/v1/ageRatingDeclarations/{declaration['id']}", body=payload("ageRatingDeclarations", cfg["ageRating"], id_=declaration["id"]))
        print("    возрастной рейтинг заполнен")
    safe_step("Возрастной рейтинг", step_age)

    # 5. Версия: вид выпуска, авторские права, номер версии
    def step_version():
        attrs = {"releaseType": cfg.get("releaseType", "MANUAL")}
        copyright_text = meta_text("metadata/copyright.txt")
        if copyright_text:
            attrs["copyright"] = copyright_text
        if cfg.get("versionString") and cfg["versionString"] != version["attributes"].get("versionString"):
            attrs["versionString"] = cfg["versionString"]
        request("PATCH", f"/v1/appStoreVersions/{version_id}", body=payload("appStoreVersions", attrs, id_=version_id))
        print("    версия обновлена:", ", ".join(f"{k}={v}" for k, v in attrs.items()))
    safe_step("Версия", step_version)

    # 6. Скриншоты
    shots_dir = Path(os.environ.get("SHOTS_DIR", str(ROOT / "screenshots")))

    def step_screens():
        loc_id = loc_id_holder.get("id")
        if not loc_id:
            raise ApiError(0, "нет локализации версии для скриншотов", "-", "-")
        for kind, display_candidates in (("iphone", cfg["displayTypes"]["iphone"]), ("ipad", cfg["displayTypes"]["ipad"])):
            names = cfg.get("screenshots", {}).get(kind, [])
            files = [shots_dir / kind / f"{name}.png" for name in names]
            missing = [f for f in files if not f.exists()]
            if missing:
                print(f"    {kind}: нет файлов {[m.name for m in missing]} — пропускаю")
                continue
            if not files:
                continue
            upload_screenshots(loc_id, display_candidates, files)
    safe_step("Скриншоты", step_screens)

    # 7. Сведения для рецензента (контакты вносит владелец в App Store Connect: репозиторий публичный)
    def step_review():
        notes = meta_text("review_notes.txt", "")
        existing = get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
        attrs = {"demoAccountRequired": False, "notes": notes}
        if existing:
            request("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", body=payload("appStoreReviewDetails", attrs, id_=existing["id"]))
            print(f"    заметки для рецензента обновлены ({len(notes)} симв.)")
        else:
            request("POST", "/v1/appStoreReviewDetails", body=payload("appStoreReviewDetails", attrs, {"appStoreVersion": link("appStoreVersions", version_id)}))
            print(f"    заметки для рецензента созданы ({len(notes)} симв.)")
    safe_step("Сведения для рецензента", step_review)

    # 8. Цена и страны
    safe_step("Цена", lambda: set_free_price(app_id))
    if cfg.get("territories"):
        safe_step("Страны", lambda: set_availability(app_id, cfg["territories"]))
    else:
        print("=== Страны: в config.json не выбраны (territories), пропускаю")

    # 9. Сборка
    if cfg.get("build"):
        safe_step("Сборка", lambda: attach_build(app_id, version_id, cfg["build"]))

    print()
    checklist(app_id)


def checklist(app_id):
    """Что ещё мешает отправке: по данным App Store Connect. Возвращает True, если мешает только невидимое API."""
    print("=== Готовность к отправке")
    version = current_version(app_id)
    version_id = version["id"]
    app = get(f"/v1/apps/{app_id}")["data"]
    info = get_all(f"/v1/apps/{app_id}/appInfos", {"include": "primaryCategory"})
    info_item = info[0][0]
    problems = 0

    def check(ok, text):
        nonlocal problems
        if not report(ok, text):
            problems += 1

    locs = get_all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")[0]
    check(bool(locs), "есть локализация версии")
    for loc in locs:
        a = loc["attributes"]
        tag = a.get("locale")
        check(bool(a.get("description")), f"[{tag}] описание")
        check(bool(a.get("keywords")), f"[{tag}] ключевые слова")
        check(bool(a.get("supportUrl")), f"[{tag}] ссылка на поддержку")
        sets = get_all(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")[0]
        for shot_set in sets:
            count = len(get_all(f"/v1/appScreenshotSets/{shot_set['id']}/appScreenshots")[0])
            check(count >= 1, f"[{tag}] скриншоты {shot_set['attributes'].get('screenshotDisplayType')}: {count}")
        check(bool(sets), f"[{tag}] есть хотя бы один набор скриншотов")
    for loc in get_all(f"/v1/appInfos/{info_item['id']}/appInfoLocalizations")[0]:
        a = loc["attributes"]
        check(bool(a.get("name")), f"[{a.get('locale')}] название")
        check(bool(a.get("privacyPolicyUrl")), f"[{a.get('locale')}] ссылка на политику конфиденциальности")
    check(bool((info_item.get("relationships", {}).get("primaryCategory") or {}).get("data")), "основная категория")
    check(bool(version["attributes"].get("copyright")), "авторские права (©)")
    build = attempt("Сборка", lambda: get(f"/v1/appStoreVersions/{version_id}/build"))
    check(bool(build and build.get("data")), "к версии привязана сборка")
    if build and build.get("data"):
        print("      сборка:", build["data"]["attributes"].get("version"), build["data"]["attributes"].get("processingState"))
    detail = attempt("Сведения для рецензента", lambda: get(f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail"))
    d = ((detail or {}).get("data") or {}).get("attributes") or {}
    check(bool(d), "есть сведения для рецензента")
    check(bool(d.get("contactFirstName") and d.get("contactLastName")), "контакт рецензента: имя и фамилия")
    check(bool(d.get("contactPhone")), "контакт рецензента: телефон")
    check(bool(d.get("contactEmail")), "контакт рецензента: почта")
    check(bool(d.get("notes")), "заметки для рецензента")
    price = attempt("Цена", lambda: get(f"/v1/apps/{app_id}/appPriceSchedule"))
    check(bool(price and price.get("data")), "цена задана")
    avail = attempt("Доступность", lambda: get(f"/v1/apps/{app_id}/appAvailabilityV2"))
    check(bool(avail and avail.get("data")), "страны заданы")
    age = attempt("Возраст", lambda: get(f"/v1/appInfos/{info_item['id']}/ageRatingDeclaration"))
    check(bool(age and (age.get("data") or {}).get("attributes", {}).get("violenceRealistic")), "возрастной рейтинг заполнен")
    check(bool(app["attributes"].get("contentRightsDeclaration")), "права на контент заявлены")
    print("  ℹ️ «Конфиденциальность приложения» (App Privacy) через API не видна и не заполняется: её вносит владелец в App Store Connect.")
    print(f"Не хватает пунктов: {problems}")
    return problems == 0


# ---------------------------------------------------------------------------------------------------------------------
# submit: отправка на проверку
# ---------------------------------------------------------------------------------------------------------------------

def submit():
    if os.environ.get("ASC_CONFIRM", "") != "ОТПРАВИТЬ":
        sys.exit("Для отправки на проверку нужно подтверждение: confirm=ОТПРАВИТЬ")
    app = find_app()
    app_id = app["id"]
    if not checklist(app_id):
        sys.exit("Карточка заполнена не полностью: отправка остановлена (список выше)")
    version = current_version(app_id)
    submission = request("POST", "/v1/reviewSubmissions", body=payload("reviewSubmissions", {"platform": "IOS"}, {"app": link("apps", app_id)}))
    sid = submission["data"]["id"]
    print("создана отправка", sid)
    request("POST", "/v1/reviewSubmissionItems", body=payload("reviewSubmissionItems", None, {
        "reviewSubmission": link("reviewSubmissions", sid), "appStoreVersion": link("appStoreVersions", version["id"])}))
    done = request("PATCH", f"/v1/reviewSubmissions/{sid}", body=payload("reviewSubmissions", {"submitted": True}, id_=sid))
    print("отправлено на проверку, состояние:", done["data"]["attributes"].get("state"))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    command = sys.argv[1]
    if command == "inspect":
        inspect()
    elif command == "prepare":
        prepare()
    elif command == "submit":
        submit()
    else:
        print(f"Неизвестная команда: {command}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
