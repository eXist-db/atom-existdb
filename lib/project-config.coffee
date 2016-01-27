fs = require 'fs'
path = require 'path'
$ = require('jquery')

module.exports =
class ProjectConfig

    configs: []
    disposables: []

    constructor: ->
        @load(atom.project.getPaths())
        @disposables.push(atom.project.onDidChangePaths(@load))

    load: (paths) ->
        @configs = []
        for dir in paths
            if @isDirectory(dir)
                configPath = path.resolve(dir, ".existdb.json")
                if fs.existsSync(configPath)
                    contents = fs.readFileSync(configPath, 'utf8')
                    try
                        data = JSON.parse(contents)
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
        else
            path = context.getPath()
        for config in @configs
            if path.length >= config.path.length && path.substring(0, config.path.length) == config.path
                return config

    getDefaults: () ->
        {
            server: atom.config.get("existdb.server"),
            user: atom.config.get("existdb.user"),
            password: atom.config.get("existdb.password"),
            root: atom.config.get("existdb.root")
        }

    isDirectory: (dir) ->
        try return fs.statSync(dir).isDirectory()
        catch then return false

    destroy: ->
        disposable.dispose() for disposable in disposables
        fs.unwatchFile(config.configFile) for config in @configs
