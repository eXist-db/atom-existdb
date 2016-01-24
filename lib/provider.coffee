$ = require('jquery')
path = require 'path'
util = require './util'

MIN_LENGTH = 3

module.exports =
    class Provider
        selector: '.source.xq, .source.xql, .source.xquery, .source.xqm'
        inclusionPriority: 1
        excludeLowerPriority: true
        config: undefined

        constructor: (@config) ->

        getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) ->
            prefix = @getPrefix(editor, bufferPosition)
            console.log("getting suggestions for %s", prefix)
            scopes = scopeDescriptor.getScopesArray()
            params = util.modules(@config, editor)

            if prefix.length < MIN_LENGTH then return []

            params.push("prefix=" + prefix)

            self = this
            return new Promise (resolve) ->
                $.ajax
                    url: self.config.data.server +
                        "/apps/atom-editor/atom-autocomplete.xql?" +
                            params.join("&")
                    username: self.config.data.user
                    password: self.config.data.password
                    success: (data) ->
                        resolve(data)

        getPrefix: (editor, bufferPosition) ->
            # Whatever your prefix regex might be
            regex = /[:\w0-9_-]+$/

            # Get the text for the line up to the triggered buffer position
            line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])

            # Match the regex to the line, and return the match
            line.match(regex)?[0] or ''
