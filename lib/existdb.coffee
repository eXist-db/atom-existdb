EXistSymbolsView = require './existdb-view'
EXistTreeView = require './existdb-tree-view'
Config = require './project-config'
{CompositeDisposable, Range} = require 'atom'
request = require 'request'
Provider = require "./provider"
WatcherControl = require "./watcher-control"
util = require "./util"
_path = require 'path'
cp = require 'child_process'
$ = require 'jquery'
XQUtils = require './xquery-helper'

COMPILE_MSG_RE = /.*line:?\s(\d+)/i

module.exports = Existdb =
    subscriptions: null
    projectConfig: null
    provider: undefined
    symbolsView: undefined
    treeView: undefined

    activate: (@state) ->
        console.log "Activating eXistdb"
        @projectConfig = new Config()

        @treeView = new EXistTreeView(@state, @projectConfig, @)

        @provider = new Provider(@projectConfig)

        @symbolsView = new EXistSymbolsView(@projectConfig, @)

        @watcherControl = new WatcherControl(@projectConfig, @)

        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable

        # Register command that toggles this view
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:run': => @run(atom.workspace.getActiveTextEditor())
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:file-symbols': => @gotoFileSymbol()
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
        connection = @projectConfig.getConnection(editor, @projectConfig.activeServer)
        options =
            uri: "#{connection.server}/apps/atom-editor/execute"
            method: "POST"
            qs: { "qu": chunk.text, "base": collectionPaths.basePath, "output": "adaptive", "count": 10 }
            auth:
                user: connection.user
                pass: connection.password || ""
                sendImmediately: true
        request(
            options,
            (error, response, body) =>
                clearTimeout(notifTimeout)
                @updateStatus("")
                if error? or response.statusCode != 200
                    html = $.parseXML(xhr.responseText)
                    message = $(html).find(".description").text()

                    atom.notifications.addError("Query execution failed: #{$(html).find(".message").text()} (#{status})",
                        { detail: message, dismissable: true })
                else
                    promise = atom.workspace.open("query-results", { split: "down", activatePane: false })
                    promise.then((newEditor) ->
                        grammar = atom.grammars.grammarForScopeName("text.xml")
                        newEditor.setGrammar(grammar)
                        newEditor.setText(body)
                        elapsed = response.headers["x-elapsed"]
                        results = response.headers["x-result-count"]
                        atom.notifications.addSuccess("Query found #{results} results in #{elapsed}s")
                    )
        )

    gotoDefinition: (signature, editor) ->
        if @gotoLocalDefinition(signature, editor)
            return

        params = util.modules(@projectConfig, editor, false)
        id = editor.getBuffer().getId()
        console.log("getting definitions for %s", id)
        if id.startsWith("exist:")
            connection = @projectConfig.getConnection(id)
        else
            connection = @projectConfig.getConnection(editor)

        self = this
        $.ajax
            url: connection.server +
                "/apps/atom-editor/atom-autocomplete.xql?signature=" + encodeURIComponent(signature) + "&" +
                    params.join("&")
            username: connection.user
            password: connection.password
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
            @treeView.open(path: uri, util.parseURI(editor.getBuffer().getId()).server, onOpen)
        else
            rootCol = "#{@projectConfig.getConnection(editor).sync.root}/"
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
            id = editor.getBuffer().getId()
            if id.startsWith("exist:")
                connection = self.projectConfig.getConnection(id)
            else
                connection = self.projectConfig.getConnection(editor)
            $.ajax
                type: "PUT"
                url: connection.server + "/apps/atom-editor/compile.xql"
                dataType: "json"
                data: chunk.text
                headers:
                    "X-BasePath": collectionPaths.basePath
                contentType: "application/octet-stream"
                username: connection.user
                password: connection.password
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
                        errors = xqlint?.getErrors()
                        if errors? and errors.length > 0
                            console.log("errors: %o", errors)
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
        @statusMsg.className ="status-message badge badge-info"
        @statusMsg.textContent = ""
        statusContainer.appendChild(@statusMsg)

        @statusBarTile = statusBar.addRightTile(item: statusContainer, priority: 100)
