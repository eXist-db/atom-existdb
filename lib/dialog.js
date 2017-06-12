/** @babel */
import {TextEditor} from 'atom';

class InputDialogView {
    
    constructor() {
        this.element = document.createElement('div');
        this.element.classList.add('existdb-input-dialog');
        this.promptText = document.createElement('div');
        this.element.appendChild(this.promptText);
        
        this.editor = new TextEditor({mini: true});
        this.element.appendChild(this.editor.element);
        // this.editor.element.addEventListener('blur', this.abort.bind(this));

        const bottomPanel = document.createElement('div');
        bottomPanel.classList.add('bottom-button-panel');
        
        const cancelBtn = document.createElement('button');
        cancelBtn.classList.add('btn');
        cancelBtn.textContent = "Cancel";
        cancelBtn.addEventListener("click", () => this.abort());
        bottomPanel.appendChild(cancelBtn);
        
        const okBtn = document.createElement('button');
        okBtn.classList.add('btn');
        okBtn.textContent = "OK";
        okBtn.addEventListener("click", () => this.confirm());
        bottomPanel.appendChild(okBtn);
        this.element.appendChild(bottomPanel);

        atom.commands.add(this.element, {
            'core:confirm': () => this.confirm(),
            'core:cancel': () => this.abort()
        });
        this.panel = atom.workspace.addModalPanel({item: this, visible: false});
    }
    
    prompt(promptText) {
        return new Promise((resolve, reject) => {
            this.onConfirm = resolve;
            this.promptText.textContent = promptText;
            this.panel.show();
            this.editor.element.focus();
        });
    }
    
    confirm() {
        const text = this.editor.getText();
        this.abort();
        this.onConfirm(text);
    }
    
    abort() {
        this.editor.setText("");
        this.panel.hide();
        const activePane = atom.workspace.getCenter().getActivePane();
        activePane.activate();
    }
    
    destroy() {
        this.editor.destroy();
        this.panel.destroy();
        this.element.remove();
    }
}

export let dialog = new InputDialogView();