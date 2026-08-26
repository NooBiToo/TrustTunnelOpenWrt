'use strict';
'require view';
'require poll';
'require rpc';
'require ui';
'require dom';

var callStatus = rpc.declare({ object: 'luci.trusttunnel', method: 'status' });
var callService = rpc.declare({
	object: 'luci.trusttunnel', method: 'service', params: [ 'action' ]
});
var callVersions = rpc.declare({
	object: 'luci.trusttunnel', method: 'versions', params: [ 'refresh' ]
});
var callLog = rpc.declare({
	object: 'luci.trusttunnel', method: 'log', params: [ 'lines' ]
});

// Эта страница отвечает на ОДИН вопрос: работает или нет. Раньше здесь была
// таблица из двенадцати строк — устройство, ip rule, таблица маршрутизации,
// nft-таблица, размер набора обхода, поддержка nftset в dnsmasq. Всё это
// названия внутренних механизмов, а не то, чем человек управляет и что
// узнаёт; судить по ним «работает ли туннель» приходилось самому, сверяя
// зелёные значки между собой.
//
// Теперь состояние сведено в одну фразу с конкретными числами, а разбор по
// звеньям с объяснениями живёт на вкладке «Диагностика» — там он к месту и
// здесь не дублируется.
function verdict(st) {
	var host = st.endpoint_hostname || (st.addresses || [])[0] || '';
	var ls = st.lists_summary || {};
	var full = st.mode === 'full';

	if (!st.client_installed)
		return { level: 'danger',
			head: _('The TrustTunnel client is not installed'),
			detail: _('Run install.sh: the package does not ship the client binary.') };

	// Проверяется РАНЬШЕ состояния службы: без поддержки nftset режим обхода
	// по списку не работает вовсе, сколько бы списков ни было выбрано, а
	// служба при этом выглядит работающей.
	if (!full && !st.dnsmasq_nftset)
		return { level: 'danger',
			head: _('This dnsmasq cannot fill the bypass set'),
			detail: _('Install dnsmasq-full, or switch to "everything through VPN" mode. Nothing is bypassed until then.') };

	if (!st.running)
		return st.enabled
			? { level: 'danger', head: _('The service is not running'),
			    detail: _('Press Start and read the client log below.') }
			: { level: 'info', head: _('The service is off'),
			    detail: _('Press Start to run it now, or turn on "Start on boot" in Settings.') };

	if (!st.device_up)
		return { level: 'warning',
			head: host ? _('Connecting to %s').format(host) : _('Connecting to the server'),
			detail: _('The client is running but the tunnel is not established yet. If this persists, the client log below says why.') };

	if (full)
		return { level: 'success',
			head: host ? _('All LAN traffic goes through %s').format(host)
			           : _('All LAN traffic goes through the tunnel'),
			detail: _('Domains from the "do not bypass" list are sent out directly.') };

	if (!st.set4 || st.set4 < 1)
		return { level: 'warning',
			head: _('The tunnel is up, but nothing is bypassed yet'),
			detail: _('Addresses appear once a device on your network looks up a domain from the selected lists.') };

	// Здесь БЫЛА фраза вида «11 адресов из 18 доменов идут через сервер», и
	// это была ошибка. Слово «из» связало две несвязанные величины: 18 — это
	// сколько домeнов в собранных списках, а 11 — сколько адресов НА ДАННЫЙ
	// МОМЕНТ попало в набор по факту запросов. Читалось как доля, будто семь
	// доменов чего-то не досчитались, и вместо ответа возникал вопрос.
	//
	// Числа остались, но каждое стоит в своей строке таблицы со своей
	// подписью, где видно, что это за величина. А успех сказан одним словом:
	// когда всё работает, подробности не нужны.
	return { level: 'success', head: _('Bypass is working'), detail: '' };
}

function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '30%' }, label),
		E('td', { 'class': 'td left' }, value)
	]);
}

function fmtAge(ts) {
	if (!ts) return _('never');
	var d = Math.floor(Date.now() / 1000) - ts;
	if (d < 60) return _('just now');
	if (d < 3600) return Math.floor(d / 60) + ' ' + _('min ago');
	if (d < 86400) return Math.floor(d / 3600) + ' ' + _('h ago');
	return Math.floor(d / 86400) + ' ' + _('days ago');
}

return view.extend({
	handleAction: function(action, ev) {
		ui.showModal(_('Please wait'), [ E('p', { 'class': 'spinning' }, _('Running…')) ]);
		return callService(action).then(function(res) {
			ui.hideModal();
			// not_running: собственный код возврата init-скрипта для `start`
			// недостоверен (см. действие service в luci.trusttunnel) — бэкенд
			// перепроверил через procd и ничего работающего не нашёл.
			if (res && res.not_running)
				ui.addNotification(null, E('p', {}, _('The service did not start. The client log below says why.')), 'warning');
			else if (res && res.code !== 0)
				ui.addNotification(null, E('pre', {}, res.output || _('Command failed')), 'warning');
			else
				ui.addNotification(null, E('p', {}, _('Done')), 'info');
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', {}, e.message || String(e)), 'danger');
		});
	},

	// Вердикт и факты отрисовываются ПОРОЗНЬ, потому что живут в разных местах
	// страницы: вердикт занимает всю ширину (это заголовок ответа), а факты
	// стоят в паре с версиями. Опрос обновляет оба блока из одного вызова.
	// Полоса-вердикт показывается ТОЛЬКО когда что-то не так. Тогда она и
	// нужна: там подсказка, что делать, и заметность оправдана. Когда всё
	// работает, полоса во всю ширину сообщала бы «всё хорошо» — то есть
	// занимала бы самое видное место страницы, не давая повода к действию.
	// В этом случае состояние стоит обычной строкой в таблице слева, первой
	// над режимом работы.
	renderVerdict: function(st) {
		var v = verdict(st);
		if (v.level === 'success')
			return E('div', {});
		return E('div', { 'class': 'alert-message ' + v.level },
			v.detail
				? [ E('strong', {}, v.head), E('br'), v.detail ]
				: [ E('strong', {}, v.head) ]);
	},

	renderFacts: function(st) {
		var ls = st.lists_summary || {};
		var v = verdict(st);
		var rows = [];

		// Состояние первой строкой и только при успехе: при отказе о нём
		// говорит полоса выше, и дублировать её здесь незачем.
		if (v.level === 'success')
			rows.push(row(_('State'),
				E('span', { 'style': 'color:#2e7d32;font-weight:bold' }, _('working'))));

		rows.push(row(_('Mode'), st.mode === 'full'
			? _('Everything through VPN') : _('Bypass by list')));

		if (st.endpoint_hostname)
			rows.push(row(_('Server'), E('code', {}, st.endpoint_hostname)));

		// Списки и набор показываются только там, где они участвуют: в режиме
		// «всё через VPN» это были бы цифры, ни на что не влияющие.
		if (st.mode !== 'full') {
			// Домены и подсети — это РАЗМЕР СОБРАННЫХ СПИСКОВ, то есть сколько
			// записей вообще подлежит обходу.
			rows.push(row(_('In the lists'),
				_('%d domains').format(ls.domains || 0) +
				((ls.cidr4 || 0) + (ls.cidr6 || 0)
					? ', ' + _('%d subnets').format((ls.cidr4 || 0) + (ls.cidr6 || 0))
					: '') +
				(ls.subtracted
					? ' · ' + _('%d removed by the "do not bypass" list').format(ls.subtracted)
					: '')));

			// А это СОВСЕМ ДРУГАЯ величина: сколько адресов dnsmasq успел
			// положить в набор по факту запросов. Она растёт по мере обращений
			// и не связана с числом доменов никаким отношением — поэтому стоит
			// отдельной строкой со своей подписью, а не рядом через «из».
			// Практическая польза: ноль здесь при работающей службе означает,
			// что dnsmasq набор не наполняет.
			if (st.set4 >= 0)
				rows.push(row(_('Resolved into the bypass set'),
					_('%d addresses').format(st.set4)));

			rows.push(row(_('Lists updated'), fmtAge(st.lists_updated)));
		}

		return E('table', { 'class': 'table' }, rows);
	},

	renderVersions: function(v, box) {
		var self = this;
		var rows = [
			row(_('Package'), v.package || _('unknown')),
			row(_('TrustTunnel client'), v.client || _('not installed'))
		];

		// latest == null означает «проверить не удалось»: ни сети, ни кэша,
		// либо у репозитория ещё нет ни одного релиза. Это НЕ то же самое,
		// что «обновлений нет», и говорить об этом надо разными словами —
		// иначе человек решит, что он на свежей версии, хотя проверки не было.
		if (v.latest == null)
			rows.push(row(_('Update check'), _('unavailable — no network and no cached result')));
		else if (v.update_available)
			rows.push(row(_('Update'), E('span', {}, [
				E('strong', {}, _('%s is available').format(v.latest)), ' — ',
				_('run install.sh again to update')
			])));
		// Установленное новее последнего известного релиза — не «актуальная
		// версия», а особый случай: либо сборка из main, либо кэш, который не
		// удалось обновить. Своими словами, а не общим успокаивающим ответом.
		else if (v.ahead)
			rows.push(row(_('Update'),
				_('the installed version is newer than the latest release (%s)').format(v.latest)));
		else
			rows.push(row(_('Update'), _('up to date')));

		if (v.stale)
			rows.push(row(_('Update check'), _('GitHub unreachable, showing the last cached result')));

		// Кнопка обязательна именно потому, что ответ кэшируется: без неё
		// единственный способ узнать о вышедшем релизе раньше, чем истечёт
		// кэш, — перезагрузить роутер (кэш лежит в /var, то есть в tmpfs).
		return E('div', {}, [
			E('table', { 'class': 'table' }, rows),
			E('div', { 'style': 'margin-top:.5em' }, E('button', {
				'class': 'cbi-button cbi-button-neutral',
				'click': ui.createHandlerFn(this, function() {
					return callVersions(true).then(function(nv) {
						dom.content(box, self.renderVersions(nv, box));
					}).catch(function(e) {
						ui.addNotification(null, E('p', {}, e.message || String(e)), 'danger');
					});
				})
			}, _('Check now')))
		]);
	},

	load: function() {
		return callStatus();
	},

	render: function(st) {
		var self = this;
		var verdictBox = E('div', {}, this.renderVerdict(st));
		var factsBox = E('div', {}, this.renderFacts(st));
		var versionBox = E('div', {}, E('em', {}, _('Checking…')));
		var logBox = E('pre', {
			'style': 'max-height:22em;overflow:auto;margin:0'
		}, '');

		// Версии запрашиваются ОДИН раз при отрисовке, а не через poll:
		// сетевая часть кэшируется на сутки, и повторять даже кэшированный
		// вызов каждые десять секунд незачем.
		callVersions(false).then(function(v) {
			dom.content(versionBox, self.renderVersions(v, versionBox));
		}).catch(function(e) {
			dom.content(versionBox, E('em', {}, e.message || String(e)));
		});

		// 10 с, а не 5: каждый опрос состояния считает на бэкенде размер
		// наборов обхода. При заполненном списком наборе это самая тяжёлая
		// операция пакета, и удвоенный интервал вдвое снижает нагрузку без
		// заметной потери отзывчивости.
		poll.add(function() {
			return callStatus().then(function(s) {
				dom.content(verdictBox, self.renderVerdict(s));
				dom.content(factsBox, self.renderFacts(s));
			});
		}, 10);

		poll.add(function() {
			return callLog(80).then(function(r) {
				logBox.textContent = (r.lines || []).join('\n');
			});
		}, 10);

		// Два блока рядом через flex-wrap, а НЕ через сетку с media-запросами:
		// оба узкие и самостоятельные, а flex-basis заставляет их встать в
		// столбик на телефоне сам, без своего CSS. Это тот же приём, которым
		// размечены строки формы в самой теме (.cbi-value — display:flex).
		//
		// Форму так делить нельзя: её строки УЖЕ двухколоночные (метка 180px +
		// поле), а содержимое ограничено 1180px, поэтому вторая колонка
		// оставила бы полю около 370px и сплющила пояснения под ним.
		var pair = E('div', {
			'style': 'display:flex;flex-wrap:wrap;gap:0 1.5em'
		}, [
			E('div', { 'style': 'flex:1 1 24em;min-width:0' }, [
				E('h3', {}, _('Now')),
				factsBox
			]),
			E('div', { 'style': 'flex:1 1 24em;min-width:0' }, [
				E('h3', {}, _('Versions')),
				versionBox
			])
		]);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('TrustTunnel')),

			E('div', { 'class': 'cbi-section' }, [
				verdictBox,
				E('div', { 'style': 'margin-top:1em' }, [
					E('button', {
						'class': 'cbi-button cbi-button-apply',
						'click': ui.createHandlerFn(this, 'handleAction', 'start')
					}, _('Start')),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-reset',
						'click': ui.createHandlerFn(this, 'handleAction', 'stop')
					}, _('Stop')),
					' ',
					E('button', {
						'class': 'cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleAction', 'restart')
					}, _('Restart'))
				])
			]),

			E('div', { 'class': 'cbi-section' }, [ pair ]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Client log')),
				logBox
			])
		]);
	}
});
