'use strict';
'require view';
'require rpc';
'require dom';
'require ui';

var callDiagnose = rpc.declare({ object: 'luci.trusttunnel', method: 'diagnose' });
var callPing = rpc.declare({
	object: 'luci.trusttunnel', method: 'ping', params: [ 'target' ]
});
var callProbe = rpc.declare({ object: 'luci.trusttunnel', method: 'probe' });
var callCheckDomain = rpc.declare({
	object: 'luci.trusttunnel', method: 'check_domain', params: [ 'domain' ]
});
var callSpeedStart = rpc.declare({ object: 'luci.trusttunnel', method: 'speedtest_start' });
var callSpeedStatus = rpc.declare({ object: 'luci.trusttunnel', method: 'speedtest_status' });
var callSpeedStop = rpc.declare({ object: 'luci.trusttunnel', method: 'speedtest_stop' });

// Слово вердикта вместо цветного кружка: на узком экране и в тёмной теме
// цвет читается хуже текста, а класс alert-message LuCI уже несёт и фон, и
// отступы — своего CSS не требуется, что важно для веса пакета.
var VERDICT_CLASS = { ok: 'success', warn: 'warning', fail: 'danger', skip: 'info' };

function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '30%' }, label),
		E('td', { 'class': 'td left' }, value)
	]);
}

function badge(ok, textOk, textBad) {
	return E('span', {
		'style': 'padding:2px 8px;border-radius:3px;color:#fff;background:' +
			(ok ? '#2e7d32' : '#c62828')
	}, ok ? textOk : textBad);
}

function verdictWord(v) {
	if (v === 'ok')   return _('everything checks out');
	if (v === 'warn') return _('works, with remarks');
	if (v === 'fail') return _('there are problems');
	return _('not checked');
}

// Статус одной проверки — короткое слово фиксированной ширины, чтобы список
// читался столбцом, а не рваным краем.
function checkMark(status) {
	var t = { ok: _('ok'), warn: _('check'), fail: _('problem'), skip: _('skipped') };
	var c = { ok: '#2e7d32', warn: '#ef6c00', fail: '#c62828', skip: '#757575' };
	return E('span', {
		'style': 'display:inline-block;min-width:6.5em;font-weight:bold;color:' + c[status]
	}, t[status] || status);
}

// Текст проверок приходит из бэкенда по-английски: бэкенд сообщает ФАКТЫ, а
// формулировки принадлежат интерфейсу. Здесь литеральные _() — не динамический
// вызов _(переменная): так строки гарантированно попадают в каталог и
// переводятся независимо от того, как тема разрешает перевод во время
// выполнения. Неизвестная строка проходит как есть — это детали вроде адресов
// и чисел, которые переводить нечего.
var DIAG_TEXT = {
	'Endpoint address': _('Endpoint address'),
	'Credentials': _('Credentials'),
	'TLS host name': _('TLS host name'),
	'Mode': _('Mode'),
	'Selected lists': _('Selected lists'),
	'TrustTunnel client': _('TrustTunnel client'),
	'dnsmasq nftset support': _('dnsmasq nftset support'),
	'tun device': _('tun device'),
	'Enabled': _('Enabled'),
	'Running': _('Running'),
	'Device': _('Device'),
	'Tunnel carrier': _('Tunnel carrier'),
	'MTU matches settings': _('MTU matches settings'),
	'Routing rule': _('Routing rule'),
	'Routing table': _('Routing table'),
	'nftables table': _('nftables table'),
	'Firewall zone': _('Firewall zone'),
	'Bypass set (IPv4)': _('Bypass set (IPv4)'),
	'Domains in lists': _('Domains in lists'),
	'Last update': _('Last update'),
	'dnsmasq config published': _('dnsmasq config published'),
	'Endpoint reachable': _('Endpoint reachable'),
	'Traffic goes through the tunnel': _('Traffic goes through the tunnel'),

	'Fill in the address on the Settings page, or import the server config.': _('Fill in the address on the Settings page, or import the server config.'),
	'Both the user name and the password are required.': _('Both the user name and the password are required.'),
	'Without it the TLS session uses the bare address, which many servers reject.': _('Without it the TLS session uses the bare address, which many servers reject.'),
	'In "bypass by list" mode nothing is routed until at least one list is selected.': _('In "bypass by list" mode nothing is routed until at least one list is selected.'),
	'Run install.sh — the package does not ship the client binary.': _('Run install.sh — the package does not ship the client binary.'),
	'Install dnsmasq-full, or switch to "everything through VPN" mode.': _('Install dnsmasq-full, or switch to "everything through VPN" mode.'),
	'Not needed in "everything through VPN" mode, but "bypass by list" would not work.': _('Not needed in "everything through VPN" mode, but "bypass by list" would not work.'),
	'Install kmod-tun.': _('Install kmod-tun.'),
	'Turn on Enable on the Settings page, then press Start.': _('Turn on Enable on the Settings page, then press Start.'),
	'Press Start and read the client log below.': _('Press Start and read the client log below.'),
	'Created by the service on start; check the log.': _('Created by the service on start; check the log.'),
	'The device is configured but the client has not established the tunnel. This is the client side, not the routing — read the client log.': _('The device is configured but the client has not established the tunnel. This is the client side, not the routing — read the client log.'),
	'Restart the service so the configured value is applied.': _('Restart the service so the configured value is applied.'),
	'Run /etc/init.d/firewall reload — traffic into the tunnel is dropped without the zone.': _('Run /etc/init.d/firewall reload — traffic into the tunnel is dropped without the zone.'),
	'Press Update lists on the Lists page.': _('Press Update lists on the Lists page.'),
	'Without it dnsmasq never fills the nftables set.': _('Without it dnsmasq never fills the nftables set.'),
	'Check the address, and that the router itself has internet access.': _('Check the address, and that the router itself has internet access.'),
	'The tunnel is up but traffic is not using it.': _('The tunnel is up but traffic is not using it.'),
	'A request bound to the device can fail even on a healthy tunnel, because the default route lives in the marked table. Judge by a LAN client instead.': _('A request bound to the device can fail even on a healthy tunnel, because the default route lives in the marked table. Judge by a LAN client instead.'),

	'not set': _('not set'),
	'supported': _('supported'),
	'missing': _('missing'),
	'not installed': _('not installed'),
	'yes': _('yes'),
	'no': _('no'),
	'present': _('present'),
	'absent': _('absent'),
	'never': _('never'),
	'up': _('up'),
	'no carrier': _('no carrier'),
	'table absent': _('table absent'),
	'everything through VPN': _('Everything through VPN'),
	'bypass by list': _('Bypass by list'),
	'/dev/net/tun present': _('present'),

	'empty for now': _('empty for now'),
	'empty and cannot fill': _('empty and cannot fill'),
	'The set is rebuilt on every service start and fills as devices resolve domains from the lists. Nothing has asked yet, which is normal right after a restart.': _('The set is rebuilt on every service start and fills as devices resolve domains from the lists. Nothing has asked yet, which is normal right after a restart.'),
	'Either this dnsmasq lacks nftset support or the generated config is not published in its conf-dir. See the checks above.': _('Either this dnsmasq lacks nftset support or the generated config is not published in its conf-dir. See the checks above.'),
	'The nftables table is gone; restart the service.': _('The nftables table is gone; restart the service.'),
	'Encrypted DNS': _('Encrypted DNS'),
	'Stock https-dns-proxy service': _('Stock https-dns-proxy service'),
	'enabled, but it has not written its resolver into the dnsmasq config': _('enabled, but it has not written its resolver into the dnsmasq config'),
	'dnsmasq has noresolv, so these are its only upstreams and the whole network is left without working DNS. Fix the failing instance in the https-dns-proxy config (check its resolver_url) or delete that instance, then restart the service. Do not just disable the service: with nothing put in its place dnsmasq falls back to the provider resolver, which may hand back spoofed addresses.': _('dnsmasq has noresolv, so these are its only upstreams and the whole network is left without working DNS. Fix the failing instance in the https-dns-proxy config (check its resolver_url) or delete that instance, then restart the service. Do not just disable the service: with nothing put in its place dnsmasq falls back to the provider resolver, which may hand back spoofed addresses.'),
	'Start it with /etc/init.d/https-dns-proxy start, otherwise everything outside the selected lists keeps going to the provider resolver.': _('Start it with /etc/init.d/https-dns-proxy start, otherwise everything outside the selected lists keeps going to the provider resolver.'),
	'DNS outside the lists': _('DNS outside the lists'),
	'resolved by the provider': _('resolved by the provider'),
	'dnsmasq has no encrypted upstream of its own, so every domain that is not in a selected list goes to the resolver handed out by the provider, which may return spoofed addresses. Install https-dns-proxy and start its service, or point dnsmasq at an encrypted resolver yourself.': _('dnsmasq has no encrypted upstream of its own, so every domain that is not in a selected list goes to the resolver handed out by the provider, which may return spoofed addresses. Install https-dns-proxy and start its service, or point dnsmasq at an encrypted resolver yourself.'),
	'no resolver URL set': _('no resolver URL set'),
	'https-dns-proxy is not installed': _('https-dns-proxy is not installed'),
	'configured, but dnsmasq is not pointed at the proxy': _('configured, but dnsmasq is not pointed at the proxy'),
	'Fill in the DoH resolver URL on the Network tab, or switch the mode back.': _('Fill in the DoH resolver URL on the Network tab, or switch the mode back.'),
	'Install it: apk add https-dns-proxy. Until then the list domains are resolved by the provider, unencrypted.': _('Install it: apk add https-dns-proxy. Until then the list domains are resolved by the provider, unencrypted.'),
	'Restart the service so the generated dnsmasq config catches up.': _('Restart the service so the generated dnsmasq config catches up.'),

	// Строки режима «резолвер для всей сети». Значения с числами и адресами
	// внутрь карты не попадают: они собираются склейкой в бэкенде, как и
	// соседние «no answer from …», и переводу поштучно не подлежат.
	'Encrypted DNS for the whole network': _('Encrypted DNS for the whole network'),
	'configured, but the service has not applied it': _('configured, but the service has not applied it'),
	'Restart the service so it switches https-dns-proxy over.': _('Restart the service so it switches https-dns-proxy over.'),
	'Install it: apk add https-dns-proxy. Until then the network keeps its current resolver.': _('Install it: apk add https-dns-proxy. Until then the network keeps its current resolver.'),
	'dnsmasq spreads queries across all of them, so part of the traffic still goes to another resolver. Restart the service.': _('dnsmasq spreads queries across all of them, so part of the traffic still goes to another resolver. Restart the service.'),
	'dnsmasq has noresolv, so these are its only upstreams and the whole network is left without working DNS. This service put your own resolver there, so fix the DoH resolver URL in Settings — editing the https-dns-proxy config would be overwritten on the next start. Turning the "whole network" checkbox off hands the network back to its previous resolver.': _('dnsmasq has noresolv, so these are its only upstreams and the whole network is left without working DNS. This service put your own resolver there, so fix the DoH resolver URL in Settings — editing the https-dns-proxy config would be overwritten on the next start. Turning the "whole network" checkbox off hands the network back to its previous resolver.')
};

function dtr(s) {
	return (s && DIAG_TEXT[s]) ? DIAG_TEXT[s] : (s || '');
}

// --- Тест скорости -------------------------------------------------------------
//
// Шкала спидометра неравномерная, как у speedtest.net: на равномерной шкале
// до гигабита типичные для домашней сети десятки мегабит слиплись бы у левого
// края. Деления стоят на равных расстояниях друг от друга, а значение между
// ними интерполируется линейно.
var SPEED_TICKS = [ 0, 10, 50, 100, 250, 500, 1000 ];
var GAUGE_ARC = Math.PI * 120;   // длина дуги радиуса 120
var SVG_NS = 'http://www.w3.org/2000/svg';

function gaugeFrac(v) {
	var last = SPEED_TICKS.length - 1;
	if (!(v > 0)) return 0;
	if (v >= SPEED_TICKS[last]) return 1;
	for (var i = 1; i <= last; i++) {
		if (v <= SPEED_TICKS[i]) {
			var a = SPEED_TICKS[i - 1], b = SPEED_TICKS[i];
			return (i - 1 + (v - a) / (b - a)) / last;
		}
	}
	return 1;
}

function svgEl(name, attrs, text) {
	var n = document.createElementNS(SVG_NS, name);
	Object.keys(attrs || {}).forEach(function(k) { n.setAttribute(k, attrs[k]); });
	if (text != null) n.textContent = text;
	return n;
}

// Дуга-спидометр с большим числом посередине. Поля по бокам в viewBox нужны
// подписи последнего деления: «1000» вплотную к краю обрезается. Возвращает узел и set(значение,
// цвет) — единственный способ его менять.
function makeGauge() {
	var svg = svgEl('svg', {
		'viewBox': '-20 0 340 190', 'width': '100%',
		'style': 'max-width:340px;display:block;margin:0 auto'
	});
	var d = 'M 30 150 A 120 120 0 0 1 270 150';
	svg.appendChild(svgEl('path', {
		'd': d, 'fill': 'none', 'stroke': 'currentColor', 'stroke-opacity': '0.15',
		'stroke-width': '14', 'stroke-linecap': 'round'
	}));
	var fill = svgEl('path', {
		'd': d, 'fill': 'none', 'stroke': '#1565c0', 'stroke-width': '14',
		'stroke-linecap': 'round', 'stroke-dasharray': '0 ' + GAUGE_ARC,
		'style': 'transition:stroke-dasharray .4s linear'
	});
	svg.appendChild(fill);

	SPEED_TICKS.forEach(function(t, i) {
		var ang = Math.PI - (i / (SPEED_TICKS.length - 1)) * Math.PI;
		svg.appendChild(svgEl('text', {
			'x': 150 + 138 * Math.cos(ang), 'y': 150 - 138 * Math.sin(ang) + 4,
			'text-anchor': i === 0 ? 'end' : (i === SPEED_TICKS.length - 1 ? 'start' : 'middle'),
			'font-size': '11', 'fill': 'currentColor', 'fill-opacity': '0.6'
		}, String(t)));
	});

	var value = svgEl('text', {
		'x': 150, 'y': 138, 'text-anchor': 'middle', 'font-size': '40',
		'font-weight': 'bold', 'fill': 'currentColor'
	}, '—');
	svg.appendChild(value);
	svg.appendChild(svgEl('text', {
		'x': 150, 'y': 162, 'text-anchor': 'middle', 'font-size': '13',
		'fill': 'currentColor', 'fill-opacity': '0.6'
	}, _('Mbit/s')));

	return {
		node: svg,
		set: function(v, color) {
			var shown = v > 0;
			value.textContent = shown ? (v < 100 ? v.toFixed(1) : String(Math.round(v))) : '—';
			fill.setAttribute('stroke', color || '#1565c0');
			// Нулевая заливка с круглым краем рисуется точкой и выглядит как
			// значение, которого нет.
			fill.setAttribute('stroke-opacity', shown ? '1' : '0');
			fill.setAttribute('stroke-dasharray',
				(shown ? gaugeFrac(v) * GAUGE_ARC : 0) + ' ' + GAUGE_ARC);
		}
	};
}

// Число или прочерк. Скорость 0 означает, что замер не удался: настоящий
// нуль на живой сети невозможен. А jitter 0.0 — честное значение.
function speedNum(v, digits, zeroIsMissing) {
	if (v == null || (zeroIsMissing && !(v > 0))) return '—';
	return v.toFixed(digits);
}

// Отношение туннеля к прямому каналу в процентах или null, если одной из
// цифр нет.
function speedRatio(res, key) {
	var t = res.tunnel[key], d = res.direct[key];
	if (!(t > 0) || !(d > 0)) return null;
	return Math.round(t / d * 100);
}

// Вердикт по худшему из двух отношений. Пороги 70% и 40% — оценка: туннель
// всегда что-то съедает на шифровании и обёртке, и 70–100% от прямого канала
// это ожидаемая норма, а ниже 40% канал до сервера уже узкое место.
function speedVerdict(res) {
	var r = [ speedRatio(res, 'down'), speedRatio(res, 'up') ].filter(function(x) {
		return x != null;
	});
	if (!r.length) return null;
	var worst = Math.min.apply(null, r);
	return {
		ratio: worst,
		level: worst >= 70 ? 'success' : (worst >= 40 ? 'warning' : 'danger'),
		text: worst >= 70 ? _('The tunnel is not the bottleneck.')
			: (worst >= 40 ? _('The tunnel is noticeably slower than the direct connection.')
				: _('The tunnel is the bottleneck: it passes less than 40% of the direct speed.'))
	};
}

var GROUP_TITLE = {
	config:  _('Configuration'),
	prereq:  _('Prerequisites'),
	service: _('Service'),
	kernel:  _('Kernel state'),
	lists:   _('Lists'),
	network: _('Network')
};

return view.extend({
	// Страница не имеет формы и ничего не сохраняет, поэтому кнопки
	// «Сохранить»/«Применить» LuCI здесь лишние.
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	// Список из 23 проверок с подсказками — это около 35 строк. Показывать их
	// все и всегда неправильно по двум причинам. Когда всё в порядке, читать
	// нечего: ответ «работает» умещается в одну строку. Когда есть проблема,
	// её надо найти, а она тонет среди зелёных строк.
	//
	// Поэтому: проблемы и замечания идут сверху, остальное — за кнопкой.
	// Двумя колонками эту длину сокращать нельзя: задача читателя — найти
	// ПЕРВУЮ проблему сверху вниз, а в двух колонках «первая» перестаёт быть
	// однозначной.
	renderChecks: function(list) {
		var order = [ 'config', 'prereq', 'service', 'kernel', 'lists', 'network' ];
		var byGroup = {};
		list.forEach(function(c) {
			if (!byGroup[c.group]) byGroup[c.group] = [];
			byGroup[c.group].push(c);
		});

		var parts = [];
		order.forEach(function(g) {
			if (!byGroup[g]) return;
			var rows = [];
			byGroup[g].forEach(function(c) {
				rows.push(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '20%' }, checkMark(c.status)),
					E('td', { 'class': 'td left', 'width': '33%' }, dtr(c.label)),
					E('td', { 'class': 'td left' }, dtr(c.detail))
				]));
				// Подсказка показывается только там, где есть что исправлять,
				// и отдельной строкой во всю ширину: рядом со значением она
				// съедала бы место у самого значения на узком экране.
				if (c.hint)
					rows.push(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td left' }, ''),
						E('td', { 'class': 'td left', 'colspan': '2' },
							E('em', {}, dtr(c.hint)))
					]));
			});
			parts.push(E('h4', { 'style': 'margin:1em 0 0.3em' }, GROUP_TITLE[g] || g));
			parts.push(E('table', { 'class': 'table' }, rows));
		});
		return parts;
	},

	renderDiagnose: function(res) {
		var counts = res.counts || {};
		var checks = res.checks || [];
		var problems = checks.filter(function(c) {
			return c.status === 'fail' || c.status === 'warn';
		});
		var passed = checks.filter(function(c) {
			return c.status !== 'fail' && c.status !== 'warn';
		});

		var parts = [
			E('div', {
				'class': 'alert-message ' + (VERDICT_CLASS[res.verdict] || 'info')
			}, [
				E('strong', {}, verdictWord(res.verdict)),
				E('br'),
				_('checks passed: %d, remarks: %d, problems: %d, skipped: %d')
					.format(counts.ok || 0, counts.warn || 0, counts.fail || 0, counts.skip || 0)
			])
		];

		if (problems.length)
			parts.push.apply(parts, this.renderChecks(problems));

		if (!passed.length)
			return parts;

		var restBox = E('div', { 'style': 'display:none' }, this.renderChecks(passed));
		var labelShow = problems.length
			? _('Show the checks that passed')
			: _('Show all checks');
		var btn = E('button', { 'class': 'cbi-button' }, labelShow);
		btn.addEventListener('click', function(ev) {
			ev.preventDefault();
			var hidden = restBox.style.display === 'none';
			restBox.style.display = hidden ? '' : 'none';
			btn.textContent = hidden ? _('Hide') : labelShow;
		});

		parts.push(E('div', { 'style': 'margin-top:1em' }, btn), restBox);
		return parts;
	},

	handleDiagnose: function(container) {
		dom.content(container, E('p', { 'class': 'spinning' },
			_('Running checks — this takes a few seconds…')));
		return callDiagnose().then(function(res) {
			dom.content(container, this.renderDiagnose(res));
		}.bind(this)).catch(function(e) {
			// catch обязателен: без него отклонённый вызов — таймаут ubus,
			// отказ в правах, перегруженный роутер — оставил бы страницу с
			// надписью «идёт проверка…» навсегда. Застрявший индикатор хуже
			// сообщения об ошибке: он выглядит как работающая проверка,
			// которая никогда не завершится.
			dom.content(container, E('div', { 'class': 'alert-message danger' },
				e.message || String(e)));
		});
	},

	handlePing: function(container) {
		dom.content(container, E('p', { 'class': 'spinning' }, _('Pinging…')));
		return callPing('').then(function(res) {
			if (res.error)
				return dom.content(container, E('p', {}, res.error));
			var rows = (res.results || []).map(function(r) {
				return E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left' }, r.host),
					E('td', { 'class': 'td left' }, r.loss + '%'),
					E('td', { 'class': 'td left' }, r.avg !== null
						? (r.min + ' / ' + r.avg + ' / ' + r.max + ' ms') : '—')
				]);
			});
			dom.content(container, E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th left' }, _('Host')),
					E('th', { 'class': 'th left' }, _('Loss')),
					E('th', { 'class': 'th left' }, _('min / avg / max'))
				])
			].concat(rows)));
		}).catch(function(e) {
			// Без этого при отклонённом вызове — таймаут ubus, отказ в
			// правах, перегруженный роутер — панель навсегда остаётся с
			// надписью «Пингую…». На странице диагностики застрявший
			// индикатор хуже отсутствующей функции: он выглядит как
			// работающая проверка, которая никогда не завершится.
			dom.content(container, E('p', {}, e.message || String(e)));
		});
	},

	handleProbe: function(container) {
		dom.content(container, E('p', { 'class': 'spinning' }, _('Checking…')));
		return callProbe().then(function(res) {
			dom.content(container, E('table', { 'class': 'table' }, [
				row(_('Through the tunnel'), res.tunnel.ip
					? E('code', {}, res.tunnel.ip)
					: E('span', { 'style': 'color:#c62828' }, res.tunnel.error)),
				row(_('Directly'), res.direct.ip
					? E('code', {}, res.direct.ip)
					: E('span', { 'style': 'color:#c62828' }, res.direct.error))
			]));
		}).catch(function(e) {
			dom.content(container, E('p', {}, e.message || String(e)));
		});
	},

	// Таблица итогов: напрямую и через туннель рядом, с процентом там, где
	// есть что сравнивать.
	renderSpeedResults: function(s) {
		var d = s.results.direct, t = s.results.tunnel;
		var hasAny = Object.keys(d).length || Object.keys(t).length;
		if (!hasAny) return [];

		function cells(key, digits, zeroMissing, unit) {
			return [
				E('td', { 'class': 'td left' }, speedNum(d[key], digits, zeroMissing)),
				E('td', { 'class': 'td left' }, s.tunnel_skipped ? '—'
					: speedNum(t[key], digits, zeroMissing)),
				E('td', { 'class': 'td left' }, unit)
			];
		}
		function line(label, key, digits, zeroMissing, unit, ratio) {
			var r = ratio ? speedRatio(s.results, key) : null;
			var c = cells(key, digits, zeroMissing, unit);
			c.push(E('td', { 'class': 'td left' }, r != null ? r + '%' : ''));
			return E('tr', { 'class': 'tr' }, [ E('td', { 'class': 'td left' }, label) ].concat(c));
		}

		var parts = [ E('table', { 'class': 'table', 'style': 'margin-top:1em' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th left' }, ''),
				E('th', { 'class': 'th left' }, _('Directly')),
				E('th', { 'class': 'th left' }, _('Through the tunnel')),
				E('th', { 'class': 'th left' }, ''),
				E('th', { 'class': 'th left' }, _('Tunnel / direct'))
			]),
			line(_('Ping'), 'ping', 1, true, _('ms'), false),
			line(_('Jitter'), 'jitter', 1, false, _('ms'), false),
			line(_('Download'), 'down', 1, true, _('Mbit/s'), true),
			line(_('Upload'), 'up', 1, true, _('Mbit/s'), true)
		]) ];

		if (s.tunnel_skipped)
			parts.push(E('p', {}, _('The tunnel is not running, so only the direct speed was measured.')));

		var v = s.tunnel_skipped ? null : speedVerdict(s.results);
		if (v && !s.running)
			parts.push(E('div', { 'class': 'alert-message ' + v.level }, [
				E('strong', {}, _('The tunnel passes %d%% of the direct speed.').format(v.ratio)),
				E('br'), v.text
			]));
		return parts;
	},

	// Один опрос. Пока замер идёт, вызывает сам себя через полсекунды; когда
	// страница ушла из документа (переход на другую вкладку LuCI), останавливает
	// замер: он тратит трафик и канал, а смотреть на него уже некому.
	pollSpeedtest: function(ctx, initial) {
		var self = this;
		// Первый вызов идёт до того, как LuCI вставит страницу в документ, и
		// проверка «ушли со страницы» его ошибочно остановила бы.
		if (!initial && !document.body.contains(ctx.root)) {
			callSpeedStop();
			return;
		}
		return callSpeedStatus().then(function(s) {
			var phaseName = { ping: _('Ping'), download: _('Download'), upload: _('Upload') };
			var color = s.phase === 'upload' ? '#2e7d32' : '#1565c0';

			ctx.gauge.set(s.phase === 'download' || s.phase === 'upload' ? s.live : 0, color);
			if (s.running) {
				var via = s.via === 'tunnel' ? _('Through the tunnel') : _('Directly');
				ctx.status.textContent = (phaseName[s.phase] || _('Starting…')) + ' · ' + via;
			} else if (s.error) {
				ctx.status.textContent = s.error === 'interrupted'
					? _('The test was interrupted.') : s.error;
			} else if (s.phase === 'stopped') {
				ctx.status.textContent = _('Stopped.');
			} else if (s.phase === 'done') {
				ctx.status.textContent = _('Done.');
			} else {
				ctx.status.textContent = '';
			}

			dom.content(ctx.results, self.renderSpeedResults(s));
			ctx.start.disabled = s.running;
			ctx.stop.style.display = s.running ? '' : 'none';

			if (s.running)
				setTimeout(function() { self.pollSpeedtest(ctx); }, 500);
		}).catch(function(e) {
			// Тот же довод, что у остальных обработчиков страницы: без catch
			// обрыв опроса оставил бы стрелку и «идёт замер» навсегда.
			ctx.status.textContent = e.message || String(e);
			ctx.start.disabled = false;
			ctx.stop.style.display = 'none';
		});
	},

	handleSpeedStart: function(ctx) {
		var self = this;
		ctx.start.disabled = true;
		ctx.status.textContent = _('Starting…');
		dom.content(ctx.results, []);
		return callSpeedStart().then(function(res) {
			if (res.error) {
				ctx.status.textContent = res.error;
				ctx.start.disabled = false;
				return;
			}
			ctx.stop.style.display = '';
			return self.pollSpeedtest(ctx);
		}).catch(function(e) {
			ctx.status.textContent = e.message || String(e);
			ctx.start.disabled = false;
		});
	},

	handleSpeedStop: function(ctx) {
		return callSpeedStop();
	},

	handleCheckDomain: function(input, container) {
		var d = input.value.trim();
		if (!d) return;
		dom.content(container, E('p', { 'class': 'spinning' }, _('Checking…')));
		return callCheckDomain(d).then(function(res) {
			if (res.error)
				return dom.content(container, E('p', {}, res.error));
			var tunnel = (res.verdict.indexOf('tunnel') === 0);
			dom.content(container, E('table', { 'class': 'table' }, [
				row(_('Normalized'), E('code', {}, res.normalized)),
				row(_('Verdict'), badge(tunnel, _('through the tunnel'), _('direct'))),
				row(_('Why'), res.reason),
				row(_('Found in lists'), (res.in_lists || []).join(', ') || _('nowhere')),
				row(_('Resolves to'), (res.addresses || []).join(', ') || '—'),
				// Второй ответ показывается рядом: расхождение означает, что
				// провайдер подменяет DNS, и это главная причина, по которой
				// запросы по обходным доменам вообще уводятся в туннель.
				row(_('Via the list resolver'),
					(res.addresses_via_resolver || []).join(', ') || '—'),
				row(_('In bypass set'), badge(res.in_set, _('yes'), _('no')))
			]));
		}).catch(function(e) {
			dom.content(container, E('p', {}, e.message || String(e)));
		});
	},



	render: function() {
		var self = this;
		var diagBox = E('div', { 'style': 'margin-top:1em' },
			E('p', { 'class': 'spinning' }, _('Running checks — this takes a few seconds…')));
		var pingBox = E('div', {});
		var probeBox = E('div', {});
		var domainBox = E('div', {});

		var speed = {
			gauge: makeGauge(),
			status: E('p', { 'style': 'text-align:center;min-height:1.5em;margin:.3em 0' }, ''),
			results: E('div', {}),
			start: E('button', { 'class': 'cbi-button cbi-button-action' }, _('Start the test')),
			stop: E('button', {
				'class': 'cbi-button cbi-button-negative', 'style': 'display:none'
			}, _('Stop'))
		};
		speed.root = E('div', {}, [
			speed.gauge.node, speed.status,
			E('div', { 'style': 'text-align:center' }, [ speed.start, ' ', speed.stop ]),
			speed.results
		]);
		speed.start.addEventListener('click', ui.createHandlerFn(this, 'handleSpeedStart', speed));
		speed.stop.addEventListener('click', ui.createHandlerFn(this, 'handleSpeedStop', speed));
		// Страницу могли обновить посреди замера или открыть после него:
		// подхватываем то, что уже идёт или лежит с прошлого раза.
		setTimeout(function() { self.pollSpeedtest(speed, true); }, 0);

		var domainInput = E('input', {
			'type': 'text', 'class': 'cbi-input-text',
			'placeholder': 'youtube.com', 'style': 'width:16em'
		});

		// Проверка запускается сразу при открытии: на эту вкладку заходят
		// именно за тем, чтобы увидеть состояние, и лишний щелчок ничего не
		// добавляет. Кнопка ниже — для повторного прогона после исправлений.
		this.handleDiagnose(diagBox);

		// Enter в поле домена делает то же, что кнопка: набрать домен и нажать
		// Enter — естественнее, чем тянуться мышью, а инструментом пользуются
		// подряд по нескольким доменам.
		domainInput.addEventListener('keydown', function(ev) {
			if (ev.key === 'Enter') {
				ev.preventDefault();
				self.handleCheckDomain(domainInput, domainBox);
			}
		});

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Diagnostics')),

			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, _('Checks the whole chain — configuration, prerequisites, service, kernel state, lists and network — and says what to do about anything it finds.')),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': function() { return self.handleDiagnose(diagBox); }
				}, _('Check again')),
				diagBox
			]),

			// Инструменты живут здесь, а не на странице состояния: это
			// действия по требованию, и нужны они тогда же, когда открывают
			// диагностику — когда что-то не работает. На странице состояния
			// они удлиняли страницу, которая должна отвечать одним взглядом.
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Check a domain')),
				E('p', {}, _('The tool to reach for when a particular site does not work: it says whether that domain goes through the tunnel, and why.')),
				E('div', {}, [
					domainInput, ' ',
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleCheckDomain', domainInput, domainBox)
					}, _('Check'))
				]),
				domainBox
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Ping the server')),
				E('p', {}, _('Loss and round-trip time for every configured address.')),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handlePing', pingBox)
				}, _('Ping')),
				pingBox
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Speed test')),
				E('p', {}, _('Measures ping, download and upload directly and through the tunnel, the way speedtest.net does, and compares the two. It takes about 40 seconds and moves as much data as your link carries in that time — around half a gigabyte on a fast connection — so avoid heavy use of the network meanwhile.')),
				E('p', { 'style': 'opacity:.7;font-size:90%' }, _('Ping is the response time of an HTTPS request, not ICMP: ICMP does not pass through the tunnel. The gauge follows the interface counters and also sees other traffic on the network; the final figures count the test traffic only.')),
				speed.root
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Compare the external address')),
				E('p', {}, _('Shows the address seen through the tunnel next to the one seen directly. The same address in both means traffic is not using the tunnel.')),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleProbe', probeBox)
				}, _('Compare')),
				probeBox
			])
		]);
	}
});
