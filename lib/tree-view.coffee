{Emitter} = require 'event-kit'

module.exports =
  TreeNode: class TreeNode

    constructor: (item) ->
        @emitter = new Emitter
        @item = item
        @item.view = this

        @render(item)

        @setChildren(item.children) if item.children?

    render: (item) ->
        {label, icon, loaded, children, type} = item
        if type == 'collection'
            @element = document.createElement("li")
            @element.classList.add("list-nested-item", "list-selectable-item", "collapsed")
            @div = document.createElement("div")
            @element.appendChild(@div)
            @div.classList.add("list-item")
            @span = document.createElement("span")
            @div.appendChild(@span)
            @span.classList.add("icon", icon, type)
            @span.appendChild(document.createTextNode(label))
            @children = document.createElement("ol")
            @element.appendChild(@children)
            @children.classList.add("list-tree")
            @div.addEventListener('dblclick', @dblClickItem)
            @div.addEventListener('click', @clickItem)
        else
            @element = document.createElement("li")
            @element.classList.add("list-item", "list-selectable-item")
            @span = document.createElement("span")
            @element.appendChild(@span)
            @span.classList.add("icon", icon, type)
            @span.appendChild(document.createTextNode(label))
            @span.addEventListener('dblclick', @dblClickItem)
            @span.addEventListener('click', @clickItem)
        @span.item = item
        @element.item = item

    setChildren: (children) ->
        @children.innerHTML = ""
        @item.children = children
        for child in children
            childNode = new TreeNode(child)
            childNode.parentView = @
            @children.appendChild(childNode.element)

    addChild: (child) =>
        @item.children = [] unless @item.children?
        @item.children.push(child)
        childNode = new TreeNode(child)
        childNode.parentView = @
        @children.appendChild(childNode.element)
        @toggleClass('collapsed') if @element.classList.contains('collapsed')

    delete: () =>
        newChildren = []
        for child in @parentView.item.children
            if child.path != @item.path
                newChildren.push(child)
        @parentView.item.children = newChildren
        @element.remove()

    toggleClass: (clazz) ->
        @element.classList.toggle(clazz)

    setCollapsed: ->
        @toggleClass('collapsed') if @item.children

    setSelected: () ->
        @toggleClass('selected')

    clearSelection: ->
        @element.querySelectorAll(".list-item").forEach((item) ->
            item.classList.remove("selected")
        )

    onDblClick: (callback) ->
      @emitter.on 'on-dbl-click', callback
      if @item.children
        for child in @item.children
          child.view.onDblClick callback

    onSelect: (callback) ->
      @emitter.on 'on-select', callback
      if @item.children?
        for child in @item.children
            child.view.onSelect callback

    clickItem: (event) =>
        if @item.children
            selected = @element.classList.contains('selected')
            @element.classList.remove('selected')
            @element.classList.toggle('collapsed') if event.offsetX <= 12
            @element.classList.add('selected') if selected
            return false if event.offsetX <= 12

        @emitter.emit 'on-select', {node: this, item: @item}
        return false

    dblClickItem: (event) =>
      @emitter.emit 'on-dbl-click', {node: this, item: @item}
      return false


  TreeView: class TreeView

    constructor: ->
        @emitter = new Emitter
        @render()

    render: ->
        @element = document.createElement("ul")
        @element.classList.add("existdb-tree-view", "list-tree", "has-collapsable-children")

    deactivate: ->
      @remove()

    onSelect: (callback) =>
      @emitter.on 'on-select', callback

    setRoot: (root, ignoreRoot=true) ->
      @rootNode = new TreeNode(root)
      root.view = @rootNode
      @rootNode.setCollapsed()
      @rootNode.onDblClick ({node, item}) =>
        node.setCollapsed()
      @rootNode.onSelect ({node, item}) =>
        @clearSelect()
        node.setSelected(true)
        @emitter.emit 'on-select', {node, item}

      @element.innerHTML = ""
      @element.appendChild(@rootNode.element)

    getSelected: () ->
        selected = []
        @rootNode.element.querySelectorAll(".selected").forEach((n) ->
            selected.push(n.item)
        )
        selected

    traversal: (root, doing) =>
      doing(root.item)
      if root.item.children
        for child in root.item.children
          @traversal(child.view, doing)

    toggleTypeVisible: (type) =>
      @traversal @rootNode, (item) =>
        if item.type == type
          item.view.toggle()

    sortByName: (ascending=true) =>
      @traversal @rootNode, (item) =>
        item.children?.sort (a, b) =>
          if ascending
            return a.name.localeCompare(b.name)
          else
            return b.name.localeCompare(a.name)
      @setRoot(@rootNode.item)

    sortByRow: (ascending=true) =>
      @traversal @rootNode, (item) =>
        item.children?.sort (a, b) =>
          if ascending
            return a.position.row - b.position.row
          else
            return b.position.row - a.position.row
      @setRoot(@rootNode.item)

    clearSelect: ->
      $('.list-selectable-item').removeClass('selected')

    select: (item) ->
      @clearSelect()
      item?.view.setSelected(true)

    # resizeStarted: =>
    #     $(document).on('mousemove', @resizeTreeView)
    #     $(document).on('mouseup', @resizeStopped)
    #
    # resizeStopped: =>
    #     $(document).off('mousemove', @resizeTreeView)
    #     $(document).off('mouseup', @resizeStopped)
    #
    # resizeTreeView: ({pageX, which}) =>
    #     return @resizeStopped() unless which is 1
    #
    #     if atom.config.get('tree-view.showOnRightSide')
    #         width = pageX - @offset().left
    #     else
    #         width = @outerWidth() + @offset().left - pageX
    #     @width(width)
