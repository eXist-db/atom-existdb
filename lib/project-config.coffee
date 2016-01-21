fs = require 'fs'
path = require 'path'

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

    isDirectory: (dir) ->
        try return fs.statSync(dir).isDirectory()
        catch then return false

    destroy: ->
        for disposable in disposables
            disposable.dispose()
