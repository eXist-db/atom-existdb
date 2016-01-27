path = require 'path'

IMPORT_RE = /\(:[^)]*:\)|(import\s+module\s+namespace\s+[^=]+\s*=\s*["'][^"']+["']\s*at\s+["'][^"']+["']\s*;)/g
MODULE_RE = /import\s+module\s+namespace\s+([^=\s]+)\s*=\s*["']([^"']+)["']\s*at\s+["']([^"']+)["']\s*;/

module.exports =

    modules: (config, editor, includeJava) ->
        imports = @getImports(editor.getText())
        @resolveImports(config, editor, imports, includeJava)

    getImports: (code) ->
        ret = []
        match = IMPORT_RE.exec(code)

        while match != null
            if match[1]?
                ret.push(match[1])
            match = IMPORT_RE.exec(code)
        ret

    resolveImports: (config, editor, imports, includeJava = true) ->
        relativePath = atom.project.relativizePath(editor.getPath())[1]
        collection = path.dirname(relativePath)
        functions = []
        params = []
        for imp in imports
            matches = MODULE_RE.exec(imp)
            if matches? and matches.length is 4
                isJava = matches[3].substring(0, 5) == "java:"
                if !isJava or includeJava
                    params.push("mprefix=" + encodeURIComponent(matches[1]))
                    params.push("uri=" + encodeURIComponent(matches[2]))
                    params.push("source=" + encodeURIComponent(matches[3]))
        basePath = "xmldb:exist://" + config.getConfig(editor).root + "/" + collection
        params.push("base=" + encodeURIComponent(basePath))
        params
