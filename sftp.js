var inherits = require('util').inherits
	, EventEmitter = require('events').EventEmitter
	, Client = require('ssh2').Client
	, SFTPWrapper = require('./lib/sftp-wrapper') //needed to modify the prototype of ssh2/SFTPWrapper
	;

module.exports = SFTPClient

function SFTPClient (options) {
	if (!(this instanceof SFTPClient)) {
		return new SFTPClient(options);
	}

	var self = this;

	EventEmitter.call(self);

	self.conn = new Client();

	self.conn.on('error', self.emit.bind(self, 'error'));

	self.conn.on('ready', function () {
		self.conn.sftp(function (err, sftp) {
			if (err) {
				self.emit('error', err);
			}

			var noCopy = ['on', 'once', 'emit', 'end']

			Object.keys(sftp.constructor.prototype).forEach(function (key) {
				if (~noCopy.indexOf(key)) {
					return;
				}

				var val = sftp[key];

				if (typeof val === 'function') {
					self[key] = sftp[key].bind(sftp);
				}
				else {
					self[key] = sftp[key];
				}
			});

			self.emit('ready');
		});
	});
}

inherits(SFTPClient, EventEmitter);

SFTPClient.prototype.connect = function (options) {
	var self = this;

	self.conn.connect.apply(self.conn, arguments);

	return self;
};

SFTPClient.prototype.end = function () {
	var self = this;

	self.conn.end.apply(self.conn, arguments);

	return self;
};
