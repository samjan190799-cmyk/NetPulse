"""
Асинхронный движок измерения пропускной способности сети (Bandwidth & Speedtest).
Поддерживает стандартную библиотеку Python (urllib) и aiohttp.
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

    @classmethod
    def _sync_measure_download(
        cls,
        progress_cb: Optional[Callable[[float], None]] = None
    ) -> float:
        """Синхронное скачивание порциями через urllib."""
        urls = [cls.CF_DOWNLOAD_URL, cls.FALLBACK_DOWNLOAD_URL]
        
        for url in urls:
            try:
                req = urllib.request.Request(
                    url,
                    headers={"User-Agent": "NetPulse/1.0 Speedtest"}
                )
                start_time = time.perf_counter()
                total_bytes = 0
                
                with urllib.request.urlopen(req, timeout=10.0) as response:
                    while True:
                        chunk = response.read(64 * 1024)
                        if not chunk:
                            break
                        total_bytes += len(chunk)
                        elapsed = time.perf_counter() - start_time
                        if elapsed > 0.2 and progress_cb:
                            current_mbps = (total_bytes * 8.0) / (elapsed * 1_000_000.0)
                            progress_cb(round(current_mbps, 1))

                total_time = time.perf_counter() - start_time
                if total_time > 0 and total_bytes > 0:
                    mbps = (total_bytes * 8.0) / (total_time * 1_000_000.0)
                    return round(mbps, 2)
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
            with urllib.request.urlopen(req, timeout=10.0) as response:
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
        return SpeedtestResult(
            timestamp=now,
            download_mbps=dl_mbps,
            upload_mbps=ul_mbps,
            server_name="Cloudflare CDN Edge",
            duration_s=duration,
            status="SUCCESS" if dl_mbps > 0 else "FAILED",
        )
