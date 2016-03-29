{XQLint} = require 'xqlint'

module.exports =
    XQUtils =
        xqlint: (editor) ->
            xqlint = new XQLint(editor.getText(), fileName: editor.getPath())
            editor.getBuffer()._ast = xqlint.getAST()
            xqlint

        findNode: (ast, pos) ->
            p = ast.pos
            if @inRange(p, pos, false)
                for child in ast.children
                    n = @findNode(child, pos)
                    return n if n?
                return ast
            else
                return null

        inRange: (p, pos, exclusive) ->
            if (p? and p.sl <= pos.line and pos.line <= p.el)
                if (p.sl < pos.line and pos.line < p.el)
                    return true
                else if (p.sl == pos.line and pos.line < p.el)
                    return p.sc <= pos.col
                else if (p.sl == pos.line and p.el == pos.line)
                    return p.sc <= pos.col and pos.col <= p.ec + (if exclusive then 1 else 0)
                else if (p.sl < pos.line and p.el == pos.line)
                    return pos.col <= p.ec + (if exclusive then 1 else 0)

        getValue: (node) ->
            val = ""
            if (node.value)
                val = node.value
            else
                for child in node.children
                    val += @getValue(child)
            return val

        getAncestor: (type, node) ->
            return node if node.name == type
            if node.getParent?
                return @getAncestor(type, node.getParent)
            return null

        findChild: (node, type) ->
            return null unless node.children
            for child in node.children
                if child.name == type
                    return child
            return null

        findChildren: (node, type) ->
            return null unless node.children
            matches = []
            for child in node.children
                if child.name == type
                    matches.push(child)
            return matches

        getFunctionSignature: (node) ->
            return null unless node.name == "FunctionCall"
            name = @findChild(node, "EQName")
            argList = @findChild(node, "ArgumentList")
            if argList?
                args = @findChildren(argList, "Argument")
                name: name.value
                arity: args.length
