/** @babel */
import { Emitter } from "event-kit";

export default class TreeNode {
    constructor(tree, item) {
        this.addChild = this.addChild.bind(this);
        this.delete = this.delete.bind(this);
        this.tree = tree;
        this.emitter = new Emitter();
        this.item = item;
        this.item.view = this;

        this.render(item);

        if (item.children != null) {
            this.setChildren(item.children);
        }
    }

    render(item) {
        function renderPermissions(permissions, parent) {
            if (permissions) {
                let tooltip = document.createElement("div");
                tooltip.classList.add("permissions");
                let tooltipText = document.createTextNode(`${permissions.owner} ${permissions.group} ${permissions.mode}`);
                tooltip.appendChild(tooltipText);
                parent.appendChild(tooltip);
            }
        }
        
        let { label, icon, loaded, children, type, permissions } = item;
        if (type === "collection") {
            this.element = document.createElement("li");
            this.element.classList.add(
                "list-nested-item",
                "entry",
                "collapsed"
            );
            this.div = document.createElement("div");
            this.element.appendChild(this.div);
            this.div.classList.add("list-item");
            this.span = document.createElement("span");
            this.div.appendChild(this.span);
            this.span.classList.add("icon", icon, type);
            this.span.appendChild(document.createTextNode(label));
            renderPermissions(permissions, this.div);
            this.children = document.createElement("ol");
            this.element.appendChild(this.children);
            this.children.classList.add("list-tree");
            this.div.addEventListener("dblclick", this.dblClickItem.bind(this));
            this.div.addEventListener("click", this.clickItem.bind(this));
            this.div.addEventListener("drop", this.drop.bind(this));
            this.div.addEventListener("dragover", this.dragOver.bind(this));
        } else {
            this.element = document.createElement("li");
            this.element.classList.add("list-item", "entry");
            this.span = document.createElement("span");
            this.element.appendChild(this.span);
            this.span.classList.add("icon", icon, type);
            this.span.appendChild(document.createTextNode(label));
            renderPermissions(permissions, this.element);
            this.span.addEventListener(
                "dblclick",
                this.dblClickItem.bind(this)
            );
            this.span.addEventListener("mousedown", this.clickItem.bind(this));
            this.span.addEventListener("drop", this.drop.bind(this));
            this.span.addEventListener("dragover", this.dragOver.bind(this));
        }
        this.span.item = item;
        this.element.item = item;
    }
    
    setChildren(children) {
        this.children.innerHTML = "";
        this.item.children = children;

        let result = [];
        for (const child of Array.from(children)) {
            const childNode = new TreeNode(this.tree, child);
            childNode.parentView = this;
            result.push(this.children.appendChild(childNode.element));
        }
        return result;
    }

    addChild(child) {
        if (this.item.children == null) {
            this.item.children = [];
        }
        this.item.children.push(child);
        const childNode = new TreeNode(this.tree, child);
        childNode.parentView = this;
        this.children.appendChild(childNode.element);
        if (this.element.classList.contains("collapsed")) {
            return this.toggleClass("collapsed");
        }
    }

    delete() {
        const newChildren = [];
        for (let child of Array.from(this.parentView.item.children)) {
            if (child.path !== this.item.path) {
                newChildren.push(child);
            }
        }
        this.parentView.item.children = newChildren;
        return this.element.remove();
    }

    toggleClass(clazz) {
        return this.element.classList.toggle(clazz);
    }

    setCollapsed() {
        if (this.item.children) {
            return this.toggleClass("collapsed");
        }
    }

    toggleSelection() {
        return this.toggleClass("selected");
    }

    setSelected(select) {
        if (select) {
            return this.element.classList.add("selected");
        } else {
            return this.element.classList.remove("selected");
        }
    }

    clearSelection() {
        return this.element
            .querySelectorAll(".list-item")
            .forEach(item => item.classList.remove("selected"));
    }

    onDblClick(callback) {
        this.emitter.on("on-dbl-click", callback);
        if (this.item.children) {
            return Array.from(this.item.children).map(child =>
                child.view.onDblClick(callback)
            );
        }
    }

    onDrop(callback) {
        this.emitter.on("on-drop", callback);
        if (this.item.children) {
            return this.item.children.map(child =>
                child.view.onDrop(callback)
            );
        }
    }
    
    drop(ev) {
        ev.preventDefault();
        ev.stopPropagation();
        let files;
        let path = ev.dataTransfer.getData("initialPath");
        if (path) {
            files = [path];
        } else {
            files = [];
            for (const file of ev.dataTransfer.files) {
                files.push(file.path);
            }
            console.log("files to upload: %o", files);
        }
        this.emitter.emit("on-drop", {target: this.item, files: files});
    }
    
    dragOver(ev) {
        ev.preventDefault();
        // Set the dropEffect to move
        ev.dataTransfer.dropEffect = "move"
    }
    
    onSelect(callback) {
        this.emitter.on("on-select", callback);
        if (this.item.children != null) {
            return Array.from(this.item.children).map(child =>
                child.view.onSelect(callback)
            );
        }
    }

    clickItem(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.item.children) {
            this.element.classList.toggle("collapsed");
        }

        this.tree.itemClicked(event, this);

        this.emitter.emit("on-select", { event, node: this, item: this.item });
    }

    dblClickItem() {
        this.emitter.emit("on-dbl-click", { node: this, item: this.item });
        return false;
    }
}
