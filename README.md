sftpjs
-------

This module provides quick access to the sftp functionality in mscdex/ssh2. In addition
it attempts to create an API that is similar to mscdex/node-ftp with the intent of making
them interchangable.

status
------

I intend on implementing the following methods in a compatible way with mscdex/node-ftp:

* .connect() - done
* .end() - done
* .list() - done
* .get()
* .put()
* .mkdir()
* .rename()

All other methods will be the same as defined in [ssh2-streams/SFTPStream](https://github.com/mscdex/ssh2-streams/blob/master/SFTPStream.md#sftpstream-methods).

example
-------

```js
var Client = require('sftpjs');
var c = Client();

c.on('ready', function () {
  c.list(function (err, list) {
    if (err) throw err;

    console.dir(list);

    c.end();
  });
}).connect({
  host : 'thanks'
  , user : 'for'
  , password : 'allthefish'
});
```

install
-------

```shell
npm install sftpjs
```

api
---

* **(constructor)**() - Creates and returns a new SFTP client instance
* **connect** - see https://github.com/mscdex/ssh2/blob/master/README.md#client-methods

license
-------

MIT
