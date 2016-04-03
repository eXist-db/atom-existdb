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

        initialize: (@state, @config) ->
            mime.define({
                "application/xquery": ["xq", "xql", "xquery", "xqm"]
            })

            atom.workspace.observeTextEditors((editor) =>
                buffer = editor.getBuffer()
                p = buffer.getId()
                if /^xmldb:exist:\/\/\/db\/.*/.test(p) and not buffer._remote?
                    p = p.substring(14)
                    console.log("Reopen %s from database", p)
                    editor.destroy()
                    @open(path: p, buffer)
            )

            @disposables = new CompositeDisposable()
            @treeView = new TreeView

            @treeView.onSelect ({node, item}) ->
                console.log("Selected %o", item)

            @append(@treeView)

            atom.config.observe 'existdb-tree-view.scrollAnimation', (enabled) =>
                @animationDuration = if enabled then 300 else 0

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
                (ev) => @removeResource(ev.target.spacePenView)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:reconnect': => @checkServer(() => @populate())

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
            console.log("Loading collection contents for item #{item.path}")
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
                        callback() if callback
            )

        removeResource: (parentView) =>
            resource = parentView.item
            atom.confirm
                message: "Delete resource?"
                detailedMessage: "Are you sure you want to delete resource #{resource.path}?"
                buttons:
                    Yes: =>
                        editor = atom.workspace.getActiveTextEditor()
                        url = "#{@config.getConfig(editor).server}/rest/#{resource.path}"
                        options =
                            uri: url
                            method: "DELETE"
                            auth:
                                user: @config.getConfig(editor).user
                                pass: @config.getConfig(editor).password || ""
                                sendImmediately: true
                        request(
                            options,
                            (error, response, body) ->
                                if error?
                                    atom.notifications.addError("Failed to delete #{resource.path}", detail: if response? then response.statusMessage else error)
                                else
                                    atom.notifications.addSuccess("#{resource.path} deleted")
                                    parentView.delete()
                        )
                    No: null

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
                        (body) ->
                            atom.notifications.addSuccess("Collection #{parent}/#{name} created")
                            parentView.addChild({
                                path: "#{parent}/#{name}"
                                label: name
                                loaded: true
                                type: "collection"
                                icon: "icon-file-directory"
                            })
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
            pane = atom.workspace.paneForURI(resource.path)
            if pane?
                pane.activateItemForURI(resource.path)
                onOpen?(atom.workspace.getActiveTextEditor())
                return

            self = this
            editor = atom.workspace.getActiveTextEditor()
            url = @config.getConfig(editor).server + "/apps/atom-editor/load.xql?path=" + resource.path
            tmpDir = @getTempDir(resource.path)
            tmpFile = path.join(tmpDir, path.basename(resource.path))
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
                    atom.notifications.addError("Failed to download #{resource.path}", detail: err)
                )
                .on("end", () ->
                    promise = atom.workspace.open(null)
                    promise.then((newEditor) ->
                        buffer = newEditor.getBuffer()
                        # buffer.getPath = () -> resource.path
                        buffer.setPath(tmpFile)
                        buffer.getId = () -> "xmldb:exist://#{resource.path}"
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

        getOpenEditor: (resource) ->
            for editor in atom.workspace.getTextEditors()
                if editor.getBuffer()._remote?.path == resource.path
                    return editor
            return null

        save: (file, resource, contentType) ->
            editor = atom.workspace.getActiveTextEditor()
            url = "#{@config.getConfig(editor).server}/rest/#{resource.path}"
            contentType = mime.lookup(path.extname(file)) unless contentType
            console.log("Saving %s using content type %s", resource.path, contentType)
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
                            atom.notifications.addSuccess("Uploaded #{resource.path}: #{response.statusCode}.")
                )
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
            else if item.type == "resource"
                @open(item)

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
            tmpPath = path.join(@tempDir.name, path.dirname(uri))
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
