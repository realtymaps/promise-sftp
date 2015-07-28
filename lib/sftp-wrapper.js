var SFTPWrapper = require('ssh2/lib/SFTPWrapper')
	, join = require('path').join
	;

module.exports = SFTPWrapper;

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
				, date : new Date(f.attrs.mtime * 1000)
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

SFTPWrapper.prototype.__mkdir = SFTPWrapper.prototype.mkdir;

SFTPWrapper.prototype.mkdir = function (path, recursive, cb) {
	var self = this;

	if (arguments.length === 2) {
		cb = recursive;
		recursive = false;
	}
	
	if (!recursive) {
		return self.__mkdir(path, cb);
	}

	var tokens = path.split(/\//g);
	var p = '';

	return mkdirp();

	function mkdirp () {
		var token = tokens.shift();

		if (!token && !tokens.length) {
			return cb(null);
		}

		token += '/';
		p = join(p, token);

		return self.__mkdir(p, function (err) {
			if (err && err.code != 4) {
				return cb(err);
			}

			mkdirp();
		});
	}
};

