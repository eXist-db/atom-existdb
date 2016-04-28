cp = require 'child_process'

module.exports =
class WatcherControl

    constructor: (@config, @main) ->
        @init()
        @config.onConfigChanged(([configs, globalConfig]) => @init())

    init: () =>
        if @watcher?
            @watcher.send({
                action: "close"
            })
            @watcher.kill()

        return unless @config.useSync()

        @watcher = cp.fork(__dirname + '/watcher.js')
        process.on('exit', () =>
            @watcher.kill()
        )
        @watcher.on("error", (error) ->
            atom.notifications.addError(error.message)
        )
        @watcher.on("message", (obj) =>
            # console.log("received message: %o", obj)
            if obj.action == "status"
                @main.updateStatus(obj.message)
            else if obj.action == "error"
                atom.notifications.addError(obj.message, { detail: obj.detail, dismissable: true })
        )
        @watcher.on("close", () =>
            @init()
        )
        @watcher.send({
            action: "init"
            configuration: @config.configs
        })

    destroy: () ->
        @watcher?.send({
            action: "close"
        })
        setTimeout(() =>
            @watcher?.kill()
        , 500)
