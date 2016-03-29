module.exports =
    class ASTVisitor

        constructor: ->

        visit: (node, handler) ->
            if node?
                name = node.name
                skip = false
                if typeof @[name] == 'function'
                    skip = if @[name](node) == true then true else false
                if !skip
                    @visitChildren node, handler
            return

        visitChildren: (node, handler) ->
            if node
                for child in node.children
                    if handler != undefined and typeof handler[child.name] == 'function'
                        handler[child.name] child
                    else
                        @visit child, handler
