path = require 'path'

IMPORT_RE = /\(:[^)]*:\)|(import\s+module\s+namespace\s+[^=]+\s*=\s*["'][^"']+["']\s*at\s+["'][^"']+["']\s*;)/g
MODULE_RE = /import\s+module\s+namespace\s+([^=\s]+)\s*=\s*["']([^"']+)["']\s*at\s+["']([^"']+)["']\s*;/
funcDefRe = /\(:.*declare.+function.+:\)|(declare\s+((?:%[\w\:\-]+(?:\([^\)]*\))?\s*)*)function\s+([^\(]+)\()/g
varDefRe = /\(:.*declare.+variable.+:\)|(declare\s+(?:%\w+\s+)*variable\s+\$[^\s;]+)/gm
varRe = /declare\s+(?:%\w+\s+)*variable\s+(\$[^\s;]+)/
paramRe = /\$[^\s]+/
trimRe = /^[\x09\x0a\x0b\x0c\x0d\x20\xa0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000]+|[\x09\x0a\x0b\x0c\x0d\x20\xa0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000]+$/g

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
        collectionPaths = @getCollectionPaths(editor, config)
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
        params.push("base=" + encodeURIComponent(collectionPaths.basePath))
        params

    parseLocalFunctions: (editor) ->
        text = editor.getText()
        symbols = []

        funcDef =  funcDefRe.exec(text)
        varDef = null

        while funcDef?
            if funcDef[1]?
                offset = funcDefRe.lastIndex
                end = @findMatchingParen(text, offset)
                name = (if funcDef.length == 4 then funcDef[3] else funcDef[2]).replace(trimRe,"")
                status = if funcDef.length == 4 then funcDef[2] else "public"
                args = text.substring(offset, end).split(/\s*,\s*/)
                arity = args.length
                signature =  name + "(" + args + ")"
                status = "private" unless status.indexOf("%private") == -1

                symbols.push({
                    type: "function"
                    name: "#{name}##{arity}"
                    signature: signature
                    status: status
                    line: @getLine(text, offset)
                    file: editor.getPath()
                    snippet: @getSnippet(name, args)
                })
            funcDef = funcDefRe.exec(text)

        varDef =  varDefRe.exec(text)
        while varDef?
            if varDef[1]?
                v = varRe.exec(varDef[1])
                sort = v[1].substr(1).split(":")
                sort.splice(1,0,":$")
                name = v[1]
                if name.substring(0, 1) == "$"
                    name = name.substring(1)
                symbols.push({
                    type: "variable"
                    name: name
                    signature: name
                    line: @getLine(text, varDefRe.lastIndex)
                    file: editor.getPath()
                })
            varDef = varDefRe.exec(text)
        symbols

    getSnippet: (name, args) ->
        templates = []
        i = 0
        for arg in args
            param = paramRe.exec(arg)
            if param?
                templates.push("${#{++i}:#{param[0]}}")

        "#{name}(#{templates.join(", ")})"


    findMatchingParen: (text, offset) ->
        depth = 1
        for i in [offset..text.length]
            ch = text.charAt(i)
            if ch == ')'
                depth -= 1
                if (depth == 0)
                    return i
            else if ch == '('
                depth += 1
        -1

    getLine: (text, offset) ->
        newlines = 0
        for i in [0..offset]
            newlines++ if text.charAt(i) == '\n'
        newlines

    getCollectionPaths: (editor, config) ->
        buffer = editor.getBuffer()
        if buffer._remote
            collection = path.dirname(buffer._remote.path)
            collection: collection
            basePath: "xmldb:exist://#{collection}"
        else
            relativePath = atom.project.relativizePath(editor.getPath())[1]
            collection = path.dirname(relativePath)
            basePath: "xmldb:exist://" + config.getConfig(editor).sync?.root + "/" + collection
            collection: collection

    parseURI: (uri) ->
        match = /^exist:\/\/(.*?)(\/db.*)$/.exec(uri)
        if  match?
            server: match[1]
            path: match[2]
