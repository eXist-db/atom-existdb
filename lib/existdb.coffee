EXistSymbolsView = require './existdb-view'
Config = require './project-config'
{CompositeDisposable, Range} = require 'atom'
Provider = require "./provider"
Uploader = require "./uploader"
path = require 'path'
$ = require 'jquery'

COMPILE_MSG_RE = /.*line:?\s(\d+)/i

module.exports = Existdb =
    config:
        server:
            title: 'Root HTTP URI of the eXist Server to connect to'
            type: 'string'
            default: 'http://localhost:8080/exist'
        user:
            type: 'string'
            default: 'admin'
        password:
            type: 'string'
            default: ''
        root:
            title: 'Root collection'
            description: """The root collection to resolve relative paths against.
                Set this to the app root if you are working on an application package,
                e.g. /db/apps/test-app."""
            type: 'string'
            default: '/db'
    existdbView: null
    modalPanel: null
    subscriptions: null
    projectConfig: null
    provider: undefined
    symbolsView: undefined
    uploader: undefined

    activate: (state) ->
        console.log "Activating eXistdb"

        @projectConfig = new Config()

        @provider = new Provider(@projectConfig)

        @symbolsView = new EXistSymbolsView(@projectConfig)

        @uploader = new Uploader(@projectConfig)

        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable

        # Register command that toggles this view
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:run': => @run(atom.workspace.getActiveTextEditor())
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:file-symbols': => @gotoFileSymbol()
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:upload': @uploader.upload

    deactivate: ->
        @projectConfig.destroy()

        @subscriptions.dispose()

    serialize: ->
        #existdbViewState: @existdbView.serialize()

    gotoFileSymbol: ->
        editor = atom.workspace.getActiveTextEditor()
        @symbolsView.populate(editor)

    run: (editor) ->
        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        basePath = "xmldb:exist://#{@projectConfig.getConfig(editor).root}/#{collection}"
        self = this
        notifTimeout =
            setTimeout(
                -> atom.notifications.addInfo("Running query ..."),
                500
            )
        $.ajax
            type: "POST"
            url: self.projectConfig.getConfig(editor).server + "/apps/atom-editor/execute"
            dataType: "text"
            data: { "qu": editor.getText(), "base": basePath, "output": "adaptive" }
            username: self.projectConfig.getConfig(editor).user
            password: self.projectConfig.getConfig(editor).password
            success: (data, status, xhr) ->
                clearTimeout(notifTimeout)
                promise = atom.workspace.open(null, { split: "left" })
                promise.then((newEditor) ->
                    grammar = atom.grammars.grammarForScopeName("text.xml")
                    newEditor.setGrammar(grammar)
                    newEditor.setText(data)
                    elapsed = xhr.getResponseHeader("X-elapsed")
                    atom.notifications.addSuccess("Query executed in #{elapsed}s")
                )
            error: (xhr, status) ->
                clearTimeout(notifTimeout)
                atom.notifications.addError("Query execution failed: #{status}",
                    { detail: xhr.responseText, dismissable: true })

    provide: ->
        return @provider

    provideLinter: ->
        provider =
            name: 'xqlint'
            grammarScopes: ['source.xq']
            scope: 'file'
            lintOnFly: true
            lint: (textEditor) =>
                return @lintOpenFile(textEditor)

    lintOpenFile: (editor) ->
        data = editor.getText()
        return unless data.length > 0

        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        basePath = "xmldb:exist://" + @projectConfig.getConfig(editor).root + "/" + collection
        self = this
        return new Promise (resolve) ->
            $.ajax
                type: "PUT"
                url: self.projectConfig.getConfig(editor).server + "/apps/atom-editor/compile.xql"
                dataType: "json"
                data: data
                headers:
                    "X-BasePath": basePath
                contentType: "application/octet-stream"
                username: self.projectConfig.getConfig(editor).user
                password: self.projectConfig.getConfig(editor).password
                success: (data) ->
                    if data.result == "fail"
                        error = self.parseErrMsg(data.error)
                        range = null
                        if error.line > -1
                            end = editor.lineTextForBufferRow(error.line).length
                            range = new Range(
                                [error.line, error.column - 1],
                                [error.line, end - 1]
                            )
                        message = {
                            type: 'Error',
                            text: error.msg,
                            range: range,
                            filePath: editor.getPath()
                        }
                        resolve([message])
                    else
                        resolve([])

    parseErrMsg: (error) ->
        if error.line?
            msg = error["#text"]
        else
            msg = error

        str = COMPILE_MSG_RE.exec(msg)
        line = -1

        if str?
            line = parseInt(str[1]) - 1
        else if error.line
            line = parseInt(error.line) - 1

        column = error.column || 0
        return { line: line, column: parseInt(column), msg: msg }
