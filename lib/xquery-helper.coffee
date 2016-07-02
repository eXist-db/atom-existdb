{XQLint} = require 'xqlint'
{CompositeDisposable, Range, Point} = require 'atom'
_path = require 'path'

module.exports =
    XQUtils =
        xqlint: (editor) ->
            try
                editor.getBuffer()._ast = null
                xqlint = new XQLint(editor.getText(), fileName: editor.getPath())
                editor.getBuffer()._ast = xqlint.getAST()
                xqlint
            catch ex
                null

        findNode: (ast, pos) ->
            p = ast.pos
            if @inRange(p, pos, false)
                for child in ast.children
                    n = @findNode(child, pos)
                    return n if n?
                return ast
            else
                return null

        findNodeForRange: (ast, start, end) ->
            p = ast.pos
            if @inRange(p, start, true) and @inRange(p, end, true)
                for child in ast.children
                    n = @findNodeForRange(child, start, end)
                    return n if n?
                return ast
            else
                return null
        
        samePosition: (pos1, pos2) ->
            return pos1.sl == pos2.sl and
                pos1.sc == pos2.sc and
                pos1.el == pos2.el and
                pos1.ec == pos2.ec

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

        getAncestorOrSelf: (type, node) ->
            return node if node.name == type
            if node.getParent?
                return @getAncestor(type, node)
            return null

        getAncestor: (type, node) ->
            if node.getParent?
                return node.getParent if node.getParent.name == type
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

        findBinding: (variable, node, found) ->
            found ?= []
            for child in node.children
                switch child.name
                    when "InitialClause", "IntermediateClause", "LetClause", "LetBinding", "ForClause", "ForBinding"
                        @findBinding(variable, child, found)
                    when "VarName"
                        name = @getValue(child)
                        if name == variable
                            found.push(child)
            return found
        
        getParameter: (param, node) ->
            for child in node.children
                switch child.name
                    when "ParamList", "Param"
                        found = @getParameter(param, child)
                        return found if found
                    when "EQName"
                        if child.value == param
                            return child
            return false
            
        getVariableScope: (variable, node) ->
            switch node.name
                when "FLWORExpr"
                    binding = @findBinding(variable, node)
                    if binding.length > 0
                        return node
                when "FunctionDecl"
                    if @getParameter(variable, node)
                        return node
            
            if node.getParent?
                return @getVariableScope(variable, node.getParent)
            return null
        
        getVariableDef: (variable, node) ->
            switch node.name
                when "FLWORExpr"
                    bindings = @findBinding(variable, node)
                    if bindings.length > 0
                        return bindings.pop()
                when "FunctionDecl"
                    param = @getParameter(variable, node)
                    return param if param

            if node.getParent?
                return @getVariableDef(variable, node.getParent)
            return null

        getFunctionSignature: (node) ->
            return null unless node.name == "FunctionCall"
            name = @findChild(node, "EQName")
            argList = @findChild(node, "ArgumentList")
            if argList?
                args = @findChildren(argList, "Argument")
                name: name.value
                arity: args.length

        getFunctionDefinition: (editor, point) =>
            self = this
            scopes = editor.getRootScopeDescriptor().getScopesArray()
            if scopes.indexOf("source.xq") > -1
                ast = editor.getBuffer()._ast
                return unless ast?
                node = XQUtils.findNode(ast, { line: point.row, col: point.column })
                if node?
                    parent = XQUtils.getAncestorOrSelf("FunctionCall", node)
                    if parent?
                        signature = XQUtils.getFunctionSignature(parent)
                        if signature?
                            return {
                                range: new Range([parent.pos.sl, parent.pos.sc], [parent.pos.el, parent.pos.ec]),
                                signature: "#{signature.name}##{signature.arity}"
                            }
        
        getText: (editor) ->
            if _path.extname(editor.getPath()) == '.xqs' and editor.getText().length > 0
                @extractSnippet(editor)
            else
                text: editor.getText()
                prologOffset: 0
                offset: 0
                isSnippet: false
        
        extractSnippet: (editor) ->
            pos = editor.getCursorBufferPosition()
            prolog = ""
            prologEnd = new Point([0, 0])
            editor.scan(/^(xquery|import|declare)[^]*;/,
                ({match, matchText, range, stop}) ->
                    prolog = matchText
                    prologEnd = range.end
            )
            start = prologEnd.row + 1
            editor.backwardsScanInBufferRange(/\n(\s*\n){2,}/, new Range(prologEnd, pos),
                ({match, matchText, range, stop}) ->
                    start = range.start.row + 1
                    stop()
            )
            lastPos = editor.clipBufferPosition([Infinity, Infinity])
            end = lastPos
            editor.scanInBufferRange(/\n(\s*\n){2,}/, new Range([start, 0], lastPos),
                ({range, stop}) ->
                    end = range.end
                    stop()
            )
            chunk = editor.getTextInBufferRange(new Range([start, 0], end))
            text: prolog + chunk
            prologOffset: prologEnd.row
            offset: start
            isSnippet: true