ExistdbView = require './existdb-view'
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

    activate: (state) ->
        console.log "Activating eXistdb"

        @config = new Config()

        @provider = new Provider(@config)

        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable

        # Register command that toggles this view
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:run': => @run(atom.workspace.getActiveTextEditor())

    deactivate: ->
        @config.destroy()

        @subscriptions.dispose()

    serialize: ->
        #existdbViewState: @existdbView.serialize()

    run: (editor) ->
        console.log 'Existdb was toggled!'

        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        basePath = "xmldb:exist://" + @config.data.root + "/" + collection
        self = this
        $.ajax
            type: "POST"
            url: self.config.data.server + "/apps/eXide/execute"
            dataType: "text"
            data: { "qu": editor.getText(), "base": basePath, "output": "adaptive" }
            success: (data) ->
                console.log(data)
                promise = atom.workspace.open(null, { split: "bottom" })
                promise.then((newEditor) -> newEditor.setText(data))
        #if @modalPanel.isVisible()
        #  @modalPanel.hide()
        #else
        #  @modalPanel.show()

    provide: ->
        return @provider

    provideLinter: ->
        console.log("getting linter")
        provider =
            name: 'xqlint'
            grammarScopes: ['source.xq']
            scope: 'file'
            lintOnFly: true
            lint: (textEditor) =>
                return @lintOpenFile textEditor

    lintOpenFile: (editor) ->
        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        basePath = "xmldb:exist://" + @config.data.root + "/" + collection
        self = this
        return new Promise (resolve) ->
            $.ajax
                type: "PUT"
                url: self.config.data.server + "/apps/eXide/modules/compile.xql"
                dataType: "json"
                data: editor.getText()
                headers:
                    "X-BasePath": basePath
                contentType: "application/octet-stream"
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
        if error.line
            msg = error["#text"]
        else
            msg = error

        str = COMPILE_MSG_RE.exec(msg)
        line = -1

        if str
            line = parseInt(str[1]) - 1
        else if error.line
            line = parseInt(error.line) - 1

        column = error.column || 0
        return { line: line, column: parseInt(column), msg: msg }
