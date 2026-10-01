"""Замер скорости: расчёт без учёта TTFB и честные статусы результата."""
import io

import engine.speedtest as speedtest_module
from engine.speedtest import AsyncSpeedtestEngine


class FakeResponse(io.RawIOBase):
    """Тело ответа из чанков; каждый read() «тратит» время по виртуальным часам."""

    def __init__(self, clock, first_byte_delay, chunk_delay, chunks, chunk_size):
        self.clock = clock
        self.first_byte_delay = first_byte_delay
        self.chunk_delay = chunk_delay
        self.remaining = chunks
        self.chunk_size = chunk_size
        self.started = False

    def read(self, _n=-1):
        if self.remaining <= 0:
            return b""                      # конец потока времени не тратит
        if not self.started:
            self.started = True
            self.clock.now += self.first_byte_delay
        else:
            self.clock.now += self.chunk_delay
        self.remaining -= 1
        return b"x" * self.chunk_size

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


def patch_download(monkeypatch, response_factory):
    clock = Clock()
    monkeypatch.setattr(speedtest_module.time, "perf_counter", clock)
    monkeypatch.setattr(speedtest_module.urllib.request, "urlopen", lambda req, timeout=None: response_factory(clock))
    return clock


def test_download_speed_excludes_time_to_first_byte(monkeypatch):
    """
    Регрессия: в скорость входили DNS, TLS и ожидание первого байта (здесь — 2 с «до первого байта»),
    из-за чего на быстрых каналах результат занижался в разы (старый расчёт дал бы 11 МБ / 3 с ≈ 29 Мбит/с).
    После первого чанка приходит 10 чанков по 1 МБ, по 0.1 с на каждый ⇒ ровно 80 Мбит/с.
    """
    patch_download(monkeypatch, lambda clock: FakeResponse(clock, first_byte_delay=2.0, chunk_delay=0.1,
                                                          chunks=11, chunk_size=1_000_000))
    assert AsyncSpeedtestEngine._sync_measure_download() == 80.0


def test_download_failure_returns_zero(monkeypatch):
    def refuse(req, timeout=None):
        raise OSError("blocked")

    monkeypatch.setattr(speedtest_module.urllib.request, "urlopen", refuse)
    assert AsyncSpeedtestEngine._sync_measure_download() == 0.0


def test_download_falls_back_to_second_url(monkeypatch):
    clock = Clock()
    monkeypatch.setattr(speedtest_module.time, "perf_counter", clock)
    urls = []

    def opener(req, timeout=None):
        urls.append(req.full_url)
        if len(urls) == 1:
            raise OSError("primary down")
        return FakeResponse(clock, 0.1, 0.1, 6, 100_000)

    monkeypatch.setattr(speedtest_module.urllib.request, "urlopen", opener)
    assert AsyncSpeedtestEngine._sync_measure_download() > 0
    assert len(urls) == 2 and urls[0] == AsyncSpeedtestEngine.CF_DOWNLOAD_URL


def patch_measurements(monkeypatch, download, upload):
    monkeypatch.setattr(AsyncSpeedtestEngine, "_sync_measure_download", classmethod(lambda cls, cb=None: download))
    monkeypatch.setattr(AsyncSpeedtestEngine, "_sync_measure_upload", classmethod(lambda cls, cb=None: upload))


async def test_status_success(monkeypatch):
    patch_measurements(monkeypatch, 94.2, 21.5)
    res = await AsyncSpeedtestEngine.run_full_speedtest()
    assert (res.status, res.download_mbps, res.upload_mbps) == ("SUCCESS", 94.2, 21.5)


async def test_status_partial_when_upload_failed(monkeypatch):
    """Регрессия: при провале отдачи результат всё равно помечался SUCCESS (с upload = 0)."""
    patch_measurements(monkeypatch, 94.2, 0.0)
    assert (await AsyncSpeedtestEngine.run_full_speedtest()).status == "PARTIAL"


async def test_status_failed_when_nothing_measured(monkeypatch):
    patch_measurements(monkeypatch, 0.0, 0.0)
    assert (await AsyncSpeedtestEngine.run_full_speedtest()).status == "FAILED"


async def test_progress_callback_receives_stage_names(monkeypatch):
    def download(cls, cb=None):
        cb(10.0)
        return 10.0

    def upload(cls, cb=None):
        cb(5.0)
        return 5.0

    monkeypatch.setattr(AsyncSpeedtestEngine, "_sync_measure_download", classmethod(download))
    monkeypatch.setattr(AsyncSpeedtestEngine, "_sync_measure_upload", classmethod(upload))
    stages = []
    await AsyncSpeedtestEngine.run_full_speedtest(progress_cb=lambda stage, mbps: stages.append((stage, mbps)))
    assert stages == [("download", 10.0), ("upload", 5.0)]
