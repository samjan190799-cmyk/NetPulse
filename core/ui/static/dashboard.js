/* NetPulse Web Dashboard.
 *
 * Без фреймворков. Все динамические данные (имена узлов, адреса, тексты алертов) выводятся только
 * через textContent / DOM API — никакого innerHTML, поэтому строка вроде «<img onerror=…>» в имени узла
 * остаётся просто текстом. Страница работает под строгой CSP (скрипты и стили только свои).
 */
(() => {
    'use strict';

    const STATS_POLL_MS = 1000;
    const ALERTS_POLL_MS = 5000;
    const SYSTEM_POLL_MS = 10000;
    const FETCH_TIMEOUT_MS = 5000;
    const SPEEDTEST_TIMEOUT_MS = 120000;
    const MAX_CHART_POINTS = 60;
    const HOST_COLORS = ['#2f81f7', '#3fb950', '#d29922', '#a371f7', '#f85149', '#39c5cf', '#db61a2', '#e3b341'];
    const DASH = '—';

    const $ = (id) => document.getElementById(id);

    function isNum(v) {
        return typeof v === 'number' && Number.isFinite(v);
    }

    function fmt(v, digits) {
        return isNum(v) ? v.toFixed(digits) : DASH;
    }

    function setText(id, text) {
        const node = $(id);
        if (node) node.textContent = text;
    }

    function cell(text, className) {
        const td = document.createElement('td');
        td.textContent = text;
        if (className) td.className = className;
        return td;
    }

    /* ---- сеть ---------------------------------------------------------------------------- */

    async function getJSON(url, options = {}, timeoutMs = FETCH_TIMEOUT_MS) {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), timeoutMs);
        try {
            const res = await fetch(url, { cache: 'no-store', ...options, signal: ctrl.signal });
            let data = null;
            try {
                data = await res.json();
            } catch (_) {
                /* пустое тело или не JSON — не ошибка транспорта */
            }
            return { ok: res.ok, status: res.status, data };
        } finally {
            clearTimeout(timer);
        }
    }

    let connected = null;

    function setConnected(ok) {
        if (ok === connected) return;
        connected = ok;
        const badge = $('conn-badge');
        badge.textContent = ok ? 'ONLINE' : 'НЕТ СВЯЗИ';
        badge.classList.toggle('offline', !ok);
    }

    /* Опрос цепочкой setTimeout: следующий запрос стартует только после завершения предыдущего,
       поэтому медленный ответ не приводит к лавине параллельных запросов. */
    function poll(fn, intervalMs) {
        const tick = async () => {
            try {
                await fn();
            } catch (e) {
                console.error(e);
            }
            setTimeout(tick, intervalMs);
        };
        tick();
    }

    /* ---- график -------------------------------------------------------------------------- */

    let chart = null;
    const datasetsByKey = new Map();

    function initChart() {
        const canvas = $('latencyChart');
        if (typeof Chart === 'undefined') {
            canvas.classList.add('hidden');
            $('chart-note').classList.remove('hidden');
            return;
        }
        chart = new Chart(canvas.getContext('2d'), {
            type: 'line',
            data: {
                labels: Array.from({ length: MAX_CHART_POINTS }, () => ''),
                datasets: [],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: false,
                spanGaps: false,
                interaction: { mode: 'nearest', axis: 'x', intersect: false },
                elements: {
                    line: { tension: 0.3, borderWidth: 2 },
                    point: { radius: 0, hitRadius: 8 },
                },
                scales: {
                    x: { grid: { display: false }, ticks: { display: false } },
                    y: {
                        beginAtZero: true,
                        grid: { color: 'rgba(255, 255, 255, 0.06)' },
                        ticks: { color: '#8b949e', font: { size: 11 } },
                    },
                },
                plugins: {
                    legend: {
                        position: 'top',
                        labels: { color: '#f0f6fc', boxWidth: 12, font: { size: 12 } },
                    },
                    tooltip: {
                        callbacks: {
                            label: (ctx) => `${ctx.dataset.label}: ${fmt(ctx.parsed.y, 1)} мс`,
                        },
                    },
                },
            },
        });
    }

    function updateChart(stats) {
        if (!chart) return;
        const present = new Set();

        stats.forEach((s) => {
            // Ключ включает адрес: при смене шлюза (роуминг) старый ряд исчезает, а не «замерзает»
            const key = `${s.name}|${s.address}`;
            present.add(key);

            let ds = datasetsByKey.get(key);
            if (!ds) {
                const color = HOST_COLORS[datasetsByKey.size % HOST_COLORS.length];
                ds = {
                    label: s.name,
                    data: Array(MAX_CHART_POINTS).fill(null),
                    borderColor: color,
                    backgroundColor: color,
                    fill: false,
                };
                datasetsByKey.set(key, ds);
                chart.data.datasets.push(ds);
            }
            // null (потеря) рисуется разрывом линии, а не нулём
            ds.data.push(isNum(s.last_latency_ms) ? s.last_latency_ms : null);
            if (ds.data.length > MAX_CHART_POINTS) ds.data.shift();
        });

        for (const [key, ds] of datasetsByKey) {
            if (!present.has(key)) {
                datasetsByKey.delete(key);
                const idx = chart.data.datasets.indexOf(ds);
                if (idx !== -1) chart.data.datasets.splice(idx, 1);
            }
        }
        chart.update('none');
    }

    /* ---- таблица узлов ------------------------------------------------------------------- */

    function statusClass(status) {
        switch (status) {
            case 'OK': return 'status-ok';
            case 'WARN': return 'status-warn';
            case 'CRIT':
            case 'DOWN': return 'status-crit';
            default: return 'status-unknown';
        }
    }

    function triple(a, b, c, digits) {
        if (!isNum(a)) return `${DASH} / ${DASH} / ${DASH}`;
        return `${fmt(a, digits)} / ${fmt(b, digits)} / ${fmt(c, digits)}`;
    }

    function renderHosts(stats) {
        const tbody = $('hosts-tbody');
        if (!stats.length) {
            const tr = document.createElement('tr');
            const td = cell('Нет узлов для мониторинга', 'empty');
            td.colSpan = 8;
            tr.appendChild(td);
            tbody.replaceChildren(tr);
            return;
        }

        const rows = stats.map((s) => {
            const tr = document.createElement('tr');

            const nameTd = document.createElement('td');
            const strong = document.createElement('strong');
            strong.textContent = s.name;
            nameTd.appendChild(strong);
            if (s.is_gateway) nameTd.appendChild(document.createTextNode(' ★'));
            tr.appendChild(nameTd);

            tr.appendChild(cell(s.address));

            const sent = s.sent_count || 0;
            const hasRtt = isNum(s.last_latency_ms);
            if (hasRtt) {
                tr.appendChild(cell(fmt(s.last_latency_ms, 1)));
            } else {
                tr.appendChild(cell(sent > 0 ? 'LOST' : DASH, sent > 0 ? 'rtt-lost' : ''));
            }

            tr.appendChild(cell(triple(s.min_latency_ms, s.avg_latency_ms, s.max_latency_ms, 0)));
            tr.appendChild(cell(triple(s.p50_latency_ms, s.p95_latency_ms, s.p99_latency_ms, 0)));
            tr.appendChild(cell(sent > 0 ? `${fmt(s.jitter_ms, 1)} мс` : DASH));
            tr.appendChild(cell(sent > 0 ? `${fmt(s.loss_window_pct, 1)}% / ${fmt(s.loss_rate_pct, 1)}%` : DASH));

            const statusTd = document.createElement('td');
            const pill = document.createElement('span');
            pill.className = `status-pill ${statusClass(s.status)}`;
            pill.textContent = s.status === 'UNKNOWN' ? 'INIT' : String(s.status);
            statusTd.appendChild(pill);
            tr.appendChild(statusTd);

            return tr;
        });
        tbody.replaceChildren(...rows);
    }

    function renderSummary(stats) {
        const live = stats.filter((s) => isNum(s.last_latency_ms));
        if (!live.length) {
            setText('res-ping', DASH);
            setText('res-jitter', DASH);
            return;
        }
        const avg = (key) => live.reduce((sum, s) => sum + (isNum(s[key]) ? s[key] : 0), 0) / live.length;
        setText('res-ping', `${fmt(avg('last_latency_ms'), 0)} мс`);
        setText('res-jitter', `${fmt(avg('jitter_ms'), 1)} мс`);
    }

    async function refreshStats() {
        let r;
        try {
            r = await getJSON('/api/stats');
        } catch (_) {
            setConnected(false);
            return;
        }
        if (!r.ok || !Array.isArray(r.data)) {
            setConnected(false);
            return;
        }
        setConnected(true);
        setText('updated-at', `Обновлено ${new Date().toLocaleTimeString()}`);
        renderHosts(r.data);
        renderSummary(r.data);
        updateChart(r.data);
    }

    /* ---- сведения о системе -------------------------------------------------------------- */

    async function refreshSystem() {
        const r = await getJSON('/api/system');
        if (!r.ok || !r.data) return;
        const d = r.data;
        setText('local-ip', d.local_ip || DASH);
        setText('gateway-ip', d.gateway_ip || DASH);
        setText('public-ip', d.public_ip ? (d.isp_name ? `${d.public_ip} · ${d.isp_name}` : d.public_ip) : DASH);
        setText('iface-name', d.interface_name && d.interface_name !== 'unknown' ? d.interface_name : DASH);
    }

    /* ---- события ------------------------------------------------------------------------- */

    async function refreshAlerts() {
        const r = await getJSON('/api/alerts');
        if (!r.ok || !Array.isArray(r.data)) return;
        const list = $('alerts-list');

        if (!r.data.length) {
            const li = document.createElement('li');
            li.className = 'alerts-empty';
            li.textContent = 'Событий пока нет';
            list.replaceChildren(li);
            return;
        }

        // API отдаёт от старых к новым — показываем новые сверху
        const items = r.data.slice().reverse().map((a) => {
            const li = document.createElement('li');
            li.className = 'alert-item';

            const time = document.createElement('span');
            time.className = 'alert-time';
            time.textContent = typeof a.timestamp === 'string' ? a.timestamp.slice(11, 19) : '';

            const sev = document.createElement('span');
            const level = ['info', 'warning', 'critical'].includes(a.severity) ? a.severity : 'info';
            sev.className = `alert-sev sev-${level}`;
            sev.textContent = level;

            const msg = document.createElement('span');
            msg.className = 'alert-msg';
            const host = document.createElement('strong');
            host.textContent = a.target_name || a.host || '';
            msg.append(host, document.createTextNode(` — ${a.message || ''}`));

            li.append(time, sev, msg);
            return li;
        });
        list.replaceChildren(...items);
    }

    /* ---- тест скорости ------------------------------------------------------------------- */

    let speedtestRunning = false;

    function setSpeedStatus(text, kind) {
        const label = $('speed-status-label');
        label.textContent = text;
        label.classList.toggle('error', kind === 'error');
        label.classList.toggle('warn', kind === 'warn');
    }

    async function runSpeedtest() {
        if (speedtestRunning) return;
        speedtestRunning = true;

        const btn = $('btn-run-speedtest');
        btn.disabled = true;
        btn.textContent = 'Выполняется замер…';
        setSpeedStatus('Замер пропускной способности…');
        setText('live-speed-val', '…');

        try {
            const r = await getJSON('/api/speedtest', { method: 'POST' }, SPEEDTEST_TIMEOUT_MS);

            if (r.status === 409) {
                setText('live-speed-val', DASH);
                setSpeedStatus('Замер уже выполняется (запущен из консоли или другой вкладки)', 'warn');
            } else if (!r.ok || !r.data) {
                setText('live-speed-val', DASH);
                const detail = r.data && typeof r.data.detail === 'string' ? `: ${r.data.detail}` : '';
                setSpeedStatus(`Ошибка замера (HTTP ${r.status})${detail}`, 'error');
            } else if (r.data.status === 'FAILED') {
                setText('live-speed-val', DASH);
                setText('res-download', DASH);
                setText('res-upload', DASH);
                setSpeedStatus('Замер не удался: нет связи с серверами скорости', 'error');
            } else {
                const d = r.data;
                setText('live-speed-val', fmt(d.download_mbps, 1));
                setText('res-download', `${fmt(d.download_mbps, 1)} Мбит/с`);
                if (d.status === 'PARTIAL') {
                    setText('res-upload', DASH);
                    setSpeedStatus('Скачивание измерено, отдачу измерить не удалось', 'warn');
                } else {
                    setText('res-upload', `${fmt(d.upload_mbps, 1)} Мбит/с`);
                    setSpeedStatus(`Завершено за ${fmt(d.duration_s, 1)} с`);
                }
                if (d.server) setText('speed-server-name', `Сервер: ${d.server}`);
            }
        } catch (e) {
            setText('live-speed-val', DASH);
            setSpeedStatus(
                e && e.name === 'AbortError' ? 'Превышено время ожидания замера' : 'Нет связи с NetPulse',
                'error',
            );
        } finally {
            speedtestRunning = false;
            btn.disabled = false;
            btn.textContent = 'Начать тест скорости';
        }
    }

    /* ---- запуск -------------------------------------------------------------------------- */

    function init() {
        const logo = $('logo-img');
        if (logo) {
            const hide = () => logo.classList.add('hidden');
            logo.addEventListener('error', hide);
            if (logo.complete && logo.naturalWidth === 0) hide();   // ошибка могла произойти до подписки
        }

        $('btn-run-speedtest').addEventListener('click', runSpeedtest);

        initChart();
        poll(refreshStats, STATS_POLL_MS);
        poll(refreshSystem, SYSTEM_POLL_MS);
        poll(refreshAlerts, ALERTS_POLL_MS);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
