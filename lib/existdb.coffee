EXistSymbolsView = require './existdb-view'
EXistTreeView = require './existdb-tree-view'
Config = require './project-config'
{CompositeDisposable, Range, Emitter} = require 'atom'
request = require 'request'
Provider = require "./provider"
WatcherControl = require "./watcher-control"
util = require "./util"
_path = require 'path'
cp = require 'child_process'
$ = require 'jquery'
XQUtils = require './xquery-helper'
InScopeVariables = require './var-visitor'
VariableReferences = require './ref-visitor'

COMPILE_MSG_RE = /.*line:?\s(\d+)/i

module.exports = Existdb =
    subscriptions: null
    projectConfig: null
    provider: undefined
    symbolsView: undefined
    treeView: undefined

    startTagMarker: undefined
    endTagMarker: undefined

    activate: (@state) ->
        console.log "Activating eXistdb"
        @emitter = new Emitter()

        @projectConfig = new Config()

        @watcherControl = new WatcherControl(@projectConfig, @)

        @treeView = new EXistTreeView(@state, @projectConfig, @)

        @provider = new Provider(@projectConfig)

        @symbolsView = new EXistSymbolsView(@projectConfig, @)

        # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
        @subscriptions = new CompositeDisposable()
        @tagSubscriptions = new CompositeDisposable()
        
        # @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:sync-project': =>
        #     p = $('.tree-view .selected').map(() ->
        #         if this.getPath? then this.getPath() else ''
        #     ).get()[0]
        #     console.log("sync: %o", p)
        #     conf = @projectConfig.getProjectConfig(p)
        #     @watcherControl.sync(conf) if conf?
            
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:run': => @run(atom.workspace.getActiveTextEditor())
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:file-symbols': => @gotoFileSymbol()
        @subscriptions.add atom.commands.add 'atom-workspace', 'existdb:toggle-tree-view': => @treeView.toggle()
        @subscriptions.add atom.commands.add 'atom-text-editor[data-grammar="source xq"]', 'existdb:rename-variable': @renameVariable
        @subscriptions.add atom.commands.add 'atom-text-editor[data-grammar="source xq"]', 'existdb:expand-selection': @expandSelection
        @subscriptions.add atom.commands.add 'atom-text-editor[data-grammar="source xq"]', 'existdb:goto-definition': =>
            editor = atom.workspace.getActiveTextEditor()
            pos = editor.getCursorBufferPosition()
            scope = editor.scopeDescriptorForBufferPosition(pos)
            if scope.getScopesArray().indexOf("meta.definition.variable.name.xquery") > -1
                ast = editor.getBuffer()._ast
                return unless ast?

                def = XQUtils.findNode(ast, { line: pos.row, col: pos.column })
                if def?
                    parent = def.getParent
                    if parent.name == "VarRef" or parent.name == "VarName"
                        @gotoVarDefinition(parent, editor)
            else
                def = XQUtils.getFunctionDefinition(editor, pos)
                @gotoDefinition(def.signature, editor) if def?

        @tooltips = new CompositeDisposable

        atom.workspace.observeTextEditors((editor) =>
            editor.onDidChangeCursorPosition((ev) =>
                return if @editTag(editor, ev)
                @markInScopeVars(editor, ev)
            )
            editor.getBuffer().onDidChange((ev) =>
                @closeTag(ev)
                editor.getBuffer()._ast = null
            )
        )
        @emitter.emit("activated")

    deactivate: ->
        @watcherControl.destroy()
        @projectConfig.destroy()
        @subscriptions.dispose()
        @symbolsView.destroy()
        @treeView.destroy()
        @statusBarTile?.destroy()
        @statusBarTile = null
        @emitter.dispose()
        @tooltips.dispose()
        @startTagMarker.destroy() if @startTagMarker?
        @endTagMarker.destroy() if @endTagMarker?

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
            strictSSL: false
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
                    html = $.parseXML(body)
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
        console.log("getting definitions for %s", signature)
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
                name = if signature.charAt(0) == "$" then signature.substring(1) else signature
                for item in data
                    if item.name == name
                        path = item.path
                        if path.indexOf("xmldb:exist://") == 0
                            path = path.substring(path.indexOf("/db"))
                        console.log("Loading %s", path)
                        self.open(editor, path, (newEditor) ->
                            self.gotoLocalDefinition(name, newEditor)
                        )
                        return

    gotoLocalDefinition: (signature, editor) ->
        signature = if signature.charAt(0) == "$" then signature.substring(1) else signature
        for item in util.parseLocalFunctions(editor)
            if item.name == signature
                editor.scrollToBufferPosition([item.line, 0])
                editor.setCursorBufferPosition([item.line, 0])
                return true
        false

    gotoVarDefinition: (reference, editor) ->
        varName = XQUtils.getValue(reference)
        name = varName.substring(1) if varName.charAt(0) == "$"
        def = XQUtils.getVariableDef(name, reference)
        if def?
            editor.scrollToBufferPosition([def.pos.sl, 0])
            editor.setCursorBufferPosition([def.pos.sl, def.pos.sc])
        else
            varName = if varName.charAt(0) == "$" then varName else "$#{varName}"
            @gotoDefinition(varName, editor)

    open: (editor, uri, onOpen) ->
        if editor.getBuffer()._remote?
            if uri.indexOf("xmldb:exist://") == 0
                uri = uri.substring(uri.indexOf("/db"))
            @treeView.open(path: uri, util.parseURI(editor.getBuffer().getId()).server, onOpen)
        else
            rootCol = "#{@projectConfig.getConfig(editor).sync.root}/"
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

    closeTag: (ev) ->
        editor = atom.workspace.getActiveTextEditor()
        return unless editor? and ev.newText == '/' and editor.getBuffer()._ast?

        grammar = editor.getGrammar()
        return unless grammar.scopeName == "source.xq"

        cursorPos = editor.getLastCursor().getBufferPosition()
        translatedPos = cursorPos.translate([0, -2])
        lastTwo = editor.getTextInBufferRange([translatedPos, cursorPos])
        return unless lastTwo == '</'

        node = XQUtils.findNode(editor.getBuffer()._ast, { line: ev.oldRange.start.row, col: ev.oldRange.start.column })

        return unless node?
        constructor = XQUtils.getAncestor("DirElemConstructor", node)
        while constructor?
            qname = XQUtils.findChild(constructor, "QName")
            if qname?
                editor.insertText(qname.value + ">")
                break
            constructor = XQUtils.getAncestor("DirElemConstructor", constructor)

    editTag: (editor, ev) =>
        reset = =>
            # clear markers
            @tagSubscriptions.dispose()
            @startTagMarker.destroy()
            @endTagMarker.destroy()
            @startTagMarker = null
            @endTagMarker = null
            @inTag = false
            false

        pos = ev.cursor.getBufferPosition()
        if @inTag and !(@startTagMarker.getBufferRange().containsPoint(pos) or @endTagMarker.getBufferRange().containsPoint(pos))
            reset()

        return false if @inTag
        return false unless editor.getGrammar().scopeName == "source.xq" and editor.getBuffer()._ast?
        return false if editor.hasMultipleCursors()
        selRange = editor.getSelectedBufferRange()
        return false unless selRange.isEmpty()
        self = this
        node = XQUtils.findNode(editor.getBuffer()._ast, { line: pos.row, col: pos.column })
        return unless node?
        if node.name == "QName" and node.getParent?.name == "DirElemConstructor"
            tags = XQUtils.findChildren(node.getParent, "QName")
            if tags? and tags.length == 2 and tags[0].value == tags[1].value
                @inTag = true
                @startTagMarker = editor.markBufferRange(new Range([tags[0].pos.sl, tags[0].pos.sc], [tags[0].pos.el, tags[0].pos.ec]))
                @endTagMarker = editor.markBufferRange(new Range([tags[1].pos.sl, tags[1].pos.sc], [tags[1].pos.el, tags[1].pos.ec]))
                @tagSubscriptions = new CompositeDisposable()
                inChange = false
                @tagSubscriptions.add(@startTagMarker.onDidChange((ev) =>
                    return if inChange
                    newTag = editor.getTextInBufferRange(@startTagMarker.getBufferRange())
                    # if whitespace was added: starting attribute list: reset
                    return reset() if /^\w+\s+/.test(newTag)

                    inChange = true
                    editor.setTextInBufferRange(@endTagMarker.getBufferRange(), newTag)
                    inChange = false
                ))
                @tagSubscriptions.add(@endTagMarker.onDidChange((ev) =>
                    return if inChange
                    newTag = editor.getTextInBufferRange(@endTagMarker.getBufferRange())
                    inChange = true
                    editor.setTextInBufferRange(@startTagMarker.getBufferRange(), newTag)
                    inChange = false
                ))
        return false

    markInScopeVars: (editor, ev) ->
        return unless editor.getGrammar().scopeName == "source.xq" and editor.getBuffer()._ast?

        selRange = editor.getSelectedBufferRange()
        return unless selRange.isEmpty()
        for decoration in editor.getDecorations(class: "var-reference")
            marker = decoration.getMarker()
            marker.destroy()

        scope = editor.scopeDescriptorForBufferPosition(ev.newBufferPosition)
        if scope.getScopesArray().indexOf("meta.definition.variable.name.xquery") > -1

            ast = editor.getBuffer()._ast
            return unless ast?

            node = XQUtils.findNode(ast, { line: ev.newBufferPosition.row, col: ev.newBufferPosition.column })
            if node?
                varName = node.value
                parent = node.getParent
                if parent.name in ["VarRef", "VarName", "Param"]
                    scope = XQUtils.getVariableScope(varName, parent)
                    # it might be a global variable, so scan the entire ast if scope is not set
                    scope ?= ast

                    visitor = new VariableReferences(node, scope)
                    vars = visitor.getReferences()
                    if vars?
                        for v in vars when v.name == varName
                            marker = editor.markBufferRange(v.range, persistent: false)
                            editor.decorateMarker(marker, type: "highlight", class: "var-reference")

    renameVariable: () ->
        editor = atom.workspace.getActiveTextEditor()
        for decoration in editor.getDecorations(class: "var-reference")
            marker = decoration.getMarker()
            editor.addSelectionForBufferRange(marker.getBufferRange())

    expandSelection: () ->
        editor = atom.workspace.getActiveTextEditor()
        ast = editor.getBuffer()._ast
        return unless ast?

        selRange = editor.getSelectedBufferRange()
        # try to determine the ast node where the cursor is located
        if selRange.isEmpty()
            astNode = XQUtils.findNode(ast, { line: selRange.start.row, col: selRange.start.column })
            expand = false
        else
            astNode = XQUtils.findNodeForRange(ast, { line: selRange.start.row, col: selRange.start.column },
                { line: selRange.end.row, col: selRange.end.column })
            expand = true

        if astNode
            if expand
                parent = astNode.getParent
                while parent and (XQUtils.samePosition(astNode.pos, parent.pos) or parent.name in ["StatementsAndOptionalExpr", "LetBinding", "FunctionDecl"])
                    parent = parent.getParent
            else
                parent = astNode
            if parent?
                if parent.name == "AnnotatedDecl"
                    p = parent.getParent.children.indexOf(parent)
                    separator = parent.getParent.children[p + 1]
                    range = new Range([parent.pos.sl, parent.pos.sc], [separator.pos.el, separator.pos.ec])
                else
                    range = new Range([parent.pos.sl, parent.pos.sc], [parent.pos.el, parent.pos.ec])

                editor.setSelectedBufferRange(range)

    provide: ->
        return @provider

    provideHyperclick: ->
        self = this
        providerName: 'hyperclick-xquery'
        getSuggestionForWord: (editor, text, range) ->
            scope = editor.scopeDescriptorForBufferPosition(range.start)
            if scope.getScopesArray().indexOf("meta.definition.variable.name.xquery") > -1
                ast = editor.getBuffer()._ast
                return unless ast?

                def = XQUtils.findNode(ast, { line: range.start.row, col: range.start.column })
                if def?
                    parent = def.getParent
                    if parent.name == "VarRef" or parent.name == "VarName"
                        return {
                            range: new Range([parent.pos.sl, parent.pos.sc], [parent.pos.el, parent.pos.ec]),
                            callback: ->
                                self.gotoVarDefinition(parent, editor)
                        }
            else
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
            messages = []
            self.xqlint(editor, chunk, messages)
            id = editor.getBuffer().getId()
            if id.startsWith("exist:")
                connection = self.projectConfig.getConnection(id)
            else
                connection = self.projectConfig.getConnection(editor, self.treeView.getActiveServer())
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
                error: (xhr, status) ->
                    resolve(messages)
                success: (data) ->
                    if data.result == "fail"
                        error = self.parseErrMsg(data.error)
                        range = null
                        if error.line > -1
                            line = (error.line - chunk.prologOffset) + chunk.offset
                            text = editor.lineTextForBufferRow(line)
                            if (text?)
                                end = text.length
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

                    resolve(messages)

    xqlint: (editor, chunk, messages) ->
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
        statusContainer = document.createElement("div")
        statusContainer.className = "existdb-status inline-block"

        icon = document.createElement("span")
        icon.className = "existdb-sync icon icon-cloud-upload"
        @tooltips.add atom.tooltips.add(icon, {title: "Database sync active"})
        statusContainer.appendChild(icon)

        @statusMsg = document.createElement("span")
        @statusMsg.className ="status-message badge badge-info icon icon-database"
        @statusMsg.textContent = ""
        statusContainer.appendChild(@statusMsg)

        @emitter.on("activated", () =>
            @watcherControl.on("status", (message) ->
                @statusMsg?.textContent = message
                if message == ""
                    $(".existdb-sync").removeClass("status-added")
                else
                    $(".existdb-sync").addClass("status-added")
            )
            @watcherControl.on("activate", (endpoint) ->
                $(icon).show()
            )
            @watcherControl.on("deactivate", (endpoint) ->
                $(icon).hide()
            )
        )

        @statusBarTile = statusBar.addRightTile(item: statusContainer, priority: 100)
