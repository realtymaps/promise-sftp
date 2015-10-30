/* jshint node:true */
/* jshint -W097 */
'use strict';


var coffee = require('coffee-script');
coffee.register();

module.exports = require('./lib/promiseSftp');
module.exports.FtpConnectionError = require('promise-ftp-common').FtpConnectionError;
module.exports.FtpReconnectError = require('promise-ftp-common').FtpReconnectError;
module.exports.STATUSES = require('promise-ftp-common').STATUSES;
