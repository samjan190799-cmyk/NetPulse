#!/usr/bin/env python3
"""Разбор результатов xcodebuild test: понятные имена вложений xcresult и краткая сводка в Markdown.

Использование:
  xcresult_report.py attachments КАТАЛОГ_ЭКСПОРТА       дать вложениям имена по manifest.json
  xcresult_report.py summary ФАЙЛ.xcresult ЗАГОЛОВОК    вывести сводку Markdown (для $GITHUB_STEP_SUMMARY)

Скрипт не должен ронять шаг CI: любые ошибки разбора печатаются, а код возврата остаётся 0.
"""
import json
import re
import subprocess
import sys
from pathlib import Path


def safe(name: str) -> str:
    return re.sub(r"[^0-9A-Za-zА-Яа-яЁё._-]+", "_", name).strip("_") or "item"


def rename_attachments(directory: Path) -> None:
    manifest_path = directory / "manifest.json"
    if not manifest_path.exists():
        print("manifest.json не найден: имена вложений остаются исходными")
        return

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    renamed = 0
    for test in manifest:
        test_id = str(test.get("testIdentifier", "test"))
        test_name = safe(test_id.split("/")[-1].replace("()", ""))
        for item in test.get("attachments", []):
            source = directory / str(item.get("exportedFileName", ""))
            if not source.is_file():
                continue
            human = safe(Path(str(item.get("suggestedHumanReadableName", source.name))).stem)
            # Xcode дописывает к имени индекс и UUID («_0_6E1B…»): оставляем только заданное в тесте имя
            human = re.split(r"_\d+_[0-9A-Fa-f-]{36}$", human)[0]
            target = directory / f"{test_name}--{human}{source.suffix}"
            counter = 1
            while target.exists():
                counter += 1
                target = directory / f"{test_name}--{human}-{counter}{source.suffix}"
            source.rename(target)
            renamed += 1
    print(f"Переименовано вложений: {renamed}")


def run_json(args):
    completed = subprocess.run(args, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or f"код возврата {completed.returncode}")
    return json.loads(completed.stdout)


def walk_test_cases(node, path, out):
    """Рекурсивно собирает тест-кейсы из вывода `xcresulttool get test-results tests`."""
    if isinstance(node, dict):
        kind = node.get("nodeType")
        name = node.get("name", "")
        if kind == "Test Case":
            failures = [
                child.get("name", "")
                for child in node.get("children", [])
                if isinstance(child, dict) and child.get("nodeType") == "Failure Message"
            ]
            out.append({
                "name": f"{path}/{name}" if path else name,
                "result": node.get("result", "?"),
                "duration": node.get("durationInSeconds") or node.get("duration"),
                "failures": failures,
            })
            return
        next_path = path if kind in ("Test Plan", "Unit test bundle", "UI test bundle") else (f"{path}/{name}" if path and name else name)
        for child in node.get("children", []):
            walk_test_cases(child, next_path, out)
        for child in node.get("testNodes", []):
            walk_test_cases(child, next_path, out)
    elif isinstance(node, list):
        for child in node:
            walk_test_cases(child, path, out)


def summary(xcresult: Path, title: str) -> None:
    lines = [f"### {title}", ""]
    if not xcresult.exists():
        lines.append(f"Результат `{xcresult.name}` не найден: тесты не запускались.")
        print("\n".join(lines))
        return

    try:
        data = run_json(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(xcresult)])
        lines.append(
            f"Итог: **{data.get('result', '?')}** · всего {data.get('totalTestCount', '?')} · "
            f"пройдено {data.get('passedTests', '?')} · упало {data.get('failedTests', '?')} · "
            f"пропущено {data.get('skippedTests', '?')}"
        )
        for failure in data.get("testFailures", []) or []:
            lines.append(f"- ❌ `{failure.get('testName', '?')}`: {failure.get('failureText', '')}")
        lines.append("")
    except Exception as exc:  # noqa: BLE001
        lines.append(f"Сводку получить не удалось: {exc}")
        lines.append("")

    try:
        tests = run_json(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(xcresult)])
        cases = []
        walk_test_cases(tests, "", cases)
        if cases:
            lines.append("| Тест | Результат | Время, с |")
            lines.append("|---|---|---|")
            for case in cases:
                icon = {"Passed": "✅", "Failed": "❌", "Skipped": "⏭"}.get(str(case["result"]), "•")
                duration = case["duration"]
                shown = f"{duration:.1f}" if isinstance(duration, (int, float)) else (str(duration) if duration else "")
                lines.append(f"| `{case['name']}` | {icon} {case['result']} | {shown} |")
                for failure in case["failures"]:
                    lines.append(f"| ↳ {failure} | | |")
            lines.append("")
    except Exception as exc:  # noqa: BLE001
        lines.append(f"Список тестов получить не удалось: {exc}")
        lines.append("")

    print("\n".join(lines))


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 0
    try:
        if sys.argv[1] == "attachments":
            rename_attachments(Path(sys.argv[2]))
        elif sys.argv[1] == "summary":
            summary(Path(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "Результаты тестов")
        else:
            print(__doc__)
    except Exception as exc:  # noqa: BLE001
        print(f"Ошибка разбора: {exc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
