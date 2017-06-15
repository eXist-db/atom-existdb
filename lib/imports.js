/** @babel */
import SelectListView from 'atom-select-list';
import util from './util';
import request from 'request';
import path from 'path';
import XQueryProlog from './xq-prolog';

export default class ImportsView {

    constructor(config) {
        this.config = config;
        this.selectListView = new SelectListView({
            items: [],
            loadingMessage: "Loading modules for import ...",
            filterKeyForItem: (item) => {
                return item.prefix + item.source;
            },
            elementForItem: (item) => {
                const li = document.createElement('li');
                const primary = document.createElement('div');
                primary.classList.add("primary-line");
                let span = document.createElement("span");
                span.classList.add("left-label");
                span.textContent = item.prefix;
                primary.appendChild(span);

                span = document.createElement("span");
                span.textContent = item.namespace;
                primary.appendChild(span);
                li.appendChild(primary);
                const secondary = document.createElement('div');
                secondary.classList.add("secondary-line");
                secondary.textContent = item.source;
                li.appendChild(secondary);
                return li;
            },
            didConfirmSelection: this.confirm.bind(this),
            didCancelSelection: this.cancel.bind(this)
        });
        this.element = document.createElement("div");
        this.element.classList.add("existdb-imports-view");
        this.element.appendChild(this.selectListView.element);

        this.panel = atom.workspace.addModalPanel({item: this, visible: false});
    }

    confirm(item) {
        this.cancel();
        const editor = atom.workspace.getActiveTextEditor();
        const prolog = new XQueryProlog(editor);
        prolog.addImport(item.prefix, item.namespace, item.source);
    }

    cancel() {
        this.selectListView.reset();
        this.selectListView.update({
            items: [],
            loadingMessage: "Loading modules for import ...",
            errorMessage: null
        });
        this.panel.hide();
        const activePane = atom.workspace.getCenter().getActivePane();
        activePane.activate();
    }

    destroy() {
        this.selectListView.destroy();
        this.panel.destroy();
        this.element.remove();
    }

    show(editor, prefix) {
        this.panel.show();
        this.selectListView.focus();
        this.getModulesForImport(editor, prefix).then(
            (symbols) => {
                this.selectListView.update({
                    items: symbols,
                    loadingMessage: null
                });
            },
            (err) => this.selectListView.update({loadingMessage: null, errorMessage: "Could not load module list: " + err})
        );
    }

    getModulesForImport(editor, prefix) {
        return new Promise((resolve, reject) => {
            const collectionPaths = util.getCollectionPaths(editor, this.config);
            const prolog = new XQueryProlog(editor);
            const params = new Array();
            if (prefix) {
                params.push(`prefix=${prefix}`);
            }
            for (const module of prolog.importedModules) {
                params.push(`uri=${encodeURIComponent(module.uri)}`);
            }
            if (prolog.module) {
                params.push(`uri=${encodeURIComponent(prolog.module.uri)}`);
            }
            params.push(`path=${encodeURIComponent(collectionPaths.basePath)}`);
            const id = editor.getBuffer().getId();
            let connection;
            if (id.startsWith("exist:")) {
                connection = this.config.getConnection(id);
            } else {
                connection = this.config.getConnection(editor);
            }
            const options = {
                uri: connection.server + "/apps/atom-editor/module-import.xql?" + params.join("&"),
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
                        reject(response.statusMessage ? response.statusMessage : error);
                    } else {
                        resolve(data);
                    }
                }
            )
        });
    }
}
