EXistSymbolsView = require './existdb-view'
EXistTreeView = require './existdb-tree-view'
Config = require './project-config'
{CompositeDisposable, Range} = require 'atom'
request = require 'request'
Provider = require "./provider"
Uploader = require "./uploader"
util = require "./util"
_path = require 'path'
$ = require 'jquery'
XQUtils = require './xquery-helper'

COMPILE_MSG_RE = /.*line:?\s(\d+)/i

module.exports = Existdb =
    config:
        server:
            title: 'HTTP URI of the eXist Server to connect to'
            type: 'string'
            default: 'http://localhost:8080/exist'
        user:
            title: 'User: name'
            type: 'string'
            default: 'admin'
        password:
            title: 'User: password'
            type: 'string'
            default: ''
        root:
            title: 'Root collection'
            description: """The root collection to resolve relative paths against when
                working on a local app directory.
                Set this to the app root if you are working on an application package,
                e.g. /db/apps/test-app."""
            type: 'string'
            default: '/db'
    subscriptions: null
    projectConfig: null
    provider: undefined
    symbolsView: undefined
    uploader: undefined
    treeView: undefined

    activate: (@state) ->
        console.log "Activating eXistdb"
        @projectConfig = new Config()

        @treeView = new EXistTreeView(@state, @projectConfig, @)

        @provider = new Provider(@projectConfig)

        @symbolsView = new EXistSymbolsView(@projectConfig, @)

        @uploader = new Uploader(@projectConfig)

        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable

        # Register command that toggles this view
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:run': => @run(atom.workspace.getActiveTextEditor())
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:file-symbols': => @gotoFileSymbol()
        # @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:upload': @uploader.upload
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:toggle-tree-view': => @treeView.toggle()
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:goto-definition': =>
            editor = atom.workspace.getActiveTextEditor()
            def = XQUtils.getFunctionDefinition(editor, editor.getCursorBufferPosition())
            @gotoDefinition(def.signature, editor) if def?

    deactivate: ->
        @projectConfig.destroy()
        @subscriptions.dispose()
        @symbolsView.destroy()
        @treeView.destroy()
        @statusBarTile?.destroy()
        @statusBarTile = null

    serialize: ->
        if @treeView?
            @treeView.serialize()
        else
            @state

    gotoFileSymbol: ->
        editor = atom.workspace.getActiveTextEditor()
        @symbolsView.populate(editor)

    run: (editor) ->
        collectionPaths = util.getCollectionPaths(editor, @projectConfig)
        self = this
        notifTimeout =
            setTimeout(
                -> atom.notifications.addInfo("Running query ..."),
                500
            )
        @updateStatus("Running query ...")
        chunk = XQUtils.getText(editor)
        $.ajax
            type: "POST"
            url: self.projectConfig.getConfig(editor).server + "/apps/atom-editor/execute"
            dataType: "text"
            data: { "qu": chunk.text, "base": collectionPaths.basePath, "output": "adaptive", "count": 10 }
            username: self.projectConfig.getConfig(editor).user
            password: self.projectConfig.getConfig(editor).password
            success: (data, status, xhr) ->
                clearTimeout(notifTimeout)
                self.updateStatus("")
                promise = atom.workspace.open("query-results", { split: "right", activatePane: false })
                promise.then((newEditor) ->
                    grammar = atom.grammars.grammarForScopeName("text.xml")
                    newEditor.setGrammar(grammar)
                    newEditor.setText(data)
                    elapsed = xhr.getResponseHeader("X-elapsed")
                    results = xhr.getResponseHeader("X-result-count")
                    atom.notifications.addSuccess("Query found #{results} results in #{elapsed}s")
                )
            error: (xhr, status) ->
                clearTimeout(notifTimeout)
                self.updateStatus("")
                atom.notifications.addError("Query execution failed: #{status}",
                    { detail: xhr.responseText, dismissable: true })

    gotoDefinition: (signature, editor) ->
        if @gotoLocalDefinition(signature, editor)
            return

        params = util.modules(@projectConfig, editor, false)
        config = @projectConfig.getConfig(editor)
        self = this
        $.ajax
            url: config.server +
                "/apps/atom-editor/atom-autocomplete.xql?signature=" + encodeURIComponent(signature) + "&" +
                    params.join("&")
            username: config.user
            password: config.password
            success: (data) ->
                for item in data
                    if item.name == signature
                        path = item.path
                        if path.indexOf("xmldb:exist://") == 0
                            path = path.substring(path.indexOf("/db"))
                        self.open(editor, path, (newEditor) ->
                            self.gotoLocalDefinition(signature, newEditor)
                        )
                        return

    gotoLocalDefinition: (signature, editor) ->
        for item in util.parseLocalFunctions(editor)
            if item.name == signature
                editor.scrollToBufferPosition([item.line, 0])
                editor.setCursorBufferPosition([item.line, 0])
                return true
        false

    open: (editor, uri, onOpen) ->
        if editor.getBuffer()._remote?
            if uri.indexOf("xmldb:exist://") == 0
                uri = uri.substring(uri.indexOf("/db"))
            @treeView.open(path: uri, onOpen)
        else
            rootCol = "#{@projectConfig.getConfig(editor).root}/"
            xmldbRoot = "xmldb:exist://#{rootCol}"
            if uri.indexOf(xmldbRoot) is 0
                uri = uri.substring(xmldbRoot.length)
            else if uri.indexOf(rootCol) is 0
                uri = uri.substring(rootCol.length)
                projectPath = atom.project.relativizePath(editor.getPath())[0]
                uri = _path.resolve(projectPath, uri)

            console.log("opening file: %s", uri)
            promise = atom.workspace.open(uri)
            promise.then((newEditor) -> onOpen?(newEditor))

    updateStatus: (message) ->
        @statusMsg?.textContent = message

    provide: ->
        return @provider

    provideHyperclick: ->
        self = this
        providerName: 'hyperclick-xquery'
        getSuggestionForWord: (editor, text, range) ->
            def = XQUtils.getFunctionDefinition(editor, range.end)
            if def?
                return {
                    range: def.range,
                    callback: ->
                        self.gotoDefinition(def.signature, editor)
                }
            else
                console.log("no function found at cursor position: #{text}")

    provideLinter: ->
        provider =
            name: 'xqlint'
            grammarScopes: ['source.xq']
            scope: 'file'
            lintOnFly: true
            lint: (textEditor) =>
                return @lintOpenFile(textEditor)

    lintOpenFile: (editor) ->
        chunk = XQUtils.getText(editor)
        return [] unless chunk.text.length > 0 and @projectConfig

        collectionPaths = util.getCollectionPaths(editor, @projectConfig)
        self = this
        return new Promise (resolve) ->
            $.ajax
                type: "PUT"
                url: self.projectConfig.getConfig(editor).server + "/apps/atom-editor/compile.xql"
                dataType: "json"
                data: chunk.text
                headers:
                    "X-BasePath": collectionPaths.basePath
                contentType: "application/octet-stream"
                username: self.projectConfig.getConfig(editor).user
                password: self.projectConfig.getConfig(editor).password
                success: (data) ->
                    messages = []

                    if data.result == "fail"
                        error = self.parseErrMsg(data.error)
                        range = null
                        if error.line > -1
                            line = (error.line - chunk.prologOffset) + chunk.offset
                            end = editor.lineTextForBufferRow(line).length
                            range = new Range(
                                [line, error.column - 1],
                                [line, end - 1]
                            )
                        message = {
                            type: 'Error',
                            text: error.msg,
                            range: range,
                            filePath: editor.getPath()
                        }
                        messages.push(message)

                    if !chunk.isSnippet
                        xqlint = XQUtils.xqlint(editor)
                        markers = xqlint?.getWarnings()
                        for marker in markers
                            message = {
                                type: marker.type
                                text: marker.message
                                range: new Range([marker.pos.sl, marker.pos.sc], [marker.pos.el, marker.pos.ec])
                                filePath: editor.getPath()
                            }
                            messages.push(message)
                    resolve(messages)

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

    consumeStatusBar: (statusBar) ->
        statusContainer = document.createElement("span")
        statusContainer.className = "existdb-status inline-block"
        icon = document.createElement("span")
        icon.className = "icon icon-database"
        statusContainer.appendChild(icon)

        @statusMsg = document.createElement("span")
        @statusMsg.className ="status-message"
        @statusMsg.textContent = ""
        statusContainer.appendChild(@statusMsg)

        @statusBarTile = statusBar.addRightTile(item: statusContainer, priority: 100)
