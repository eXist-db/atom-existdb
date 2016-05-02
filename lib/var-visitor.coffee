ASTVisitor = require './visitor'
XQUtils = require './xquery-helper'
{Range} = require 'atom'

module.exports =
    class InScopeVariables extends ASTVisitor

        constructor: (root, node) ->
            @node = node
            @stack = []
            @variables = null
            @visit(root)

        FLWORExpr: (node) ->
            pos = @stack.length
            @visitChildren node
            @stack.length = pos
            true

        VarName: (node) ->
            if node is @node
                @variables = @deepCopy(@stack)
                return true
            if node.getParent.name == 'ForBinding' or node.getParent.name == 'LetBinding'
                name = XQUtils.getValue(node)
                @stack.push
                    name: name,
                    range: new Range([node.pos.sl, node.pos.sc - 1], [node.pos.el, node.pos.ec])

        VarRef: (node) ->
            if node is @node
                @variables = @deepCopy(@stack)
                return true
            false

        VarDecl: (node) ->
            self = this
            @visitChildren node,
                VarName: (node) ->
                    value = XQUtils.getValue(node)
                    self.stack.push
                        name: value,
                        range: new Range([node.pos.sl, node.pos.sc - 1], [node.pos.el, node.pos.ec])
                    true
                VarValue: (node) ->
                    true
                    # skip
            true

        FunctionDecl: (node) ->
            saved = @deepCopy(@stack)
            @visitChildren node
            @stack = saved
            true

        Param: (node) ->
            self = this
            @visitChildren node, EQName: (node) ->
                self.stack.push
                    name: node.value,
                    range: new Range([node.pos.sl, node.pos.sc - 1], [node.pos.el, node.pos.ec])
                return
            true

        deepCopy: (arr) ->
            copy = []
            i = 0
            while i < arr.length
                copy.push arr[i]
                i++
            copy

        getStack: () ->
            @variables
