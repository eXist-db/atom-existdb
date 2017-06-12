/** @babel */
import SelectListView from 'atom-select-list';
import util from './util';
import request from 'request';
import path from 'path';

export default class SymbolsView {

    constructor(config, main) {
        this.config = config;
        this.main = main;
        this.selectListView = new SelectListView({
            items: [],
            filterKeyForItem: (item) => {
                if (item.type == "variable") {
                    return item.name;
                }
                return item.signature;
            },
            elementForItem: (item) => {
                const li = document.createElement('li');
                const primary = document.createElement('div');
                primary.classList.add("primary-line");
                let span = document.createElement("span");
                span.classList.add("left-label");
                if (item.leftLabel) {
                    span.textContent = item.leftLabel;
                }
                primary.appendChild(span);
                
                span = document.createElement("span");
                if (item.type === "function") {
                    span.textContent = item.snippet.replace(/\$\{\d+:([^}]+)\}/g, "$1");
                } else {
                    span.textContent = item.text;
                }
                primary.appendChild(span);
                li.appendChild(primary);
                const secondary = document.createElement('div');
                secondary.classList.add("secondary-line");
                const dir = path.basename(item.path);
                secondary.textContent = `${dir} ${item.line > 0 ? item.line + 1 : ''}`;
                li.appendChild(secondary);
                return li;
            },
            didConfirmSelection: this.confirm.bind(this),
            didCancelSelection: this.cancel.bind(this)
        });
        this.element = document.createElement("div");
        this.element.classList.add("existdb-symbols-view");
        this.element.appendChild(this.selectListView.element);
        
        this.panel = atom.workspace.addModalPanel({item: this, visible: false});
    }

    confirm(item) {
        this.cancel();
        const editor = atom.workspace.getActiveTextEditor();
        if (item.path == editor.getPath()) {
            editor.scrollToBufferPosition([item.line, 0]);
            editor.setCursorBufferPosition([item.line, 0]);
        } else {
            this.open(editor, item.path, item);
        }
    }

    cancel() {
        this.selectListView.reset();
        this.selectListView.update({
            items: [],
            loadingMessage: "Loading symbols ..."
        });
        this.panel.hide();
        const activePane = atom.workspace.getCenter().getActivePane();
        activePane.activate();
    }

    open(editor, file, item) {
        this.main.open(editor, file, (newEditor) =>
            this.main.gotoLocalDefinition(item.name, newEditor)
        );
    }

    destroy() {
        this.selectListView.destroy();
        this.panel.destroy();
        this.element.remove();
    }

    show(editor) {
        this.panel.show();
        this.selectListView.focus();
        const localSymbols = this.getFileSymbols(editor);
        this.selectListView.update({
            items: localSymbols,
            loadingMessage: "Loading imported symbols ..."
        });
        this.getImportedSymbols(editor).then(
            (symbols) => {
                this.selectListView.update({
                    items: localSymbols.concat(symbols),
                    loadingMessage: null
                });
            },
            () => this.selectListView.update({loadingMessage: null, errorMessage: "Could not load imported symbols"})
        );
    }

    getFileSymbols(editor) {
        const symbols = [];
        for (const item of util.parseLocalFunctions(editor)) {
            symbols.push({
                type: item.type,
                name: item.name,
                snippet: item.snippet,
                path: item.file,
                line: item.line,
                text: item.name
            })
        }
        return symbols;
    }

    getImportedSymbols(editor) {
        return new Promise((resolve, reject) => {
            const params = util.modules(this.config, editor, false);
            const id = editor.getBuffer().getId();
            let connection;
            if (id.startsWith("exist:")) {
                connection = this.config.getConnection(id);
            } else {
                connection = this.config.getConnection(editor);
            }
            const options = {
                uri: connection.server + "/apps/atom-editor/atom-autocomplete.xql?" + params.join("&"),
                method: "GET",
                json: true,
                strictSSL: false,
                auth: {
                    user: connection.user,
                    pass: connection.password || "",
                    sendImmediately: true
                }
            }
            request(
                options,
                (error, response, data) => {
                    if (error || response.statusCode !== 200) {
                        reject();
                    } else {
                        resolve(data);
                    }
                }
            )
        });
    }
}
