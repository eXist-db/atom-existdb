{CompositeDisposable} = require 'atom'
fs = require 'fs'
request = require 'request'
path = require 'path'
mime = require 'mime'
$ = require('jquery')

module.exports =
class Watch

    @disposables: undefined
    @watchers: undefined

    constructor: (@config) ->
        @disposables = new CompositeDisposable()
        @disposables.add(atom.project.onDidChangePaths(@init))

        @init()

        mime.define({
            "application/xquery": ["xq", "xql", "xquery", "xqm"]
        })

    init: ->
        @watchers.dispose() if @watchers?
        @watchers = new CompositeDisposable()
        dirs = atom.project.getDirectories()
        for dir in dirs
            @watchDirectory(dir)

    watchDirectory: (dir) ->
        self = this
        dir.getEntries((error, entries) ->
            if not error?
                for entry in entries
                    do (entry) ->
                        if entry.isFile()
                            self.watchers.add(entry.onDidChange(() -> self.fileChanged(entry.getPath())))
                        else
                            self.watchDirectory(entry)
        )

    fileChanged: (file) ->
        project = @config.getProjectConfig(file)
        relPath = file.substring(project.path.length)
        url = "#{project.config.server}/rest/#{project.config.root}/#{relPath}"
        contentType = mime.lookup(path.extname(file))
        console.log("uploading changed file to: %s using type %s", url, contentType)
        self = this
        options =
            uri: url
            method: "PUT"
            auth:
                user: project.config.user
                pass: project.config.password || ""
                sendImmediately: true
            headers:
                "Content-Type": contentType
        fs.createReadStream(file).pipe(
            request(
                options,
                (error, response, body) ->
                    if error?
                        atom.notifications.addError("Failed to upload #{relPath}", detail: error)
                    else
                        atom.notifications.addSuccess("Uploaded #{relPath}: #{response.statusCode}.")
            )
        )

    dispose: () ->
        console.log("disposing watchers ...")
        @watchers.dispose()
        @disposables.dispose()
