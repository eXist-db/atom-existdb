EXistSymbolsView = require './existdb-view'
Config = require './project-config'
{CompositeDisposable, Range} = require 'atom'
Provider = require "./provider"
path = require 'path'
$ = require 'jquery'

COMPILE_MSG_RE = /.*line:?\s(\d+)/i

module.exports = Existdb =
    existdbView: null
    modalPanel: null
    subscriptions: null
    config: null
    provider: undefined
    symbolsView: undefined

    activate: (state) ->
        console.log "Activating eXistdb"

        @config = new Config()

        @provider = new Provider(@config)

        @symbolsView = new EXistSymbolsView(@config)

        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable

        # Register command that toggles this view
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:run': => @run(atom.workspace.getActiveTextEditor())
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:file-symbols': => @gotoFileSymbol()

    deactivate: ->
        @config.destroy()

        @subscriptions.dispose()

    serialize: ->
        #existdbViewState: @existdbView.serialize()

    gotoFileSymbol: ->
        editor = atom.workspace.getActiveTextEditor()
        @symbolsView.populate(editor)

    run: (editor) ->
        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        basePath = "xmldb:exist://#{@config.data.root}/#{collection}"
        self = this
        notifTimeout =
            setTimeout(
                -> atom.notifications.addInfo("Running query ..."),
                500
            )
        $.ajax
            type: "POST"
            url: self.config.data.server + "/apps/atom-editor/execute"
            dataType: "text"
            data: { "qu": editor.getText(), "base": basePath, "output": "adaptive" }
            username: self.config.data.user
            password: self.config.data.password
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
        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        basePath = "xmldb:exist://" + @config.data.root + "/" + collection
        self = this
        return new Promise (resolve) ->
            $.ajax
                type: "PUT"
                url: self.config.data.server + "/apps/atom-editor/compile.xql"
                dataType: "json"
                data: editor.getText()
                headers:
                    "X-BasePath": basePath
                contentType: "application/octet-stream"
                username: self.config.data.user
                password: self.config.data.password
                success: (data) ->
                    if data.result == "fail"
                        error = self.parseErrMsg(data.error)
                        end = editor.lineTextForBufferRow(error.line).length
                        message = {
                            type: 'Error',
                            text: error.msg,
                            range: new Range(
                                [error.line, error.column - 1],
                                [error.line, end - 1]
                            ),
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
