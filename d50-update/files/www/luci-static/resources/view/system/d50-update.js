'use strict';
'require view';
'require dom';
'require rpc';
'require ui';

const callStatus = rpc.declare({ object: 'd50-update', method: 'status' });
const callCheck = rpc.declare({ object: 'd50-update', method: 'check' });
const callDownload = rpc.declare({ object: 'd50-update', method: 'download' });
const callFlash = rpc.declare({ object: 'd50-update', method: 'flash' });

function when(seq) {
	return seq ? new Date(seq * 1000).toLocaleString() : _('unknown');
}

function mb(bytes) {
	return '%.1f MB'.format(bytes / 1048576);
}

function row(label, value) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, label),
		E('td', { 'class': 'td left' }, value)
	]);
}

return view.extend({
	load: function() {
		return callCheck().catch(function(e) {
			return { ok: false, error: e.message };
		});
	},

	show: function(r) {
		const body = [];

		if (!r.ok) {
			body.push(E('div', { 'class': 'alert-message warning' }, r.error));
		}
		else {
			const cur = r.current || {};
			const lat = r.latest || {};

			body.push(E('table', { 'class': 'table' }, [
				row(_('Running'), cur.build ? '%s (%s)'.format(cur.build, when(cur.seq)) : _('unknown build')),
				row(_('Latest'), '%s (%s)'.format(lat.build, when(lat.seq))),
				lat.base ? row(_('Built on'), lat.base) : '',
				row(_('Size'), mb(lat.size)),
				lat.notes ? row(_('Notes'), lat.notes) : '',
				row(_('Settings'), r.keep ? _('kept') : _('replaced by the settings in the image'))
			]));

			if (r.removed && r.removed.length)
				body.push(E('div', { 'class': 'alert-message warning' }, [
					E('p', _('These installed packages are not in the new image and will be removed. Their settings are kept, reinstall them after the update:')),
					E('p', {}, E('code', r.removed.join(' ')))
				]));

			if (r.same)
				body.push(E('p', {}, E('strong', _('This router is up to date.'))));
			else if (!r.newer)
				body.push(E('p', {}, E('strong', _('The running image is newer than the latest published one.'))));
		}

		body.push(E('div', { 'class': 'cbi-page-actions' }, [
			E('button', {
				'class': 'btn cbi-button',
				'click': ui.createHandlerFn(this, 'handleCheck')
			}, _('Check again')),
			' ',
			E('button', {
				'class': 'btn cbi-button-action important',
				'disabled': (r.ok && r.newer) ? null : '',
				'click': ui.createHandlerFn(this, 'handleUpdate', r)
			}, _('Update'))
		]));

		dom.content(this.box, body);
	},

	handleCheck: function() {
		return callCheck().catch(function(e) {
			return { ok: false, error: e.message };
		}).then(L.bind(this.show, this));
	},

	handleUpdate: function(r) {
		ui.showModal(_('Update to %s?').format(r.latest.build), [
			E('p', _('The router downloads the image (%s), checks it and flashes it. The internet connection drops for a few minutes while it flashes and restarts. Settings are %s.')
				.format(mb(r.latest.size), r.keep ? _('kept') : _('replaced by the settings in the image'))),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, _('Cancel')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': ui.createHandlerFn(this, 'run', r)
				}, _('Update'))
			])
		]);
	},

	run: function(r) {
		const progress = E('p', { 'class': 'spinning' }, _('Starting the download...'));

		ui.showModal(_('Downloading'), [ progress ]);

		return callDownload().then(function(res) {
			if (!res.ok)
				throw new Error(res.error);

			return new Promise(function(resolve, reject) {
				const tick = function() {
					callStatus().then(function(s) {
						if (s.state == 'ready')
							return resolve();
						if (s.state == 'error')
							return reject(new Error(s.message));
						if (s.downloaded != null)
							dom.content(progress, (s.downloaded >= r.latest.size)
								? _('Checking the image...')
								: _('Downloaded %s of %s').format(mb(s.downloaded), mb(r.latest.size)));
						window.setTimeout(tick, 1000);
					}, reject);
				};
				tick();
			});
		}).then(function() {
			return callFlash();
		}).then(function(res) {
			if (!res.ok)
				throw new Error(res.error);

			ui.showModal(_('Flashing...'), [
				E('p', { 'class': 'spinning' }, _('The system is flashing now.<br /> DO NOT POWER OFF THE DEVICE!<br /> Wait a few minutes before you try to reconnect.'))
			]);
			ui.awaitReconnect(window.location.host, '192.168.1.1', 'openwrt.lan');
		}).catch(L.bind(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', _('Update stopped: %s').format(e.message)), 'error');
			return this.handleCheck();
		}, this));
	},

	render: function(r) {
		this.box = E('div');
		this.show(r);

		return E([], [
			E('h2', _('Image Update')),
			E('div', { 'class': 'cbi-map-descr' }, _('Checks for a newer image for this router. Nothing is installed until you press Update.')),
			this.box
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
