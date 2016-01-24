fs = require 'fs'
path = require 'path'
$ = require('jquery')

defaultConfig = {
    "server": "http://localhost:8080/exist",
    "user": "guest",
    "password": "guest",
    "root": "/db"
}

module.exports =
class ProjectConfig

    data: {}
    disposables: []

    constructor: ->
        @load(atom.project.getPaths())
        @disposables.push(atom.project.onDidChangePaths(@load))

    load: (paths) ->
        for dir in paths
            if @isDirectory(dir)
                configPath = path.resolve(dir, ".existdb.json")
                console.log(configPath)
                if fs.existsSync(configPath)
                    console.log("Found config: %s", configPath)
                    contents = fs.readFileSync(configPath, 'utf8')
                    try
                        @data = JSON.parse(contents)
                    catch e
                        atom.notifications.addInfo('Error parsing .existdb.json.')
                    @data = $.extend({}, defaultConfig, @data)

    isDirectory: (dir) ->
        try return fs.statSync(dir).isDirectory()
        catch then return false

    destroy: ->
        disposable.dispose() for disposable in disposables
