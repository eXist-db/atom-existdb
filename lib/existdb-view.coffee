path = require 'path'
{$$, SelectListView} = require 'atom-space-pen-views'
$ = require('jquery')
util = require './util'

module.exports =
class EXistSymbolsView extends SelectListView

    constructor: (@config, @main) ->
        super

    initialize: ->
        super
        @addClass("eXist-symbols-view fuzzy-finder")

        @panel ?= atom.workspace.addModalPanel(item: this, visible: false)

        @focusFilterEditor()

    populate: (editor) ->
        scopes = editor.getRootScopeDescriptor().getScopesArray()
        if scopes.indexOf("source.xq") > -1
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
        @main.open(editor, file, (newEditor) =>
            @main.gotoLocalDefinition(item.name, newEditor)
        )

    cancelled: ->
        @panel.hide()

    destroy: ->
        @cancel()
        @panel.destroy()

    getFileSymbols: (editor) ->
        @symbols = util.parseLocalFunctions(editor)
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
