### jshint node:true ###
### jshint -W097 ###
'use strict'


Promise = require('bluebird')
fs = require('fs')
SshClient = require('ssh2').Client
path = require('path')

FtpConnectionError = require('promise-ftp-common').FtpConnectionError
FtpReconnectError = require('promise-ftp-common').FtpReconnectError
STATUSES = require('promise-ftp-common').STATUSES
ERROR_CODES = require('./errorCodes')


# these methods need no custom logic; just wrap the common logic around the originals and pass through any args
simplePassthroughMethods =
  rename: 'continue'
  rmdir: 'continue'  # TODO: test recursive behavior and implement and/or document
  fastGet: 'callback'
  fastPut: 'callback'
  createReadStream: 'return'
  createWriteStream: 'return'
  open: 'continue'
  close: 'continue'
  write: 'continue'
  fstat: 'continue'
  fsetstat: 'continue'
  futimes: 'continue'
  fchown: 'continue'
  fchmod: 'continue'
  opendir: 'continue'
  readdir: 'continue'
  unlink: 'continue'
  stat: 'continue'
  lstat: 'continue'
  setstat: 'continue'
  utimes: 'continue'
  chown: 'continue'
  chmod: 'continue'
  readlink: 'continue'
  symlink: 'continue'
  realpath: 'continue'
  ext_openssh_rename: 'continue'
  ext_openssh_statvfs: 'continue'
  ext_openssh_fstatvfs: 'continue'
  ext_openssh_hardlink: 'continue'
  ext_openssh_fsync: 'continue'

# these methods will have custom logic defined, and then will be wrapped in common logic
complexPassthroughMethods =
  list: 'none'
  get: 'none'
  put: 'none'
  append: 'none'
  delete: 'none'
  mkdir: 'continue'
  listSafe: 'none'
  size: 'none'
  lastMod: 'none'
  read: 'continue'
  wait: 'none'

# these methods do not use the common wrapper; they're listed here in order to be properly set on the prototype
otherPrototypeMethods = [
  'connect'
  'reconnect'
  'logout'
  'end'
  'destroy'
  'getConnectionStatus'
  'restart'
]


class PromiseSftp

  constructor: () ->
    if @ not instanceof PromiseSftp
      throw new TypeError("PromiseSftp constructor called without 'new' keyword")

    connectionStatus = STATUSES.NOT_YET_CONNECTED
    sshClient = new SshClient()
    sftpClientContext = {}
    connectOptions = null
    autoReconnect = null
    keyboardInteractive = null
    changePassword = null
    lastSshError = null
    lastSftpError = null
    closeSshError = null
    closeSftpError = null
    unexpectedClose = null
    autoReconnectPromise = null
    continuePromise = Promise.resolve()
    promisifiedClientMethods = {}
    restartOffset = null

    
    # always-on event handlers
    sshClient.on 'error', (err) ->
      lastSshError = err
    sshClient.on 'close', (hadError) ->
      if hadError
        closeSshError = lastSshError
      unexpectedClose = (connectionStatus != STATUSES.DISCONNECTING && connectionStatus != STATUSES.LOGGING_OUT)
      connectionStatus = STATUSES.DISCONNECTED
      autoReconnectPromise = null
      if keyboardInteractive
        sshClient.removeListener('keyboard-interactive', keyboardInteractive)
      if changePassword
        sshClient.removeListener('change password', changePassword)

    
    # common 'continue' logic
    continueLogicFactory = (clientContext, name) ->
      (args...) -> new Promise (resolve, reject) ->
        continuePromise = new Promise (resolve2, reject2) ->
          clientContext.client.once('continue', resolve2)
          ready = clientContext.client[name] args..., (err, args2...) ->
            if err
              return reject(err)
            if args2.length == 0
              result = null
            else if args2.length == 1
              result = args2[0]
            else
              result = args2
            resolve(result)
          if ready
            clientContext.client.removeListener('continue', resolve2)
            resolve2()

    # common 'finish' logic
    finishLogic = (stream) ->
      continuePromise = new Promise (resolve, reject) ->
        stream.once('finish', resolve)
      undefined

    # internal connect logic
    _getSftpStream = continueLogicFactory(client: sshClient, 'sftp')
    _connect = (tempStatus) ->
      new Promise (resolve, reject) ->
        connectionStatus = tempStatus
        serverMessage = null
        sshClient.once 'banner', (msg, lang) ->
          serverMessage = msg
        if keyboardInteractive
          sshClient.on('keyboard-interactive', keyboardInteractive)
        if changePassword
          sshClient.on('change password', changePassword)
        onSshReady = () ->
          sshClient.removeListener('error', onSshError)
          closeSshError = null
          _getSftpStream()
          .then (sftp) ->
            sftpClientContext.client = sftp
            resolve(serverMessage)
          .catch (err) ->
            lastSftpError = err
            sshClient.destroy()
            reject(err)
        onSshError = (err) ->
          sshClient.removeListener('ready', onSshReady)
          reject(err)
        sshClient.once('ready', onSshReady)
        sshClient.once('error', onSshError)
        sshClient.connect(connectOptions)
      .then (serverMessage) ->
        closeSftpError = null
        unexpectedClose = false
        connectionStatus = STATUSES.CONNECTED
        sftpClientContext.client.on 'error', (err) ->
          lastSftpError = err
        sftpClientContext.client.on 'close', (hadError) ->
          if hadError
            closeSftpError = lastSftpError
          sshClient.destroy()
        serverMessage


    # methods listed in otherPrototypeMethods, which don't get a wrapper

    @connect = (options) ->
      continuePromise
      .then () ->
        if connectionStatus != STATUSES.NOT_YET_CONNECTED && connectionStatus != STATUSES.DISCONNECTED
          throw new FtpConnectionError("can't connect when connection status is: '#{connectionStatus}'")
        # copy options object so options can't change without another call to @connect()
        connectOptions = {}
        for key,value of options
          connectOptions[key] = value
        # autoReconnect is part of PromiseSftp, so it's not understood by the underlying sshClient
        autoReconnect = !!options.autoReconnect
        delete connectOptions.autoReconnect
        # privateKeyFile is part of PromiseSftp, so handle it here
        if connectOptions.privateKeyFile && !connectOptions.privateKey
          connectOptions.privateKey = fs.readFileSync(connectOptions.privateKeyFile)
        delete connectOptions.privateKeyFile
        # simplified password-change setup
        if connectOptions.changePassword
          _changePassword = connectOptions.changePassword
          changePassword = (message, language, finish) ->
            Promise.try () ->
              _changePassword(message, language)
            .catch (err) -> null
            .then(finish)
        delete connectOptions.changePassword
        # simplified keyboard-interactive setup
        if connectOptions.tryKeyboard
          _keyboardInteractive = connectOptions.tryKeyboard
          connectOptions.tryKeyboard = true
          keyboardInteractive = (name, instructions, instructionsLang, prompts, finish) ->
            Promise.try () ->
              _keyboardInteractive(name, instructions, instructionsLang, prompts)
            .catch (err) -> null
            .all(finish)
        # alias options.user to options.username to match the promise-ftp API
        if connectOptions.user && !connectOptions.username
          connectOptions.username = connectOptions.user
        delete connectOptions.user
        # alias options.connTimeout to options.readyTimeout to match the promise-ftp API
        if connectOptions.connTimeout && !connectOptions.readyTimeout
          connectOptions.readyTimeout = connectOptions.connTimeout
        delete connectOptions.connTimeout
        # alias options.pasvTimeout to options.readyTimeout to match the promise-ftp API
        if connectOptions.pasvTimeout && !connectOptions.readyTimeout
          connectOptions.readyTimeout = connectOptions.pasvTimeout
        delete connectOptions.pasvTimeout
        # alias options.keepalive to options.keepaliveInterval to match the promise-ftp API
        if connectOptions.keepalive && !connectOptions.keepaliveInterval
          connectOptions.keepaliveInterval = connectOptions.keepalive
        delete connectOptions.keepalive
  
        # now that everything is set up, we can connect
        _connect(STATUSES.CONNECTING)

    @reconnect = () ->
      continuePromise
      .then () ->
        if connectionStatus != STATUSES.NOT_YET_CONNECTED && connectionStatus != STATUSES.DISCONNECTED
          throw new FtpConnectionError("can't reconnect when connection status is: '#{connectionStatus}'")
        _connect(STATUSES.RECONNECTING)

    @end = () ->
      (autoReconnectPromise || Promise.resolve())
      .then () ->
        continuePromise
      .then () ->
        if connectionStatus == STATUSES.NOT_YET_CONNECTED || connectionStatus == STATUSES.DISCONNECTED || connectionStatus == STATUSES.DISCONNECTING
          throw new FtpConnectionError("can't end connection when connection status is: #{connectionStatus}")
        new Promise (resolve, reject) ->
          restartOffset = null
          connectionStatus = STATUSES.DISCONNECTING
          sshClient.once 'close', (hadError) ->
            resolve(if hadError then lastSshError||true else false)
          sshClient.end()

    @logout = @end
    
    @destroy = () ->
      if connectionStatus == STATUSES.NOT_YET_CONNECTED || connectionStatus == STATUSES.DISCONNECTED
        wasDisconnected = true
      else
        wasDisconnected = false
        connectionStatus = STATUSES.DISCONNECTING
      restartOffset = null
      sshClient.destroy()
      wasDisconnected

    @getConnectionStatus = () ->
      connectionStatus

    @restart = (byteOffset) -> Promise.try () ->
      restartOffset = byteOffset
      undefined
    
    # methods listed in complexPassthroughMethods, which will get a common logic wrapper

    @list = (path='.') ->
      promisifiedClientMethods.readdir(path)
      .then (files) ->
        # create a promise-ftp like result
        for file in files
          type: file.longname.substr(0, 1)
          name: file.filename
          size: file.attrs.size
          date: new Date(file.attrs.mtime * 1000)
          rights:
            user: file.longname.substr(1, 3).replace(/-/g, '')
            group: file.longname.substr(4, 3).replace(/-/g, '')
            other: file.longname.substr(7, 3).replace(/-/g, '')
          owner: file.attrs.uid
          group: file.attrs.gid
          target: null   # TODO
          sticky: null   # TODO

    @get = (sourcePath, options = {}) -> Promise.try () ->
      if restartOffset != null
        options.start = options.start || restartOffset
        options.flags = options.flags || 'r+'
        restartOffset = null
      promisifiedClientMethods.createReadStream(sourcePath, options)
      .then (stream) ->
        finishLogic(stream)
        stream

    @put = (input, destPath) -> Promise.try () ->
      if restartOffset != null
        options =
          start: restartOffset
          flags: 'r+'
        restartOffset = null
      #input can be a ReadableStream, Buffer or Path
      if typeof input == 'string'
        if !options
          return promisifiedClientMethods.fastPut(input, destPath)
        input = fs.createReadStream(input)
      promisifiedClientMethods.createWriteStream(destPath, options)
      .then (stream) ->
        finishLogic(stream)
        if input instanceof Buffer
          return stream.end(input)
        input.pipe(stream)
        undefined

    @append = (input, destPath) ->
      promisifiedClientMethods.createWriteStream(destPath, flags: 'a')
      .then (stream) ->
        finishLogic(stream)
        #input can be a ReadableStream, Buffer or Path
        if input instanceof Buffer
          return stream.end(input)
        else if typeof input == 'string'
          input = fs.createReadStream(input)
        input.pipe(stream)
        undefined
  
    @delete = promisifiedClientMethods.unlink

    @mkdir = (dirPath, recursive, attributes) =>
      if typeof(recursive) == 'object'
        attributes = recursive
        recursive = false
      if !recursive
        return promisifiedClientMethods.mkdir(dirPath, attributes)

      # TODO: better recursive/error handling here
      #result = @stat(dirPath)
      #.then (stats) ->
      result = Promise.resolve()
      tokens = dirPath.split(/\//g)
      currPath = if dirPath.charAt(0) == '/' then '/' else ''
      isFirst = true;
      for token in tokens
        if isFirst
          currPath = "#{token}"
          isFirst = false
        else
          currPath = "#{currPath}/#{token}"
        if token == '.' || token == '..'
          continue
        addMkdirJob = (newPath) =>
          @mkdir(newPath, false, attributes)
        result = result
        .then (addMkdirJob(currPath))
        .catch (err) ->
          if err.code != ERROR_CODES.FAILURE && err.code != ERROR_CODES.FILE_ALREADY_EXISTS
            throw err
      result

    @listSafe = @list

    @size = (filePath) =>
      @stat(filePath)
      .then (stats) ->
        stats.size

    @lastMod = (filePath) =>
      @stat(filePath)
      .then (stats) ->
        new Date(stats.mtime * 1000)

    @read = (handle, buffer, offset, length, position) ->
      promisifiedClientMethods.read(handle, buffer, offset, length, position)
      .spread (bytesRead, buffer, position) ->
        { bytesRead, buffer, position }
        
    @wait = () ->  # no-op, will perform wrapper logic only

        
    # common promise, connection-check, and reconnect logic
    commonLogicFactory = (name, finishType, handler) ->
      if finishType == 'continue'
        promisifiedClientMethods[name] = continueLogicFactory(sftpClientContext, name)
      else if finishType == 'callback'
        promisifiedClientMethods[name] = (args...) ->
          Promise.promisify(sftpClientContext.client[name], sftpClientContext.client)(args...)
      else if finishType == 'return'
        promisifiedClientMethods[name] = (args...) -> Promise.try () -> sftpClientContext.client[name](args...)
      else if finishType == 'none'
        promisifiedClientMethods[name] = null
      else  # catch programming errors
        throw new Error("Unrecognized finishType: #{finishType}")
      if !handler
        handler = promisifiedClientMethods[name]
      (args...) ->
        Promise.try () ->
          # if we need to reconnect and we're not already reconnecting, start reconnect
          if unexpectedClose && autoReconnect && !autoReconnectPromise
            originalError = closeSftpError||closeSshError
            autoReconnectPromise = _connect(STATUSES.RECONNECTING)
            .catch (err) ->
              throw new FtpReconnectError(originalError, err, false)
          # if we just started reconnecting or were already reconnecting, wait for that to finish before continuing
          if autoReconnectPromise
            return autoReconnectPromise
          else if connectionStatus != STATUSES.CONNECTED
            throw new FtpConnectionError("can't perform '#{name}' command when connection status is: #{connectionStatus}")
        .then () ->
          continuePromise
        .then () ->
          # now perform the requested command
          handler(args...)

    # create the methods listed in simplePassthroughMethods as common logic wrapped around the original sshClient method
    for name,finishType of simplePassthroughMethods
      @[name] = commonLogicFactory(name, finishType)

    # wrap the methods listed in complexPassthroughMethods with common logic
    for name,finishType of complexPassthroughMethods
      @[name] = commonLogicFactory(name, finishType, @[name])


  # set method names on the prototype; they'll be overwritten with real functions from inside the constructor's closure
  for methodList in [Object.keys(simplePassthroughMethods), Object.keys(complexPassthroughMethods), otherPrototypeMethods]
    for methodName in methodList
      PromiseSftp.prototype[methodName] = null


module.exports = PromiseSftp
