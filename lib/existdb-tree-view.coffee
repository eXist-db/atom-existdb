TreeView = require "./tree-view.js"
XQUtils = require './xquery-helper'
{dialog} = require './dialog.js'
# EXistEditor = require './editor'
request = require 'request'
path = require 'path'
fs = require 'fs'
tmp = require 'tmp'
mkdirp = require 'mkdirp'
{CompositeDisposable, Emitter} = require 'atom'
mime = require 'mime'
{exec} = require('child_process')
Shell = require('shell')

module.exports =
    class EXistTreeView extends Emitter

        @tmpDir: null

        constructor: (@state, @config) ->
            super
            mime.define({
                "application/xquery": ["xq", "xql", "xquery", "xqm"],
                "application/xml": ["odd", "xconf", "tei"]
            })

            atom.packages.activatePackage('tree-view').then((pkg) =>
                @fileTree = pkg.mainModule.getTreeViewInstance()
            )

            atom.workspace.observeTextEditors((editor) =>
                buffer = editor.getBuffer()
                p = buffer.getId()
                match = /^exist:\/\/(.*?)(\/db.*)$/.exec(p)
                if  match and not buffer._remote?
                    server = match[1]
                    p = match[2]
                    console.log("Reopen %s from database %s", p, server)
                    editor.destroy()
                    @open(path: p, server)
            )

            @disposables = new CompositeDisposable()

            @element = document.createElement("div")
            @element.classList.add("existdb-tree", "block", "tool-panel", "focusable-panel")
            @select = document.createElement("select")
            @select.classList.add("existdb-database-select")
            @element.appendChild(@select)

            @treeView = new TreeView()
            @element.appendChild(@treeView.element)

            @initServerList()
            @config.activeServer = @getActiveServer()
            @select.addEventListener('change', =>
                @populate()
                @config.activeServer = @getActiveServer()
            )
            @config.onConfigChanged(([configs, globalConfig]) =>
                @initServerList()
                @checkServer(() => @populate())
            )

            atom.config.observe 'existdb-tree-view.scrollAnimation', (enabled) =>
                @animationDuration = if enabled then 300 else 0
            atom.config.onDidChange('existdb.server', (ev) => @checkServer(() => @populate()))
            atom.config.onDidChange('existdb.user', (ev) => @checkServer(() => @populate()))
            atom.config.onDidChange('existdb.password', (ev) => @checkServer(() => @populate()))
            atom.config.onDidChange('existdb.root', (ev) => @checkServer(() => @populate()))

            # @disposables.add atom.workspace.addOpener (uri) ->
            #     if uri.startsWith "xmldb:exist:"
            #         new EXistEditor()

            @toggle() if @state?.show

            @disposables.add atom.commands.add 'atom-workspace', 'existdb:reindex':
                (ev) => @reindex(ev.target.item)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:reload-tree-view':
                (ev) => @load(ev.target.item)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:new-file':
                (ev) => @newFile(ev.target.item)
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:new-collection':
                (ev) => @newCollection(ev.target.item)
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
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:deploy': @deploy
            @disposables.add atom.commands.add 'atom-workspace', 'existdb:open-in-browser': @openInBrowser
            # @disposables.add atom.commands.add 'atom-workspace', 'existdb:sync':
            #     (ev) => @sync(ev.target.spacePenView)
            @populate()

        getDefaultLocation: () => 'right'

        getAllowedLocations: () => ['left', 'right']

        getURI: () -> 'atom:existdb/tree-view'

        getTitle: () -> 'eXist Database'

        hasParent: () ->
            @element.parentNode?

        # Toggle the visibility of this view
        toggle: ->
            atom.workspace.toggle(this)

        initServerList: ()->
            configs = @config.getConfig()
            @select.innerHTML = ""
            for name, config of configs.servers
                option = document.createElement("option")
                option.value = name
                option.title = config.server
                if name == @state?.activeServer
                    option.selected = true
                option.appendChild(document.createTextNode(name))
                @select.appendChild(option)

        getActiveServer: ->
            @select.options[@select.selectedIndex].value

        serialize: ->
            show: @hasParent()
            activeServer: @getActiveServer()

        populate: =>
            root = {
                label: "db",
                path: "/db",
                icon: "icon-database",
                type: "collection",
                children: [],
                loaded: true
            }
            console.log("populating %o", root)
            @treeView.setRoot(root, false)
            @checkServer(() => @load(root))

        load: (item, callback) =>
            self = this
            connection = @config.getConnection(null, @getActiveServer())
            console.log("Loading collection contents for item #{item.path} using server #{connection.server}")
            url = "#{connection.server}/apps/atom-editor/browse.xql?root=#{item.path}"
            options =
                uri: url
                method: "GET"
                json: true
                strictSSL: false
                auth:
                    user: connection.user
                    pass: connection.password || ""
                    sendImmediately: true
            request(
                options,
                (error, response, body) =>
                    if error? or response.statusCode != 200
                        atom.notifications.addWarning("Failed to load database contents", detail: if response? then response.statusMessage else error)
                    else
                        item.view.setChildren(body)
                        for child in body
                            child.view.onSelect(self.onSelect)
                            child.view.onDblClick(self.onDblClick)
                            if child.type == 'collection'
                                child.view.onDrop(self.upload)
                        callback() if callback
            )

        removeResource: (selection) =>
            message = if selection.length == 1 then "resource #{selection[0].path}" else "#{selection.length} resources"
            atom.confirm
                message: "Delete resource?"
                detailedMessage: "Are you sure you want to delete #{message}?"
                buttons:
                    Yes: =>
                        for item in selection
                            @doRemove(item)
                    No: null

        doRemove: (resource) =>
            connection = @config.getConnection(null, @getActiveServer())
            url = "#{connection.server}/rest/#{resource.path}"
            options =
                uri: url
                method: "DELETE"
                strictSSL: false
                auth:
                    user: connection.user
                    pass: connection.password || ""
                    sendImmediately: true
            @emit("status", "Deleting #{resource.path}...")
            request(
                options,
                (error, response, body) =>
                    if error?
                        atom.notifications.addError("Failed to delete #{resource.path}", detail: if response? then response.statusMessage else error)
                    else
                        @emit("status", "")
                        resource.view.delete()
            )

        newFile: (item) =>
            dialog.prompt("Enter a name for the new resource:").then((name) => @createFile(item, name) if name?)

        newCollection: (item) =>
            parent = item.path
            dialog.prompt("Enter a name for the new collection:").then((name) =>
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
                            item.view.addChild(collection)
                            collection.view.onSelect(@onSelect)
                            collection.view.onDblClick(@onDblClick)
                            collection.view.onDrop(@upload)
                    )
            )

        createFile: (item, name) ->
            self = this
            collection = item.path
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
                item.view.addChild(resource)
                resource.view.onSelect(self.onSelect)
                resource.view.onDblClick(self.onDblClick)
                buffer = newEditor.getBuffer()
                # buffer.getPath = () -> resource.path
                server = self.getActiveServer()
                connection = self.config.getConnection(null, server)
                buffer.getId = () -> self.getXMLDBUri(connection, resource.path)
                buffer.setPath(tmpFile)
                resource.editor = newEditor
                buffer._remote = resource
                onDidSave = buffer.onDidSave((ev) ->
                    self.save(null, tmpFile, resource, mime.lookup(resource.path))
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

        open: (resource, server, onOpen) =>
            # switch to existing editor if resource is already open
            editor = @getOpenEditor(resource)
            if editor?
                pane = atom.workspace.paneForItem(editor)
                pane.activateItem(editor)
                onOpen?(editor)
                return

            self = this
            server ?= @getActiveServer()
            connection = @config.getConnection(null, server)
            url = "#{connection.server}/apps/atom-editor/load.xql?path=#{resource.path}"
            tmpDir = @getTempDir(resource.path)
            tmpFile = path.join(tmpDir, path.basename(resource.path))
            @emit("status", "Opening #{resource.path} ...")
            console.log("Downloading %s to %s", resource.path, tmpFile)
            stream = fs.createWriteStream(tmpFile)
            options =
                uri: url
                method: "GET"
                strictSSL: false
                auth:
                    user: connection.user
                    pass: connection.password || ""
                    sendImmediately: true
            contentType = null
            request(options)
                .on("response", (response) ->
                    contentType = response.headers["content-type"]
                )
                .on("error", (err) ->
                    self.emit("status", "")
                    atom.notifications.addError("Failed to download #{resource.path}", detail: err)
                )
                .on("end", () ->
                    self.emit("status", "")
                    promise = atom.workspace.open(null)
                    promise.then((newEditor) ->
                        buffer = newEditor.getBuffer()
                        # buffer.getPath = () -> resource.path
                        buffer.setPath(tmpFile)
                        buffer.getId = () => self.getXMLDBUri(connection, resource.path)
                        buffer.loadSync()
                        resource.editor = newEditor
                        buffer._remote = resource
                        onDidSave = buffer.onDidSave((ev) ->
                            self.save(buffer, tmpFile, resource, contentType)
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
                        if contentType == "application/xquery"
                            XQUtils.xqlint(newEditor)
                        onOpen?(newEditor)
                    )
                )
                .pipe(stream)

        getXMLDBUri: (connection, path) ->
            return "exist://#{connection.name}#{path}"

        getOpenEditor: (resource) ->
            for editor in atom.workspace.getTextEditors()
                if editor.getBuffer()._remote?.path == resource.path
                    return editor
            return null

        save: (buffer, file, resource, contentType) ->
            return new Promise((resolve, reject) =>
                editor = atom.workspace.getActiveTextEditor()
                if buffer?
                    connection = @config.getConnection(buffer.getId())
                else
                    connection = @config.getConnection(null, @getActiveServer())

                url = "#{connection.server}/rest/#{resource.path}"
                contentType = mime.lookup(path.extname(file)) unless contentType
                console.log("Saving %s to %s using content type %s", resource.path, connection.server, contentType)
                self = this
                options =
                    uri: url
                    method: "PUT"
                    strictSSL: false
                    auth:
                        user: connection.user
                        pass: connection.password || ""
                        sendImmediately: true
                    headers:
                        "Content-Type": contentType
                fs.createReadStream(file).pipe(
                    request(
                        options,
                        (error, response, body) ->
                            if error?
                                atom.notifications.addError("Failed to upload #{resource.path}", detail: if response? then response.statusMessage else error)
                                reject()
                            else
                                resolve()
                    )
                )
            )

        uploadCurrent: () =>
            selected = @treeView.getSelected()
            if selected.length != 1 or selected[0].item.type == "resource"
                atom.notifications.addError("Please select a single target collection for the upload in the database tree view")
                return
            editor = atom.workspace.getActiveTextEditor()
            fileName = path.basename(editor.getPath())
            @emit("status", "Uploading file #{fileName}...")
            @save(null, editor.getPath(), path: "#{selected[0].item.path}/#{fileName}", null).then(() =>
                @load(selected[0].item)
                @emit("status", "")
            )

        uploadSelected: () ->
            locals = @fileTree.selectedPaths()
            if locals? and locals.length > 0
                selected = @treeView.getSelected()
                if selected.length != 1 or selected[0].type == "resource"
                    atom.notifications.addError("Please select a single target collection for the upload in the database tree view")
                    return
                @upload(locals, selected[0])

        upload: ({target, files}) =>
            @emit("status", "Uploading #{files.length} files ...")
            deploy = files.every((file) -> file.endsWith(".xar"))
            if deploy
                atom.confirm
                    message: "Install Packages?"
                    detailedMessage: "Would you like to install the packages?"
                    buttons:
                        Yes: -> deploy = true
                        No: -> deploy = false

            for file in files
                if (deploy)
                    promise = @deploy(file)
                    root = @treeView.getNode("/db/apps")
                else
                    fileName = path.basename(file)
                    promise = @save(null, file, path: "#{target.path}/#{fileName}", null)
                    root = target
            promise.then(() =>
                @load(root)
                @emit("status", "")
            )

        deploy: (xar) =>
            return new Promise((resolve, reject) =>
                if xar? and typeof xar == "string" then paths = [ xar ]
                if not paths?
                    paths = @fileTree.selectedPaths()

                if paths? and paths.length > 0
                    for file in paths
                        fileName = path.basename(file)
                        targetPath = "/db/system/repo/#{fileName}"
                        @emit("status", "Uploading package ...")
                        @save(null, file, path: targetPath, null).then(() =>
                            @emit("status", "Deploying package ...")
                            query = """
                            xquery version "3.1";

                            declare namespace expath="http://expath.org/ns/pkg";
                            declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
                            declare option output:method "json";
                            declare option output:media-type "application/json";

                            declare variable $repo := "http://demo.exist-db.org/exist/apps/public-repo/modules/find.xql";

                            declare function local:remove($package-url as xs:string) as xs:boolean {
                                if ($package-url = repo:list()) then
                                    let $undeploy := repo:undeploy($package-url)
                                    let $remove := repo:remove($package-url)
                                    return
                                        $remove
                                else
                                    false()
                            };

                            let $xarPath := "#{targetPath}"
                            let $meta :=
                                try {
                                    compression:unzip(
                                        util:binary-doc($xarPath),
                                        function($path as xs:anyURI, $type as xs:string,
                                            $param as item()*) as xs:boolean {
                                            $path = "expath-pkg.xml"
                                        },
                                        (),
                                        function($path as xs:anyURI, $type as xs:string, $data as item()?,
                                            $param as item()*) {
                                            $data
                                        }, ()
                                    )
                                } catch * {
                                    error(xs:QName("local:xar-unpack-error"), "Failed to unpack archive")
                                }
                            let $package := $meta//expath:package/string(@name)
                            let $removed := local:remove($package)
                            let $installed := repo:install-and-deploy-from-db($xarPath, $repo)
                            return
                                repo:get-root()
                            """
                            @runQuery(query,
                                (error, response) =>
                                    atom.notifications.addError("Failed to deploy package",
                                        detail: if response? then response.body else error)
                                    @emit("status", "")
                                    reject()
                                (body) =>
                                    @emit("status", "")
                                    resolve()
                            )
                        )
            )

        openInBrowser: (ev) =>
            item = ev.target.item
            target = item.path.replace(/^.*?\/([^\/]+)$/, "$1")
            connection = @config.getConnection(null, @getActiveServer())
            url = "#{connection.server}/apps/#{target}"
            process_architecture = process.platform
            switch process_architecture
                when 'darwin' then exec ('open "' + url + '"')
                when 'linux' then exec ('xdg-open "' + url + '"')
                when 'win32' then Shell.openExternal(url)

        reindex: (item) ->
            query = "xmldb:reindex('#{item.path}')"
            @emit("status", "Reindexing #{item.path}...")
            @runQuery(query,
                (error, response) ->
                    atom.notifications.addError("Failed to reindex collection #{item.path}", detail: if response? then response.statusMessage else error)
                (body) =>
                    @emit("status", "")
                    atom.notifications.addSuccess("Collection #{item.path} reindexed")
            )

        sync: (item) =>
            dialog.prompt("Path to sync to (server-side):").then(
                (path) =>
                    query = "file:sync('#{item.path}', '#{path}', ())"
                    @emit("status", "Sync to directory...")
                    @runQuery(query,
                        (error, response) ->
                            @emit("status", "")
                            atom.notifications.addError("Failed to sync collection #{item.path}", detail: if response? then response.statusMessage else error)
                        (body) =>
                            @emit("status", "")
                            atom.notifications.addSuccess("Collection #{item.path} synched to directory #{path}")
                    )
            )

        onSelect: ({node, item}) =>
            if not item.loaded
                @load(item, () ->
                    item.loaded = true
                    item.view.toggleClass('collapsed')
                )

        onDblClick: ({node, item}) =>
            if item.type == "resource"
                @open(item)

        destroy: ->
            @element.remove()
            @disposables.dispose()
            @tempDir.removeCallback() if @tempDir

        remove: ->
          @destroy()

        getTempDir: (uri) ->
            @tempDir = tmp.dirSync({ mode: 0o750, prefix: 'atom-exist_', unsafeCleanup: true }) unless @tempDir
            tmpPath = path.join(fs.realpathSync(@tempDir.name), path.dirname(uri))
            mkdirp.sync(tmpPath)
            return tmpPath

        runQuery: (query, onError, onSuccess) =>
            editor = atom.workspace.getActiveTextEditor()
            connection = @config.getConnection(null, @getActiveServer())
            url = "#{connection.server}/rest/db?_query=#{query}&_wrap=no"
            options =
                uri: url
                method: "GET"
                json: true
                strictSSL: false
                auth:
                    user: connection.user
                    pass: connection.password || ""
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
            xar = @getXAR()
            query = """
                xquery version "3.0";

                declare namespace expath="http://expath.org/ns/pkg";
                declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
                declare option output:method "json";
                declare option output:media-type "application/json";

                if ("http://exist-db.org/apps/atom-editor" = repo:list()) then
                    let $data := repo:get-resource("http://exist-db.org/apps/atom-editor", "expath-pkg.xml")
                    let $xml := parse-xml(util:binary-to-string($data))
                    return
                        if ($xml/expath:package/@version = "#{xar.version}") then
                            true()
                        else
                            $xml/expath:package/@version/string()
                else
                    false()
            """
            @runQuery(query,
                (error, response) ->
                    atom.notifications.addWarning("Failed to access database", detail: if response? then response.statusMessage else error)
                (body) =>
                    if body == true
                        onSuccess?()
                    else
                        if typeof body == "string"
                            message = "Installed support app has version #{body}. A newer version (#{xar.version}) is recommended for proper operation. Do you want to install it?"
                        else
                            message = "This package requires a small support app to be installed on the eXistdb server. Do you want to install it?"
                        atom.confirm
                            message: "Install server-side support app?"
                            detailedMessage: message
                            buttons:
                                Yes: =>
                                    @deploy(xar.path).then(onSuccess)
                                No: -> if typeof body == "string" then onSuccess?() else null
            )

        getXAR: () =>
            pkgDir = atom.packages.resolvePackagePath("existdb")
            if pkgDir?
                files = fs.readdirSync(path.join(pkgDir, "resources/db"))
                for file in files
                    if file.endsWith(".xar")
                        return {
                            version: file.replace(/^.*-([\d\.]+)\.xar/, "$1"),
                            path: path.join(pkgDir, "resources/db", file)
                        }
