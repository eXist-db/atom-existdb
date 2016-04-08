{$, jQuery, View} = require "atom-space-pen-views"
{TreeView} = require "./tree-view"
XQUtils = require './xquery-helper'
Dialog = require './dialog'
request = require 'request'
path = require 'path'
fs = require 'fs'
tmp = require 'tmp'
mkdirp = require 'mkdirp'
{CompositeDisposable} = require 'atom'
mime = require 'mime'

module.exports =
    class EXistTreeView extends View

        @content: ->
            @div class: "existdb-tree"

        @tmpDir: null

        initialize: (@state, @config, @main) ->
            mime.define({
                "application/xquery": ["xq", "xql", "xquery", "xqm"]
            })

            atom.workspace.observeTextEditors((editor) =>
                buffer = editor.getBuffer()
                p = buffer.getId()
                console.log("checking buffer %s", p)
                match = /^((?:http|https):\/\/.*?)(\/db.*)$/.exec(p)
                if  match and not buffer._remote?
                    server = match[1]
                    p = match[2]
                    console.log("Reopen %s from database %s", p, server)
                    editor.destroy()
                    @open(path: p, buffer)
            )

            @disposables = new CompositeDisposable()
            @treeView = new TreeView

            @append(@treeView)

            atom.config.observe 'existdb-tree-view.scrollAnimation', (enabled) =>
                @animationDuration = if enabled then 300 else 0
            atom.config.onDidChange('existdb.server', (ev) => @checkServer(() => @populate()))
            atom.config.onDidChange('existdb.user', (ev) => @checkServer(() => @populate()))
            atom.config.onDidChange('existdb.password', (ev) => @checkServer(() => @populate()))
            atom.config.onDidChange('existdb.root', (ev) => @checkServer(() => @populate()))

            @treeView.width(@state.width) if @state?.width
            @toggle() if @state?.show

            @disposables.add atom.commands.add 'atom-workspace', 'existdb:reindex':
                (ev) => @reindex(ev.target.spacePenView)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:reload-tree-view':
                (ev) => @load(ev.target.spacePenView.item)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:new-file':
                (ev) => @newFile(ev.target.spacePenView)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:new-collection':
                (ev) => @newCollection(ev.target.spacePenView)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:remove-resource':
                (ev) =>
                    selection = @treeView.getSelected()
                    if selection? and selection.length > 0
                        @removeResource(selection)
                    else
                        @removeResource([ev.target.spacePenView])
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:reconnect': => @checkServer(() => @populate())
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:upload-current': =>
                @uploadCurrent()
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:upload-selected': =>
                @uploadSelected()

        serialize: ->
            width: @treeView.width()
            show: @hasParent()

        populate: ->
            root = {
                label: "db",
                path: "/db",
                icon: "icon-database",
                type: "collection",
                children: [],
                loaded: true
            }
            @treeView.setRoot(root, false)
            @checkServer(() => @load(root))

        load: (item, callback) =>
            console.log("Loading collection contents for item #{item.path} using server #{@config.getConfig(editor).server}")
            self = this
            editor = atom.workspace.getActiveTextEditor()
            url = @config.getConfig(editor).server +
                "/apps/atom-editor/browse.xql?root=" + item.path
            options =
                uri: url
                method: "GET"
                json: true
                auth:
                    user: @config.getConfig(editor).user
                    pass: @config.getConfig(editor).password || ""
                    sendImmediately: true
            request(
                options,
                (error, response, body) ->
                    if error? or response.statusCode != 200
                        atom.notifications.addWarning("Failed to load database contents", detail: if response? then response.statusMessage else error)
                    else
                        item.view.setChildren(body)
                        for child in body
                            child.view.onSelect(self.onSelect)
                            child.view.onDblClick(self.onDblClick)
                        callback() if callback
            )

        removeResource: (selection) =>
            message = if selection.length == 1 then "resource #{selection[0].item.path}" else "#{selection.length} resources"
            atom.confirm
                message: "Delete resource?"
                detailedMessage: "Are you sure you want to delete #{message}?"
                buttons:
                    Yes: =>
                        editor = atom.workspace.getActiveTextEditor()
                        for item in selection
                            @doRemove(editor, item.item)
                    No: null

        doRemove: (editor, resource) =>
            url = "#{@config.getConfig(editor).server}/rest/#{resource.path}"
            options =
                uri: url
                method: "DELETE"
                auth:
                    user: @config.getConfig(editor).user
                    pass: @config.getConfig(editor).password || ""
                    sendImmediately: true
            @main.updateStatus("Deleting #{resource.path}...")
            request(
                options,
                (error, response, body) =>
                    if error?
                        atom.notifications.addError("Failed to delete #{resource.path}", detail: if response? then response.statusMessage else error)
                    else
                        @main.updateStatus("")
                        resource.view.delete()
            )

        newFile: (parentView) =>
            dialog = new Dialog("Enter a name for the new resource:", null, (name) => @createFile(parentView, name) if name?)
            dialog.attach()

        newCollection: (parentView) =>
            parent = parentView.item.path
            dialog = new Dialog("Enter a name for the new collection:", null, (name) =>
                if name?
                    query = "xmldb:create-collection('#{parent}', '#{name}')"
                    @runQuery(query,
                        (error, response) ->
                            atom.notifications.addError("Failed to create collection #{parent}/#{name}", detail: if response? then response.statusMessage else error)
                        (body) =>
                            atom.notifications.addSuccess("Collection #{parent}/#{name} created")
                            collection = {
                                path: "#{parent}/#{name}"
                                label: name
                                loaded: true
                                type: "collection"
                                icon: "icon-file-directory"
                            }
                            parentView.addChild(collection)
                            collection.view.onSelect(@onSelect)
                            collection.view.onDblClick(@onDblClick)
                    )
            )
            dialog.attach()

        createFile: (parentView, name) ->
            self = this
            collection = parentView.item.path
            resource =
                path: "#{collection}/#{name}"
                type: "resource"
                icon: "icon-file-text"
                label: name
                loaded: true
            tmpDir = @getTempDir(resource.path)
            tmpFile = path.join(tmpDir, path.basename(resource.path))

            promise = atom.workspace.open(null)
            promise.then((newEditor) ->
                parentView.addChild(resource)
                resource.view.onSelect(self.onSelect)
                resource.view.onDblClick(self.onDblClick)
                buffer = newEditor.getBuffer()
                # buffer.getPath = () -> resource.path
                buffer.setPath(tmpFile)
                resource.editor = newEditor
                buffer._remote = resource
                onDidSave = buffer.onDidSave((ev) ->
                    self.save(tmpFile, resource, mime.lookup(resource.path))
                )
                onDidDestroy = buffer.onDidDestroy((ev) ->
                    self.disposables.remove(onDidSave)
                    self.disposables.remove(onDidDestroy)
                    onDidDestroy.dispose()
                    onDidSave.dispose()
                    fs.unlink(tmpFile)
                )
                self.disposables.add(onDidSave)
                self.disposables.add(onDidDestroy)
            )

        open: (resource, onOpen) =>
            # switch to existing editor if resource is already open
            editor = @getOpenEditor(resource)
            if editor?
                pane = atom.workspace.paneForItem(editor)
                pane.activateItem(editor)
                onOpen?(editor)
                return

            self = this
            editor = atom.workspace.getActiveTextEditor()
            url = @config.getConfig(editor).server + "/apps/atom-editor/load.xql?path=" + resource.path
            tmpDir = @getTempDir(resource.path)
            tmpFile = path.join(tmpDir, path.basename(resource.path))
            @main.updateStatus("Opening #{resource.path} ...")
            console.log("Downloading %s to %s", resource.path, tmpFile)
            stream = fs.createWriteStream(tmpFile)
            options =
                uri: url
                method: "GET"
                auth:
                    user: @config.getConfig(editor).user
                    pass: @config.getConfig(editor).password || ""
                    sendImmediately: true
            contentType = null
            request(options)
                .on("response", (response) ->
                    contentType = response.headers["content-type"]
                )
                .on("error", (err) ->
                    self.main.updateStatus("")
                    atom.notifications.addError("Failed to download #{resource.path}", detail: err)
                )
                .on("end", () ->
                    self.main.updateStatus("")
                    promise = atom.workspace.open(null)
                    promise.then((newEditor) ->
                        buffer = newEditor.getBuffer()
                        # buffer.getPath = () -> resource.path
                        buffer.setPath(tmpFile)
                        buffer.getId = () => self.getXMLDBUri(editor, resource.path)
                        buffer.loadSync()
                        resource.editor = newEditor
                        buffer._remote = resource
                        onDidSave = buffer.onDidSave((ev) ->
                            self.save(tmpFile, resource, contentType)
                        )
                        onDidDestroy = buffer.onDidDestroy((ev) ->
                            self.disposables.remove(onDidSave)
                            self.disposables.remove(onDidDestroy)
                            onDidDestroy.dispose()
                            onDidSave.dispose()
                            fs.unlink(tmpFile)
                        )
                        self.disposables.add(onDidSave)
                        self.disposables.add(onDidDestroy)
                        XQUtils.xqlint(newEditor)
                        onOpen?(newEditor)
                    )
                )
                .pipe(stream)

        getXMLDBUri: (editor, path) ->
            return "#{@config.getConfig(editor).server}#{path}"

        getOpenEditor: (resource) ->
            for editor in atom.workspace.getTextEditors()
                if editor.getBuffer()._remote?.path == resource.path
                    return editor
            return null

        save: (file, resource, contentType, onSuccess) ->
            editor = atom.workspace.getActiveTextEditor()
            url = "#{@config.getConfig(editor).server}/rest/#{resource.path}"
            contentType = mime.lookup(path.extname(file)) unless contentType
            console.log("Saving %s using content type %s", resource.path, contentType)
            @main.updateStatus("Uploading ...")
            self = this
            options =
                uri: url
                method: "PUT"
                auth:
                    user: @config.getConfig(editor).user
                    pass: @config.getConfig(editor).password || ""
                    sendImmediately: true
                headers:
                    "Content-Type": contentType
            fs.createReadStream(file).pipe(
                request(
                    options,
                    (error, response, body) ->
                        if error?
                            atom.notifications.addError("Failed to upload #{resource.path}", detail: error)
                        else
                            self.main.updateStatus("")
                            onSuccess?()
                )
            )

        uploadCurrent: () =>
            selected = @treeView.getSelected()
            if selected.length != 1 or selected[0].item.type == "resource"
                atom.notifications.addError("Please select a single target collection for the upload in the database tree view")
                return
            editor = atom.workspace.getActiveTextEditor()
            fileName = path.basename(editor.getPath())
            @save(editor.getPath(), path: "#{selected[0].item.path}/#{fileName}", null, () => @load(selected[0].item))

        uploadSelected: () ->
            locals =
                $('.tree-view .selected').map(() ->
                    if this.getPath? then this.getPath() else ''
                ).get();
            if locals? and locals.length > 0
                selected = @treeView.getSelected()
                if selected.length != 1 or selected[0].item.type == "resource"
                    atom.notifications.addError("Please select a single target collection for the upload in the database tree view")
                    return
                for file in locals
                    fileName = path.basename(file)
                    @save(file, path: "#{selected[0].item.path}/#{fileName}", null, () =>
                        @load(selected[0].item)
                    )

        reindex: (parentView) ->
            query = "xmldb:reindex('#{parentView.item.path}')"
            @runQuery(query,
                (error, response) ->
                    atom.notifications.addError("Failed to reindex collection #{parentView.item.path}", detail: if response? then response.statusMessage else error)
                (body) ->
                    atom.notifications.addSuccess("Collection #{parentView.item.path} reindexed")
            )

        onSelect: ({node, item}) =>
            if not item.loaded
                @load(item, () ->
                    item.loaded = true
                    item.view.toggleClass('collapsed')
                )
            else
                item.view.setSelected(true)

        onDblClick: ({node, item}) =>
            if item.type == "resource"
                @open(item)
            else
                node.setCollapsed()
                node.clearSelection()

        destroy: ->
            @element.remove()
            @disposables.dispose()
            @tempDir.removeCallback() if @tempDir

        attach: =>
            if (atom.config.get('tree-view.showOnRightSide'))
                @panel = atom.workspace.addLeftPanel(item: this)
            else
                @panel = atom.workspace.addRightPanel(item: this)

        remove: ->
          super
          @panel.destroy()

        # Toggle the visibility of this view
        toggle: ->
          if @hasParent()
            @remove()
          else
            @populate()
            @attach()

        # Show view if hidden
        showView: ->
          if not @hasParent()
            @populate()
            @attach()

        # Hide view if visisble
        hideView: ->
          if @hasParent()
            @remove()

        getTempDir: (uri) ->
            @tempDir = tmp.dirSync({ mode: 0o750, prefix: 'atom-exist_', unsafeCleanup: true }) unless @tempDir
            tmpPath = path.join(fs.realpathSync(@tempDir.name), path.dirname(uri))
            mkdirp.sync(tmpPath)
            return tmpPath

        runQuery: (query, onError, onSuccess) =>
            editor = atom.workspace.getActiveTextEditor()
            url = "#{@config.getConfig(editor).server}/rest/db?_query=#{query}&_wrap=no"
            options =
                uri: url
                method: "GET"
                json: true
                auth:
                    user: @config.getConfig(editor).user
                    pass: @config.getConfig(editor).password || ""
                    sendImmediately: true
            request(
                options,
                (error, response, body) =>
                    if error? or response.statusCode != 200
                        onError?(error, response)
                    else
                        onSuccess?(body)
            )

        checkServer: (onSuccess) =>
            query = "'http://exist-db.org/apps/atom-editor' = repo:list()"
            @runQuery(query,
                (error, response) ->
                    atom.notifications.addWarning("Failed to access database", detail: if response? then response.statusMessage else error)
                (body) =>
                    if body
                        onSuccess?()
                    else
                        console.log("server-side support app is not installed")
                        atom.confirm
                            message: "Install server-side support app?"
                            detailedMessage: "This package requires a small support app to be installed on the eXistdb server. Do you want to install it?"
                            buttons:
                                Yes: =>
                                    query = "repo:install-and-deploy('http://exist-db.org/apps/atom-editor', 'http://demo.exist-db.org/exist/apps/public-repo/modules/find.xql')"
                                    @runQuery(query,
                                        (error, response) ->
                                            atom.notifications.addError("Failed to install support app", detail: if response? then response.statusMessage else error)
                                        (body) ->
                                            onSuccess?()
                                    )
                                No: -> null
            )
