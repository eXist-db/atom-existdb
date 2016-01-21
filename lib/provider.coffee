$ = require('jquery')
path = require 'path'

BASE_PATH = "/db/apps/monex/modules"
MIN_LENGTH = 3
IMPORT_RE = /\(:[^)]*:\)|(import\s+module\s+namespace\s+[^=]+\s*=\s*["'][^"']+["']\s*at\s+["'][^"']+["']\s*;)/g
MODULE_RE = /import\s+module\s+namespace\s+([^=\s]+)\s*=\s*["']([^"']+)["']\s*at\s+["']([^"']+)["']\s*;/

module.exports =
    class Provider
        selector: '.source.xq, .source.xql, .source.xquery, .source.xqm'
        inclusionPriority: 1
        excludeLowerPriority: true
        config: undefined

        constructor: (config) ->
            @config = config

        getSuggestions: ({editor, bufferPosition, scopeDescriptor, prefix}) ->
            prefix = @getPrefix(editor, bufferPosition)
            console.log("getting suggestions for %s", prefix)
            scopes = scopeDescriptor.getScopesArray()
            console.log("scopes: %o", scopes)
            imports = @getImports(editor.getText())
            params = @resolveImports(editor, imports)

            if prefix.length < MIN_LENGTH then return []

            params.push("prefix=" + prefix)

            self = this
            return new Promise (resolve) ->
                $.ajax
                    url: self.config.data.server +
                        "/apps/eXide/modules/atom-autocomplete.xql?" +
                            params.join("&")
                    success: (data) ->
                        resolve(data)

        getPrefix: (editor, bufferPosition) ->
            # Whatever your prefix regex might be
            regex = /[:\w0-9_-]+$/

            # Get the text for the line up to the triggered buffer position
            line = editor.getTextInRange([[bufferPosition.row, 0], bufferPosition])

            # Match the regex to the line, and return the match
            line.match(regex)?[0] or ''

        getImports: (code) ->
            ret = []
            match = IMPORT_RE.exec(code)

            while match != null
                if match[1] != null
                    ret.push(match[1])
                match = IMPORT_RE.exec(code)
            return ret

        resolveImports: (editor, imports) ->
            relativePath = atom.project.relativizePath(editor.getPath())[1]
            collection = path.dirname(relativePath)
            functions = []
            params = []
            for imp in imports
                matches = MODULE_RE.exec(imp)
                if matches != null and matches.length == 4
                    params.push("mprefix=" + encodeURIComponent(matches[1]))
                    params.push("uri=" + encodeURIComponent(matches[2]))
                    params.push("source=" + encodeURIComponent(matches[3]))
            basePath = "xmldb:exist://" + @config.data.root + "/" + collection
            params.push("base=" + encodeURIComponent(basePath))
            return params
