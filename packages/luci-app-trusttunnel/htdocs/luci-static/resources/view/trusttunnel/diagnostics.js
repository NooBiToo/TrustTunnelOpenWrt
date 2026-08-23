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
	'Restart the service so the generated dnsmasq config catches up.': _('Restart the service so the generated dnsmasq config catches up.')
};

function dtr(s) {
	return (s && DIAG_TEXT[s]) ? DIAG_TEXT[s] : (s || '');
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
