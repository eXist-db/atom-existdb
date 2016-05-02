$ = require('jquery')
path = require 'path'
util = require './util'
XQUtils = require './xquery-helper'
InScopeVariables = require './var-visitor'

MIN_LENGTH = 3

module.exports =
    class Provider
        selector: '.source.xq, .source.xql, .source.xquery, .source.xqm'
        inclusionPriority: 1
        excludeLowerPriority: true
        config: undefined

        constructor: (@config) ->
            require('atom-package-deps').install().then(
                () ->
                    console.log("Initializing provider")
            )

        getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) ->
            prefix = @getPrefix(editor, bufferPosition)

            if prefix.indexOf('$') != 0 and prefix.length < MIN_LENGTH then return []

            params = util.modules(@config, editor)
            params.push("prefix=" + prefix)
            variables = @getInScopeVariables(editor, prefix)
            # assume we're looking for a local variable if no namespace prefix is present
            return variables if /^$[^:]+$/.test(prefix)
            
            localFuncs = @getLocalSuggestions(editor, prefix)
            self = this
            return new Promise (resolve) ->
                id = editor.getBuffer().getId()
                if id.startsWith("exist:")
                    connection = self.config.getConnection(id)
                else
                    connection = self.config.getConnection(editor)
                $.ajax
                    url: connection.server +
                        "/apps/atom-editor/atom-autocomplete.xql?" +
                            params.join("&")
                    username: connection.user
                    password: connection.password
                    success: (data) ->
                        resolve(variables.concat(localFuncs).concat(data))

        getPrefix: (editor, bufferPosition) ->
            # Whatever your prefix regex might be
            regex = /\$?[:\w0-9_-]+$/

            # Get the text for the line up to the triggered buffer position
            line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])

            # Match the regex to the line, and return the match
            line.match(regex)?[0] or ''

        getLocalSuggestions: (editor, prefix) ->
            regex = new RegExp("^" + prefix)
            localFuncs = []
            for fn in util.parseLocalFunctions(editor) when regex.test(fn.name)
                localFuncs.push(
                    text: fn.signature
                    type: fn.type
                    snippet: fn.snippet
                    replacementPrefix: prefix
                )
            localFuncs

        getInScopeVariables: (editor, prefix) ->
            return [] unless prefix.length > 0 and prefix.charAt(0) == '$'
            ast = editor.getBuffer()._ast
            return [] unless ast?
            pos = editor.getCursorBufferPosition()
            node = XQUtils.findNode(ast, { line: pos.row, col: pos.column - 1})
            prefix = prefix.substring(1)
            if node?
                parent = node.getParent
                if parent.name == "VarRef" or parent.name == "VarName"
                    visitor = new InScopeVariables(ast, parent)
                    vars = visitor.getStack()
                    if vars?
                        regex = new RegExp("^" + prefix)
                        variables = []
                        for v in vars.sort((a, b) ->
                            if a.name == b.name
                                0
                            else if a.name < b.name
                                -1
                            else
                                1
                                
                        ) when regex.test(v.name)
                            def =
                                text: "$" + v.name
                                type: "variable"
                                snippet: v.name
                                replacementPrefix: prefix
                            variables.push(def)
                        return variables
            return []
