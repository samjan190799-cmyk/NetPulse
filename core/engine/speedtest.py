"""
Асинхронный движок измерения пропускной способности сети (Bandwidth & Speedtest).
Работает на стандартной библиотеке Python (urllib в потоках + asyncio).
"""
import asyncio
import os
import time
import urllib.request
from datetime import datetime
from typing import Callable, Optional
from metrics.models import SpeedtestResult


class AsyncSpeedtestEngine:
    """Измеритель скорости загрузки (Download) и отдачи (Upload)."""

    CF_DOWNLOAD_URL = "https://speed.cloudflare.com/__down?bytes=10000000"  # 10 MB payload
    CF_UPLOAD_URL = "https://speed.cloudflare.com/__up"
    FALLBACK_DOWNLOAD_URL = "http://speedtest.tele2.net/10MB.zip"

    CHUNK = 64 * 1024

    @classmethod
    def _sync_measure_download(
        cls,
        progress_cb: Optional[Callable[[float], None]] = None
    ) -> float:
        """
        Синхронное скачивание порциями через urllib.

        Скорость считается по байтам, полученным ПОСЛЕ первого чанка, и по времени от
        первого чанка: DNS, TLS-рукопожатие и ожидание первого байта в замер не входят
        (иначе на быстрых каналах 10-МБ загрузка сильно занижала скорость).
        """
        urls = [cls.CF_DOWNLOAD_URL, cls.FALLBACK_DOWNLOAD_URL]

        for url in urls:
            try:
                req = urllib.request.Request(
                    url,
                    headers={"User-Agent": "NetPulse/1.0 Speedtest"}
                )
                t_request = time.perf_counter()
                total_all = 0
                total_after_first = 0
                t_first = None

                with urllib.request.urlopen(req, timeout=10.0) as response:
                    while True:
                        chunk = response.read(cls.CHUNK)
                        if not chunk:
                            break
                        total_all += len(chunk)
                        if t_first is None:
                            t_first = time.perf_counter()   # первый байт получен — начинаем отсчёт
                            continue
                        total_after_first += len(chunk)
                        elapsed = time.perf_counter() - t_first
                        if elapsed > 0.2 and progress_cb:
                            progress_cb(round((total_after_first * 8.0) / (elapsed * 1_000_000.0), 1))

                t_end = time.perf_counter()
                if t_first is not None and total_after_first > 0 and (t_end - t_first) > 0.05:
                    return round((total_after_first * 8.0) / ((t_end - t_first) * 1_000_000.0), 2)
                # Слишком мало данных для «чистого» замера — считаем по всему запросу
                total_time = t_end - t_request
                if total_all > 0 and total_time > 0:
                    return round((total_all * 8.0) / (total_time * 1_000_000.0), 2)
            except Exception:
                continue

        return 0.0

    @classmethod
    def _sync_measure_upload(
        cls,
        progress_cb: Optional[Callable[[float], None]] = None
    ) -> float:
        """Синхронная отправка данных на Cloudflare speedtest эндпоинт."""
        payload_size = 4 * 1024 * 1024  # 4 MB
        payload = os.urandom(payload_size)

        try:
            req = urllib.request.Request(
                cls.CF_UPLOAD_URL,
                data=payload,
                headers={"User-Agent": "NetPulse/1.0 Speedtest", "Content-Type": "application/octet-stream"},
                method="POST"
            )
            start_time = time.perf_counter()
            with urllib.request.urlopen(req, timeout=10.0):
                total_time = time.perf_counter() - start_time
            if total_time > 0:
                mbps = (payload_size * 8.0) / (total_time * 1_000_000.0)
                if progress_cb:
                    progress_cb(round(mbps, 1))
                return round(mbps, 2)
        except Exception:
            pass

        return 0.0

    @classmethod
    async def run_full_speedtest(
        cls,
        progress_cb: Optional[Callable[[str, float], None]] = None
    ) -> SpeedtestResult:
        """Полный цикл тестирования скорости."""
        now = datetime.now()
        start_full = time.perf_counter()

        def _dl_cb(mbps: float):
            if progress_cb:
                progress_cb("download", mbps)

        dl_mbps = await asyncio.to_thread(cls._sync_measure_download, _dl_cb)

        def _ul_cb(mbps: float):
            if progress_cb:
                progress_cb("upload", mbps)

        ul_mbps = await asyncio.to_thread(cls._sync_measure_upload, _ul_cb)

        duration = round(time.perf_counter() - start_full, 2)

        # Статус отражает, что реально удалось измерить: «SUCCESS» только если измерены обе стороны
        if dl_mbps > 0 and ul_mbps > 0:
            status = "SUCCESS"
        elif dl_mbps > 0:
            status = "PARTIAL"
        else:
            status = "FAILED"

        return SpeedtestResult(
            timestamp=now,
            download_mbps=dl_mbps,
            upload_mbps=ul_mbps,
            server_name="Cloudflare CDN Edge",
            duration_s=duration,
            status=status,
        )
