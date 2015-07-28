var SFTP = require('./');

var sftp = SFTP();

sftp.on('ready', function () {
	console.log('ready');
	sftp.list('.', function (err, data) {
		console.dir(data);

		sftp.end();
	});
}).on('error', function (err) {
	console.log(err);
}).connect({
	host : process.env.SFTP_HOST
	, user : process.env.SFTP_USER
	, password : process.env.SFTP_PASSWORD
});
