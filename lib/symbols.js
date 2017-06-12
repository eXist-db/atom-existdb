/** @babel */
import SelectListView from 'atom-select-list';
import XQUtils from './xquery-helper';
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
                if (item.type == "variable") {
                    primary.textContent = item.name;
                } else {
                    primary.textContent = item.signature;
                }
                li.appendChild(primary);
                const secondary = document.createElement('div');
                secondary.classList.add("secondary-line");
                const dir = path.basename(item.file)
                secondary.textContent = `${dir} ${item.line > 0 ? item.line + 1 : ''}`;
                li.appendChild(secondary);
                return li;
            },
            didConfirmSelection: this.confirm.bind(this),
            didCancelSelection: this.cancel.bind(this)
        });
        this.panel = atom.workspace.addModalPanel({item: this.selectListView, visible: false});
    }

    confirm(item) {
        this.cancel();
        const editor = atom.workspace.getActiveTextEditor();
        if (item.file == editor.getPath()) {
            editor.scrollToBufferPosition([item.line, 0]);
            editor.setCursorBufferPosition([item.line, 0]);
        } else {
            this.open(editor, item.file, item);
        }
    }

    cancel() {
        this.selectListView.reset();
        this.selectListView.update({
            items: [],
            loadingMessage: "Loading symbols ..."
        });
        this.panel.hide();
    }

    open(editor, file, item) {
        this.main.open(editor, file, (newEditor) =>
            this.main.gotoLocalDefinition(item.name, newEditor)
        );
    }

    destroy() {
        this.selectListView.destroy();
        this.panel.destroy();
    }

    show(editor) {
        this.panel.show();
        this.selectListView.focus();
        const localSymbols = this.getFileSymbols(editor);
        this.selectListView.update({
            items: localSymbols,
            loadingMessage: "Loading imported symbols ..."
        });
        this.getImportedSymbols(editor).then((symbols) => {
            this.selectListView.update({
                items: localSymbols.concat(symbols),
                loadingMessage: null
            });
        });
    }

    getFileSymbols(editor) {
        return util.parseLocalFunctions(editor);
    }

    getImportedSymbols(editor) {
        return new Promise((resolve, reject) => {
            params = util.modules(this.config, editor, false);
            id = editor.getBuffer().getId();
            if (id.startsWith("exist:")) {
                connection = this.config.getConnection(id);
            } else {
                connection = this.config.getConnection(editor);
            }
            options = {
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
                    console.log(data);
                    const symbols = [];
                    for (const item of data) {
                        symbols.push({
                            type: item.type,
                            name: item.name,
                            signature: item.text,
                            line: -1,
                            file: item.path
                        });
                    }
                    resolve(symbols);
                }
            )
        });
    }
}
