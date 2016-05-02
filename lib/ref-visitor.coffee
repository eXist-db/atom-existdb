ASTVisitor = require './visitor'
XQUtils = require './xquery-helper'
{Range} = require 'atom'

module.exports =
    class VariableReferences extends ASTVisitor

        constructor: (variable, ast) ->
            @variable = variable
            @references = []
            @visit(ast)

        VarName: (node) ->
            name = XQUtils.getValue(node)
            if name == @variable.value
                @references.push
                    name: name,
                    range: new Range([node.pos.sl, node.pos.sc - 1], [node.pos.el, node.pos.ec])
        
        Param: (node) ->
            for child in node.children
                if child.value == @variable.value
                    @references.push
                        name: child.value,
                        range: new Range([child.pos.sl, child.pos.sc - 1], [child.pos.el, child.pos.ec])
                
        getReferences: () ->
            @references