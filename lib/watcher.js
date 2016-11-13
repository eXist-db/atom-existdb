var mime = require('mime');
var chokidar = require('chokidar');
var request = require('request');
var path = require('path');
var fs = require('fs');
var walk = require('walk');
var minimatch = require('minimatch');

var watchers = {};

function message(action, message, detail) {
    message = message || "";
    if (process.send) {
        obj = {action: action, message: message};
        if (detail) {
            obj.detail = detail;
        }
        process.send(obj);
    } else if (message !== "") {
        console.log("%s: %s", action, message);
    }
}

function init(configs) {
    mime.define({
        "application/xquery": ["xq", "xql", "xquery", "xqm"],
        "application/xml": ["odd", "xconf", "tei"]
    });

    close();

    configs.forEach(function(config) {
        if (config.sync && config.sync.active) {
            watcher = chokidar.watch(config.path, {
                persistent: true,
                ignoreInitial: true,
                awaitWriteFinish: true,
                cwd: config.path,
                ignored: config.sync.ignore
            }).on('error', function(error) {
                message('error', "Directory watcher reported error: " + error);
            }).on('change', function(filename) {
                store(filename, config);
            }).on('add', function(filename) {
                store(filename, config, true);
            }).on('addDir', function(dir) {
                var parentCol = path.dirname(dir);
                var name = path.basename(dir);
                message("status", "Creating collection " + name + " in " + parentCol);
                query(config, "xmldb:create-collection('" + config.sync.root + "/" + parentCol + "', '" + name + "')",
                    function(error, response) {
                        message("error", "Failed to create collection " + dir, response ? response.statusMessage : error.code);
                    },
                    function() {
                        message("status", "");
                    }
                );
            }).on('unlink', function(filename) {
                remove(filename, config);
            }).on('unlinkDir', function(dir) {
                remove(dir, config);
            }).on('ready', function() {
                message("status", "");
            });
            message("status", "Initializing directory watcher on " + config.path + "...");
            watchers[config.path] = watcher;
        }
    });
}

function store(file, config, add) {
    var connection = config.servers[config.sync.server];
    var url = connection.server + "/rest/" + config.sync.root + "/" + file;
    var contentType = mime.lookup(path.extname(file));

    self = this;
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

    console.log("upload", "Uploading " + file + "...");

    fs.createReadStream(path.join(config.path, file)).pipe(
        request(
            options,
            function(error, response, body) {
                if (error || !(response.statusCode == 200 || response.statusCode == 201)) {
                    message("error", "Failed to upload " + path.join(config.path, file), response ? response.statusMessage : error.code);
                    response.pipe(process.stderr);
                    console.log("upload %s: %s: %s", response.statusMessage, file, body);
                }
                message("upload");
                if (contentType == "application/xquery" && add) {
                    query(config, "sm:chmod(xs:anyURI('" + config.sync.root + "/" + file + "'), 'rwxr-xr-x')");
                }
            }
        )
    );
}

function download(localPath, remotePath, config) {
    var connection = config.servers[config.sync.server];
    var stream = fs.createWriteStream(localPath);
    var url = connection.server + "/apps/atom-editor/load.xql?path=" + encodeURIComponent(config.sync.root + "/" + remotePath);
    var options = {
        uri: url,
        method: "GET",
        auth: {
            user: connection.user,
            pass: connection.password || "",
            sendImmediately: true
        }
    };
    message("status", "Downloading " + localPath + "...");
    request(options)
        .on("error", function(err) {
            message("error", "Failed to download " + remotePath, response ? response.statusMessage : error.code);
        })
        .pipe(stream);
}

function remove(file, config) {
    var connection = config.servers[config.sync.server];
    var url = connection.server + "/rest/" + config.sync.root + "/" + file;
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
    message("status", "Deleting " + file + "...");
    request(
        options,
        function(error, response, body) {
            if (error) {
                message("error", "Failed to delete " + file, response ? response.statusMessage : error.code);
            }
            message("status", "");
        }
    )
}

function query(config, query, onError, onSuccess) {
    var connection = config.servers[config.sync.server];
    var url = connection.server + "/rest/" + config.sync.root + "?_query=" + encodeURIComponent(query) + "&_wrap=no";
    self = this;
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

function sync(config, timestamp) {
    var connection = config.servers[config.sync.server];
    var url = connection.server +
        "/apps/atom-editor/sync.xql?root=" + encodeURIComponent(config.sync.root);
    if (timestamp) {
        url += "&timestamp=" + timestamp;
    }
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
                message("error", "Failed to retrieve contents for sync", response ? response.statusMessage : error.code);
            } else {
                pause(config.path);
                message("status", "Sync ...");
                try {
                    var paths = {};
                    syncRemote2Local(config, body.children, config.path, "", paths);
                    message("status", "Syncing local to remote...");
                    syncLocal2Remote(config, paths);
                } catch (e) {
                    message("error", e);
                } finally {
                    resume(config.path);
                    message("status");
                }
                message("sync", { timestamp: body.timestamp, path: config.path });
            }
        }
    )
}

function syncRemote2Local(config, resources, localPath, remotePath, paths) {
    resources.forEach(function(resource) {
        var p = path.join(localPath, resource.path);
        var remotePathAbs = remotePath ? [remotePath, resource.path].join("/") : resource.path;
        paths[p] = remotePathAbs;
        if (!ignorePath(config, remotePathAbs, config.sync.root) && fs.existsSync(p)) {
            var stats = fs.statSync(p);
            if (stats.isFile()) {
                var rtime = new Date(resource.lastModified);
                if (rtime.getTime() > stats.mtime.getTime()) {
                    download(p, remotePathAbs, config);
                } else if (rtime.getTime() < stats.mtime.getTime()) {
                    store(remotePathAbs, config, false);
                }
            }
        } else if (resource.children) {
            fs.mkdirSync(p);
        } else {
            download(p, remotePathAbs, config);
        }
        if (resource.children) {
            syncRemote2Local(config, resource.children, p, remotePathAbs, paths);
        }
    });
}

function syncLocal2Remote(config, paths) {
    var walker = walk.walkSync(config.path, {
        followLinks: false,
        listeners:{
            file: function(root, fileStats, next) {
                var p = path.join(root, fileStats.name);
                if (!ignorePath(config, p, config.path) && !paths[p]) {
                    console.log("path not found on server: %s", p);
                }
                next();
            }
        }
    });
    // walker.on("errors", function (root, nodeStatsArray, next) {
    //     message("status", "found error");
    //     next();
    // });
    // walker.on("file", function(root, fileStats, next) {
    //     // var p = path.join(root, fileStats.name);
    //     // message("status", p);
    //     // if (!ignorePath(config, p, config.path) && !paths[p]) {
    //     // }
    //     next();
    // });
}

function ignorePath(config, currentPath, root) {
    if (config.sync.ignore) {
        for (var i = 0; i < config.sync.ignore.length; i++) {
            if (minimatch(currentPath, path.join(root, config.sync.ignore[i]), { matchBase: true })) {
                return true;
            }
        }
    }
    return false;
}

function pause(path) {
    var watcher = watchers[path];
    if (watcher) {
        watcher.unwatch(path);
    }
}

function resume(path) {
    var watcher = watchers[path];
    if (watcher) {
        watcher.add(path);
    }
}

function exit() {
    close();
    process.exit(0);
}

function close() {
    for (var p in watchers) {
        if (watchers.hasOwnProperty(p)) {
            watchers[p].close();
        }
    }
    watchers = {};
}

if (process.send) {
    process.title = "atom-existdb";
    process.on("message", function(obj) {
        switch(obj.action) {
            case "init":
                init(obj.configuration);
                break;
            case "close":
                exit();
                break;
            case "sync":
                sync(obj.configuration, null);
                break;
        }
    });
} else {
    var args = process.argv.slice(2);
    var command = args[0];
    var configPath = path.resolve(args[1], ".existdb.json");
    console.log("command: %s config: %s", command, configPath);
    if (fs.existsSync(configPath)) {
        var contents = fs.readFileSync(configPath, 'utf8');

        var config = JSON.parse(contents);
        config.path = args[1];
        console.log("config: %o", config);
        switch (command) {
            case "sync":
                sync(config, null);
                break;
            case "watch":
                init([config]);
                break;
        }
    } else {
        console.log("no configuration found at %s", configPath);
    }
}
