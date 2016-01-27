{CompositeDisposable} = require 'atom'
fs = require 'fs'
path = require 'path'
$ = require('jquery')

module.exports =
class Watch

    @disposables: undefined
    @watchers

    constructor: (@config) ->
        @disposables = new CompositeDisposable()
        @disposables.add(atom.project.onDidChangePaths(@init))
        @watchers = new CompositeDisposable()
        @init()

    init: ->
        @watchers.dispose()
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

    fileChanged: (path) ->
        project = @config.getProjectConfig(path)
        relPath = path.substring(project.path.length)
        console.log("file changed: %o", relPath)
        url = project.config.server + "/rest/#{project.config.root}/#{relPath}"
        console.log("upload url: %s", url)

        #$.ajax
        #    type: "PUT"
        #    url: project.config.server + "/rest/#{project.config.root}/#{relPath}"
        #    dataType: "json"
        #    data: editor.getText()
        #    headers:
        #        "X-BasePath": basePath
        #    contentType: "application/octet-stream"
        #    username: self.projectConfig.getConfig(editor).user
        #    password: self.projectConfig.getConfig(editor).password
        #    success: (data) ->

    dispose: () ->
        @watchers.dispose()
        @disposables.dispose()
