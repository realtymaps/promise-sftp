var inherits = require('util').inherits
	, EventEmitter = require('events').EventEmitter
	, Client = require('ssh2').Client
	, SFTPWrapper = require('ssh2/lib/SFTPWrapper')
	;

SFTPWrapper.prototype.list = function (path, useCompression, cb) {
	var self = this
		, regDash = /-/gi
	
	cb = arguments[arguments.length - 1];

	self.readdir(path, function (err, data) {
		if (err) {
			return cb(err);
		}

		//create an ftp like result

		data.forEach(function (f, i) {
			data[i] = {
				type : f.longname.substr(0, 1)
				, name : f.filename
				, size : f.attrs.size
				, date : f.attrs.mtime
				, rights : {
					user : f.longname.substr(1,3).replace(regDash, '')
					, group : f.longname.substr(4, 3).replace(regDash, '')
					, other : f.longname.substr(7, 3).replace(regDash, '')
				}
				, owner : f.attrs.uid
				, group : f.attrs.gid
				, target : null //TODO
				, sticky : null //TODO
			}
		});

		return cb(null, data);
	});
};

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
