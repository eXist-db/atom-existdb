var mime = require('mime');
var chokidar = require('chokidar');
var request = require('request');
var path = require('path');
var fs = require('fs');

var watchers = [];

function message(action, message, detail) {
    if (process.send) {
        obj = {action: action, message: message};
        if (detail) {
            obj.detail = detail;
        }
        process.send(obj);
    } else {
        console.log("%s: %s", action, message);
    }
}

function init(configs) {
    mime.define({
        "application/xquery": ["xq", "xql", "xquery", "xqm"]
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
                store(filename, config);
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
            watchers.push(watcher);
        }
    });
}

function store(file, config) {
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

    message("status", "Uploading " + file + "...");

    fs.createReadStream(path.join(config.path, file)).pipe(
        request(
            options,
            function(error, response, body) {
                if (error || !(response.statusCode == 200 || response.statusCode == 201)) {
                    message("error", "Failed to upload " + file, response ? response.statusMessage : error.code);
                }
                message("status", "");
            }
        )
    );
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
            if (error) {
                onError(error, response)
            } else {
                onSuccess();
            }
        }
    )
}

function close() {
    watchers.forEach(function(watcher) {
        watcher.close();
    });
    watchers = [];
}

if (process.send) {
    process.on("message", function(obj) {
        if (obj.action === "init") {
            init(obj.configuration);
        } else if (obj.action === "close") {
            close();
        }
    });
} else {
    init([{
        path: "/Users/wolfgang/Source/apps/hsg-project/repos/hsg-shell",
        servers: {
            "localhost": {
                server: "http://localhost:8000/exist",
                user: "admin",
                password: ""
            }
        },
        sync: {
            server: "localhost",
            root: "/db/apps/hsg-shell",
            active: true,
            ignore: ['.existdb.json', '.git/**']
        }
    }]);
}