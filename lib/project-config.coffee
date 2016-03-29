$ = require('jquery')
fs = require 'fs'
minimatch = require("minimatch")

module.exports =
class ProjectConfig

    configs: []
    disposables: []

    constructor: ->
        @load(atom.project.getPaths())
        @disposables.push(atom.project.onDidChangePaths(@load))

    load: (paths) =>
        @configs = []
        for dir in paths
            if @isDirectory(dir)
                path = require 'path'
                configPath = path.resolve(dir, ".existdb.json")
                if fs.existsSync(configPath)
                    contents = fs.readFileSync(configPath, 'utf8')
                    try
                        data = JSON.parse(contents)
                        console.log("configuration file %s: %o", configPath, data)
                        fs.watchFile(configPath, (curr, prev) =>
                            @load([dir])
                        )
                        config = $.extend({}, @getDefaults(), data)
                        @configs.push({
                            "path": dir
                            configFile: configPath
                            config: config
                        })
                    catch e
                        atom.notifications.addInfo('Error parsing .existdb.json.', detail: e)

    getConfig: (context) ->
        config = @getProjectConfig(context)
        if config?
            return config.config
        return @getDefaults()

    getProjectConfig: (context) ->
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

    getDefaults: () ->
        server: atom.config.get("existdb.server")
        user: atom.config.get("existdb.user")
        password: atom.config.get("existdb.password")
        root: atom.config.get("existdb.root")
        sync: false
        ignore: []

    ignoreFile: (file) ->
        config = @getConfig(file)
        for pattern in config.ignore
            if minimatch(file, pattern, {matchBase: true, dot: true})
                console.log("ignoring file %s", file)
                return true

    isDirectory: (dir) ->
        try return fs.statSync(dir).isDirectory()
        catch then return false

    destroy: ->
        disposable.dispose() for disposable in disposables
        fs.unwatchFile(config.configFile) for config in @configs
