path = require 'path'
{$$, SelectListView} = require 'atom-space-pen-views'
$ = require('jquery')
util = require './util'

funcDefRe = /\(:.*declare.+function.+:\)|(declare\s+((?:%[\w\:\-]+(?:\([^\)]*\))?\s*)*)function\s+([^\(]+)\()/g
varDefRe = /\(:.*declare.+variable.+:\)|(declare\s+(?:%\w+\s+)*variable\s+\$[^\s;]+)/gm
varRe = /declare\s+(?:%\w+\s+)*variable\s+(\$[^\s;]+)/
trimRe = /^[\x09\x0a\x0b\x0c\x0d\x20\xa0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000]+|[\x09\x0a\x0b\x0c\x0d\x20\xa0\u1680\u180e\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000]+$/g

module.exports =
class EXistSymbolsView extends SelectListView

    constructor: (@config) ->
        super

    initialize: ->
        super
        @addClass("eXist-symbols-view fuzzy-finder")

        @panel ?= atom.workspace.addModalPanel(item: this, visible: false)

        @focusFilterEditor()

    populate: (editor) ->
        @getFileSymbols(editor)
        @getImportedSymbols(editor)

        @storeFocusedElement()
        @panel.show()
        @focusFilterEditor()

    viewForItem: ({name, signature, line, file, type}) ->
        $$ ->
            @li class: 'two-lines', =>
                @div (if type is "variable" then "$#{name}" else signature), class: 'primary-line'
                dir = path.basename(file)
                @div "#{dir} #{if line > 0 then line + 1 else ''}", class: 'secondary-line'

    confirmed: (item) ->
        @cancel()
        editor = atom.workspace.getActiveTextEditor()
        if item.file == editor.getPath()
            editor.scrollToBufferPosition([item.line, 0])
            editor.setCursorBufferPosition([item.line, 0])
        else
            @open(editor, item.file, item)

    open: (editor, file, item) ->
        xmldbRoot = "xmldb:exist://#{@config.getConfig(editor).root}/"
        if file.indexOf(xmldbRoot) is 0
            file = file.substring(xmldbRoot.length)
        else
            file = path.resolve(editor.getPath(), file)
        console.log("opening file: %s", file)
        promise = atom.workspace.open(file)
        if item?
            promise.then((newEditor) =>
                symbols = @parseLocalFunctions(newEditor)
                for symbol in symbols
                    if symbol.name == item.name
                        newEditor.scrollToBufferPosition([symbol.line, 0])
                        newEditor.setCursorBufferPosition([symbol.line, 0])
            )

    cancelled: ->
        @panel.hide()

    destroy: ->
        @cancel()
        @panel.destroy()

    getFileSymbols: (editor) ->
        @symbols = @parseLocalFunctions(editor)
        @setItems(@symbols)

    getFilterKey: ->
        "name"

    getImportedSymbols: (editor) ->
        params = util.modules(@config, editor, false)
        config = @config.getConfig(editor)
        @setLoading("Loading imported symbols...")
        self = this
        $.ajax
            url: config.server +
                "/apps/atom-editor/atom-autocomplete.xql?" +
                    params.join("&")
            username: config.user
            password: config.password
            success: (data) ->
                for item in data
                    self.symbols.push({
                        type: item.type
                        name: item.name
                        signature: item.text
                        line: -1
                        file: item.path
                    })
                self.setItems(self.symbols)
                self.setLoading('')

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
                args = text.substring(offset, end)
                cardinality = args.split(/\s*,\s*/).length
                signature =  name + "(" + args + ")"
                status = "private" unless status.indexOf("%private") == -1

                symbols.push({
                    type: "function"
                    name: "#{name}##{cardinality}"
                    signature: signature
                    status: status
                    line: @getLine(text, offset)
                    file: editor.getPath()
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
