{CompositeDisposable} = require 'atom'
fs = require 'fs'
request = require 'request'
path = require 'path'
mime = require 'mime'

module.exports =
class Uploader

    constructor: (@config) ->
        disposables = new CompositeDisposable()

        mime.define({
            "application/xquery": ["xq", "xql", "xquery", "xqm"]
        })

        self = this
        disposables.add(atom.workspace.observeTextEditors((editor) ->
            onDidSave = editor.onDidSave((ev) ->
                self.fileChanged(ev.path)
            )
            onDidDestroy = editor.onDidDestroy((ev) ->
                disposables.remove(onDidSave)
                disposables.remove(onDidDestroy)
                onDidDestroy.dispose()
                onDidSave.dispose()
            )

            disposables.add(onDidSave)
            disposables.add(onDidDestroy)
        ))

    upload: =>
        editor = atom.workspace.getActiveTextEditor()
        @fileChanged(editor.getPath(), true)

    fileChanged: (file, force = false) ->
        project = @config.getProjectConfig(file)
        return unless project? and (project?.config.sync or force)
        return if @config.ignoreFile(file)

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
