{Emitter,File} = require('atom')
$ = require('jquery')
fs = require 'fs'
_path = require 'path'
minimatch = require("minimatch")
util = require './util'

module.exports =
class ProjectConfig

    globalConfig: null
    globalConfigPath: null
    configs: []
    disposables: []
    paths: []
    activeServer: null

    constructor: ->
        @emitter = new Emitter()
        @initGlobalConfig()
        @load(atom.project.getPaths())
        @disposables.push(atom.project.onDidChangePaths(@load))
        @disposables.push(atom.commands.add('atom-workspace', 'existdb:create-configuration-for-selected': =>
            atom.packages.activatePackage('tree-view').then((pkg) =>
                fileTree = pkg.mainModule.getTreeViewInstance()
                selected = fileTree.selectedPaths()
                if selected? and selected.length > 0
                    path = @getProjectConfigPath(selected[0]) or selected[0]
                else
                    path = atom.project.getPaths()?[0]
                @createProjectConfig(path)
            ))
        )
        @disposables.push(atom.commands.add('atom-workspace', 'existdb:create-configuration-for-current': =>
            editor = atom.workspace.getActiveTextEditor()
            if not editor?
                atom.notifications.addError('No editor open')
                return

            path = @getProjectConfigPath(editor.getPath())
            if not path
                path = atom.project.relativizePath(editor.getPath())[0]
            @createProjectConfig(path))
        )
        @disposables.push(atom.commands.add('atom-workspace', 'existdb:edit-configuration': =>
            atom.workspace.open(@globalConfigPath)
        ))
        file = new File(@globalConfigPath)
        disposable = file.onDidChange(=>
            @initGlobalConfig()
            @emitter.emit("changed", [@configs, @globalConfig])
        )
        @disposables.push(disposable)

    load: (paths) =>
        for config in @configs
            config.disposable.dispose()
        @paths = []
        @configs = []
        for dir in paths
            if isDirectory(dir)
                path = require 'path'
                configPath = path.resolve(dir, ".existdb.json")
                if fs.existsSync(configPath)
                    contents = fs.readFileSync(configPath, 'utf8')
                    try
                        data = JSON.parse(contents)
                        file = new File(configPath)
                        disposable = file.onDidChange(=>
                            console.log("Configuration changed. Reloading")
                            @load([dir])
                        )
                        config = $.extend({}, @getDefaults(), data)
                        config.path = dir
                        config.configFile = configPath
                        config.disposable = disposable
                        for name, connection of config.servers
                            connection.name = name

                        console.log("configuration file %s: %o", configPath, config)
                        @configs.push(config)

                        @paths.push(dir)
                    catch e
                        atom.notifications.addInfo('Error parsing .existdb.json.', detail: e)
        @emitter.emit("changed", [@configs, @globalConfig])

    createProjectConfig: (path) ->
        return unless path? and isDirectory(path)

        config = _path.resolve(path, ".existdb.json")
        if fs.existsSync(config)
            atom.workspace.open(config)
            return
        fs.writeFileSync(config, JSON.stringify(@getDefaults(), null, 4))
        atom.workspace.open(config)
        @load(atom.project.getPaths())

    onConfigChanged: (callback) ->
        @emitter.on("changed", callback)

    getConnection: (context, server) ->
        if typeof context == "string" and context.startsWith("exist:")
            config = @getConfig()
            config.servers[util.parseURI(context).server]
        else
            config = @getConfig(context)
            return config.servers[config.sync.server] if !server and config.sync?.active and config.sync?.server
            return config.servers[server] if server?
            config.servers[Object.keys(config.servers)[0]]

    getConfig: (context) ->
        config = @getProjectConfig(context)
        mergeConfigs(config, @globalConfig)

    mergeConfigs = (config, globals) ->
        if config?
            newConfig = $.extend({}, config)
            newConfig.servers = $.extend({}, globals.servers, config.servers)
            return newConfig
        return globals

    initGlobalConfig: () ->
        @globalConfigPath = _path.join(_path.dirname(atom.config.getUserConfigPath()), 'existdb.json')
        if not fs.existsSync(@globalConfigPath)
            defaults = {
                servers: {
                    "localhost": {
                        server: "http://localhost:8080/exist"
                        user: "admin"
                        password: ""
                    }
                }
            }
            fs.writeFileSync(@globalConfigPath, JSON.stringify(defaults, null, 4))
            @globalConfig = defaults
        else
            contents = fs.readFileSync(@globalConfigPath, 'utf8')
            try
                @globalConfig = JSON.parse(contents)
            catch e
                atom.notifications.addInfo('Error parsing .existdb.json.', detail: e)
        for name, connection of @globalConfig.servers
            connection.name = name

    getProjectConfig: (context) ->
        context ?= @paths[0]
        return unless context?

        if typeof context == "string"
            path = context
        else if context?
            path = context.getPath()
        if path?
            for config in @configs
                if path.length >= config.path.length && path.substring(0, config.path.length) == config.path
                    return config
        else if @configs.length > 0
            @configs[0]
        else
            null

    getProjectConfigPath: (path) ->
        if path?
            for config in @configs
                if path.length >= config.path.length && path.substring(0, config.path.length) == config.path
                    return config.path

    getDefaults: () ->
        {
            servers: {
                "localhost": {
                    server: "http://localhost:8080/exist"
                    user: "admin"
                    password: ""
                }
            },
            sync: {
                server: "localhost"
                root: ""
                active: false
                ignore: ['.existdb.json', '.git/**', 'node_modules/**', 'bower_components/**']
            }
        }

    useSync: () ->
        for config in @configs
            return true if config.sync?.active

    ignoreFile: (file) ->
        config = @getConfig(file)
        for pattern in config?.sync?.ignore
            if minimatch(file, pattern, {matchBase: true, dot: true})
                console.log("ignoring file %s", file)
                return true

    isDirectory = (dir) ->
        try return fs.statSync(dir).isDirectory()
        catch then return false

    destroy: ->
        @emitter.dispose()
        disposable.dispose() for disposable in @disposables
        config.disposable.dispose() for config in @configs
