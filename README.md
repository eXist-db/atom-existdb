# Atom editor package for eXistdb

This package contains a set of views and providers to support XQuery development using the [eXistdb Native XML Database](http://exist-db.org). In particular, the features are:

* tree view to browse the contents of the database
* open, edit and save files stored remotely in the database
* syntax highlighting and linting of XQuery scripts (based on [xqlint](https://github.com/wcandillon/xqlint))
* autocomplete showing all functions and variables which are in scope, including those from imported modules
* a hyperclick provider to navigate to the definition of a function, even if located in an imported module
* refactoring of variables
* XML auto-close tags, tag renaming
* execution of XQuery scripts within the editor
* symbols view to navigate to functions and variables which are in scope for the current XQuery

![First steps](https://raw.githubusercontent.com/wolfgangmm/atom-existdb/master/basic.gif)

## Dependencies

The eXistdb package requires a small support app to be installed in the database instance you want to access. You should be asked if you would like to install the support app the first time the package is activated. If this fails for any reason, install it manually by going to the eXistdb dashboard. In the package manager, search for an app called *Server side support scripts for the Atom editor package* and install it.

Linting and code navigation also depend on two Atom packages, which should be installed automatically unless they are already present:

1. linter
2. hyperclick

## Usage

### Introduction

The package supports two different workflows for developing with eXist:

1. directly work on the files stored *inside* the database, i.e. all development is done in eXist
2. Atom is called on a directory on the file system, which resembles an application stored in eXist. Editing is done in the directory but files are automatically synced to the database.

Most eXist users will be familiar with the first approach because this is how the in-browser IDE, eXide, works. (2) has advantages if you are working on an existing app, e.g. cloned from git. In this case, you deploy the app once, configure the automatic sync and continue to edit files in the file system. We'll cover this workflow below. See the section on *Automatic Sync*.

### Getting Started

When activated the first time, the package tries to detect if it can connect to an eXist server at the default location and if the server-side support app is installed on the database instance (see the first screencast above). By default, the package assumes that eXist can be reached using the URL: http://localhost:8080/exist, and the password for the admin user is empty.

If you changed the default eXist configuration or would like to connect to a different instance, select "Edit Server Configuration" from the packages menu or run the `existdb:edit-configuration` command. The configuration file is a simple JSON file:

```json
{
    "servers": {
        "localhost": {
            "server": "http://localhost:8080/exist",
            "user": "admin",
            "password": ""
        }
    }
}
```

The "servers" object is a dictionary mapping server names to connection details for each server available. After changing this file, you may need to call the *Reconnect* command from the package menu in Atom.

If the server-side support app is not installed on the selected server instance, you will be asked to install it. Just answer with "Yes" and the app will be installed automatically.

Once the package is activated, you should see the database browser tree view on either the left or right side of the Atom editor window. If not, please select *Toggle Database View* from the package menu (or press `cmd-alt-e` on mac, `ctrl-alt-e` on windows).

Clicking on any resource in the database browser will open the remote file for editing in an Atom editor tab. Behind the scenes, the resource is downloaded and stored into a temporary directory. The connection with the remote resource is preserved though, so pressing save in the editor will reupload the changed content into the database. This should also work across restarts of Atom: the package detects if you had previously opened files stored in eXist and re-downloads them upon restart.

A right-click on a resource or collection in the database browser opens a context menu from which one can

* create new collections or resources
* delete resources
* reindex a collection
* refresh the collection tree

### Editor Features

#### Autocomplete
While you type, autocomplete will talk to the database to get a list of functions or variable names which are in scope and may match what you just typed. This includes all functions and variables which are visible to your current code.

Concerning local variables, autocomplete looks at the XQuery syntax tree corresponding to the current position of the cursor to determine which variables would be in scope.

#### Linting
Whenever you change an XQuery file, its contents will be forwarded to eXist and any compile errors will pop up in the editor window. This will not only detect errors in the current file, but also issues in modules it imports.

In addition to server-side compilation, xqlint will be called in the background to provide hints and alerts for the currently open file. The eXistdb package combines those with the feedback coming from the eXist server.

#### Navigate to a function or variable definition
The package includes a provider for *hyperclick*: keep the `ctrl` or `command` key pressed while moving the mouse over a function call or variable name and it should be highlighted. Clicking on the highlighted range should navigate to the definition of the function or variable, given that the source location of the corresponding XQuery module is known to the XQuery engine (obviously it won't work for the standard Java modules compiled into eXist). If the declaration resides in a different file, it will be opened in a new editor tab.

Just in case hyperclick doesn't work for you: place the cursor inside a function call or variable and press `cmd-alt-g` or `ctrl-alt-g`.

#### Symbol browser
To quickly navigate to the definition of a function or variable, you can also use the symbol browser: press `cmd-ctrl-r` or `ctrl-shift-r` to get a popup showing all functions and variables which are visible to the code currently open in the editor.

Type a few characters to limit the list to functions or variable containing that string sequence. Press return to jump to a highlighted item.

#### Refactoring
You will notice that if you place the cursor inside a variable name, other occurrences of the same variable within the current scope will be highlighted. To rename the variable, press `alt-cmd-r` or `ctrl-shift-r`. This will select all occurrences and you can type as usual to change them all simultaneously. Once you're done, press `ESC` to get back to the single cursor.

![XML Editing](https://raw.githubusercontent.com/wolfgangmm/atom-existdb/master/refactor.gif)

#### Expand Selection
Pressing `alt-up` will expand the current selection to the closest XQuery expression, respecting XQuery semantics. Repeatedly press `alt-up` to select larger blocks.

### XML Editing in XQuery
* open XML tags are closed automatically if you press `</` inside an XML context
* changing the name of a tag will also change the corresponding opening or closing tag

![XML Editing](https://raw.githubusercontent.com/wolfgangmm/atom-existdb/master/xml-edit.gif)

#### Execute XQuery scripts
You can send the XQuery code in the current editor to eXist for execution by pressing `ctrl-enter` (mac) or `alt-shift-enter` (windows/linux). The result will be displayed in a new editor tab. Obviously this will only work for XQuery main modules.

![Executing query](https://raw.githubusercontent.com/wolfgangmm/atom-existdb/master/run.gif)

### Using the File Tree View
Inside Atom's file tree pane, right clicking will show a subcategory *existdb* in the context menu for files and directories.

* _Upload Selected_ will upload any selected files to the database collection highlighted in the DB view
* _Deploy Package_ is shown if you click on a `.xar` file (which is eXist's format for installable packages). Selecting it will install the
xar into the database using eXist's package management features.

### Automatic Sync
Automatic sync will start a background thread which keeps watching the current project directory for changes. Any change will be immediately uploaded to the corresponding target collection in the database. This means you can work on the files in the file system as you would usually do in Atom, though it even detects changes happening outside the editor, e.g. if you copy or remove files.

To get started, open Atom on the root directory containing the source code of the eXist app you're working on. Atom projects are directory-based, so whatever directory you choose will become the root of your project.

Next, right click on the project root in the file tree and select *Edit Configuration for Current Project* (or use the existdb package menu). This creates a configuration file called `.existdb.json` in your project root:

```json
{
    "servers": {
        "localhost": {
            "server": "http://localhost:8080/exist",
            "user": "admin",
            "password": ""
        }
    },
    "sync": {
        "server": "localhost",
        "root": "/db/apps/atom-editor",
        "active": true,
        "ignore": [
            ".existdb.json",
            ".git/**"
        ]
    }
}
```

The "servers" configuration is identical to the global config file, but there's an additional property "sync", which configures the mapping between the project directory and a collection on the server:

Property | Description
--- | ---
server  | the name of the server entry to connect to
root | the root collection to sync with
active | sync will only be active if this is set to true
ignore | an array of file path patterns which should not be synced

### Workflow for Working on a Cloned Repo
Most of the time you will probably use automatic sync on an eXistdb application package you cloned from git. In this case, the workflow to get started would be as follows:

1. clone the repository into a local directory
2. build the xar and deploy it into eXistdb
3. configure automatic sync on the project
4. start coding
5. commit your changes from the directory as usually

### Caveats
Changes made to the project directory while Atom is closed will not be detected and thus not synced to the database. Future versions of the package may contain a "sync upon startup" feature.

## Development

### Building from source

Clone the main package, cd into it and run `apm install` once. This creates a subdirectory `node_modules`. Next, call `apm link .` to register the package with Atom. The complete steps:

```shell
git clone https://github.com/wolfgangmm/atom-existdb.git
cd atom-existdb
apm install
apm link .
```

You may also want to clone and build the server-side support app:

```shell
git clone https://github.com/wolfgangmm/atom-editor-support.git
cd atom-editor-support
ant
```

This creates `atom-editor-0.1.xar` inside the `build/` directory. Deploy this into your eXist instance using the dashboard.
