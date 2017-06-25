/** @babel */
import TreeNode from './tree-node.js';

export default class TreeView {

    constructor() {
        this.traversal = this.traversal.bind(this);
        this.toggleTypeVisible = this.toggleTypeVisible.bind(this);
        this.sortByName = this.sortByName.bind(this);
        this.sortByRow = this.sortByRow.bind(this);
        this.render();
    }

    render() {
        this.element = document.createElement("ul");
        return this.element.classList.add("existdb-tree-view", "list-tree", "has-collapsable-children");
    }

    destroy() {
      this.element.remove();
  }

    setRoot(root, ignoreRoot) {
      if (ignoreRoot == null) { ignoreRoot = true; }
      this.rootNode = new TreeNode(this, root);
      root.view = this.rootNode;
      this.rootNode.setCollapsed();
      this.rootNode.onDblClick(({node}) => {
        return node.setCollapsed();
      });

      this.element.innerHTML = "";
      return this.element.appendChild(this.rootNode.element);
  }

    getSelected() {
        const selected = [];
        this.rootNode.element.querySelectorAll(".selected").forEach(n => selected.push(n.item));
        return selected;
    }

    itemClicked(ev, node) {
        const metaKey = ev.metaKey || (ev.ctrlKey && (process.platform !== 'darwin'));
        if (!(metaKey || ev.shiftKey)) {
            this.clearSelect();
        }
        if (metaKey) {
            let parent = node.parentView;
            while (parent) {
                parent.setSelected(false);
                parent = parent.parentView;
            }
        } else if (ev.shiftKey) {
            const selected = this.getSelected();
            if (selected.length > 0) {
                const last = selected.pop();
                const parent = node.parentView.element;
                const entries = Array.from(parent.querySelectorAll('.entry'));
                if (entries.length > 0) {
                    const currentIndex = entries.indexOf(node.element);
                    const lastIndex = entries.indexOf(last.view.element);
                    const elements = entries.slice(lastIndex, currentIndex);
                    for (const elem of elements) {
                        let parent = elem.item.view.parentView;
                        while (parent) {
                            parent.setSelected(false);
                            parent = parent.parentView;
                        }
                        elem.item.view.setSelected(true);
                    }
                }
            }
        }

        return node.toggleSelection();
    }

    traversal(root, doing) {
      doing(root.item);
      if (root.item.children) {
        return Array.from(root.item.children).map((child) =>
          this.traversal(child.view, doing));
    }
  }

    toggleTypeVisible(type) {
      return this.traversal(this.rootNode, item => {
        if (item.type === type) {
          return item.view.toggle();
      }
      });
  }

    getNode(path, root = this.rootNode.item) {
        if (root.path === path) {
            return root;
        }
        if (root.children) {
            for (const child of root.children) {
                return this.getNode(path, child);
            }
        }
    }
    
    sortByName(ascending) {
      if (ascending == null) { ascending = true; }
      this.traversal(this.rootNode, item => {
        return (item.children != null ? item.children.sort((a, b) => {
          if (ascending) {
            return a.name.localeCompare(b.name);
          } else {
            return b.name.localeCompare(a.name);
        }
        }) : undefined);
      });
      return this.setRoot(this.rootNode.item);
  }

    sortByRow(ascending) {
      if (ascending == null) { ascending = true; }
      this.traversal(this.rootNode, item => {
        return (item.children != null ? item.children.sort((a, b) => {
          if (ascending) {
            return a.position.row - b.position.row;
          } else {
            return b.position.row - a.position.row;
        }
        }) : undefined);
      });
      return this.setRoot(this.rootNode.item);
  }

    clearSelect() {
        return this.element.querySelectorAll(".selected").forEach(elem => elem.classList.remove('selected'));
    }

    select(item) {
      this.clearSelect();
      return (item != null ? item.view.setSelected(true) : undefined);
  }
}