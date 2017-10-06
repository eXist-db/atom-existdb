/** @babel */

import {CompositeDisposable, Range, Emitter, File} from 'atom';
import request from 'request';
import path from 'path';
import fs from 'fs-plus';
import mime from 'mime';
import minimatch from 'minimatch';

export default class Sync extends Emitter {

    constructor(config, main) {
        super();
        this.config = config;
        this.main = main;
        this.disposables = new CompositeDisposable();

        const disposable = atom.project.onDidChangeFiles(events => {
            for (const event of events) {
                if (this.config.useSync()) {
                    const projectConfig = this.config.getProjectConfig(event.path);
                    if (!projectConfig.sync || this.ignorePath(projectConfig, event.path, projectConfig.path)) {
                        return;
                    }
                    switch (event.action) {
                        case "modified":
                            this.store(projectConfig, event.path, false);
                            break;
                        case "created":
                            if (fs.isDirectorySync(event.path)) {
                                this.createCollection(projectConfig, event.path);
                            } else {
                                this.store(projectConfig, event.path, true);
                            }
                            break;
                        case "deleted":
                            this.remove(projectConfig, event.path);
                            break;
                        case "renamed":
                            this.remove(projectConfig, event.oldPath);
                            this.store(projectConfig, event.path);
                            break;
                    }
                }
            }
        });
        this.disposables.add(disposable);
    }

    store(projectConfig, file, add) {
        const relPath = atom.project.relativizePath(file)[1];
        const connection = projectConfig.servers[projectConfig.sync.server];
        const url = connection.server + "/rest/" + projectConfig.sync.root + "/" + relPath;
        const contentType = mime.getType(path.extname(file));

        options = {
            uri: url,
            method: "PUT",
            auth: {
                user: connection.user,
                pass: connection.password || "",
                sendImmediately: true
            },
            headers: {
                "Content-Type": contentType
            }
        };

        this.emit("status", `Uploading ${file} to ${relPath}...`);

        const self = this;
        fs.createReadStream(file).pipe(
            request(
                options,
                (error, response, body) => {
                    if (error || !(response.statusCode == 200 || response.statusCode == 201)) {
                        atom.notifications.addError("Failed to upload " + file,
                            { detail: response ? response.statusMessage : error.code, dismissable: true })
                        response.pipe(process.stderr);
                        console.log("upload %s: %s: %s", response.statusMessage, file, body);
                    }
                    if (contentType == "application/xquery" && add) {
                        self.query(projectConfig, "sm:chmod(xs:anyURI('" + projectConfig.sync.root + "/" + file + "'), 'rwxr-xr-x')");
                    }
                    this.emit("status", "");
                }
            )
        );
    }

    remove(projectConfig, file) {
        const relPath = atom.project.relativizePath(file)[1];
        const connection = projectConfig.servers[projectConfig.sync.server];
        const url = connection.server + "/rest/" + projectConfig.sync.root + "/" + relPath;
        self = this;
        options = {
            uri: url,
            method: "DELETE",
            auth: {
                user: connection.user,
                pass: connection.password || "",
                sendImmediately: true
            }
        };
        this.emit("status", `Deleting ${file} ...`);
        request(
            options,
            (error, response, body) => {
                if (error) {
                    atom.notifications.addError("Failed to delete " + file, { detail: response ? response.statusMessage : error.code });
                }
                this.emit("status", "");
            }
        )
    }

    createCollection(projectConfig, dir) {
        const parentCol = path.dirname(dir);
        const name = path.basename(dir);
        const relPath = atom.project.relativizePath(parentCol)[1];
        this.emit("status", `Creating collection ${name} in ${relPath}`);
        this.query(projectConfig, "xmldb:create-collection('" + projectConfig.sync.root + "/" + relPath + "', '" + name + "')",
            (error, response) => {
                atom.notifications.addError("Failed to create collection " + relPath, { detail: response ? response.statusMessage : error.code });
                this.emit("status", "");
            },
            () => {
                this.emit("status", "");
            }
        );
    }
    query(projectConfig, query, onError, onSuccess) {
        var connection = projectConfig.servers[projectConfig.sync.server];
        var url = connection.server + "/rest/" + projectConfig.sync.root + "?_query=" + encodeURIComponent(query) + "&_wrap=no";
        options = {
            uri: url,
            method: "GET",
            json: true,
            auth: {
                user: connection.user,
                pass: connection.password || "",
                sendImmediately: true
            }
        };
        request(
            options,
            function(error, response, body) {
                if (error && onError) {
                    onError(error, response)
                } else if (onSuccess) {
                    onSuccess();
                }
            }
        )
    }

    ignorePath(config, currentPath, root) {
        if (config.sync.ignore) {
            for (var i = 0; i < config.sync.ignore.length; i++) {
                if (minimatch(currentPath, path.join(root, config.sync.ignore[i]), { matchBase: true })) {
                    return true;
                }
            }
        }
        return false;
    }

    destroy() {
        this.disposables.dispose();
    }
}
