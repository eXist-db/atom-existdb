# Atom editor package for eXistdb

Provides:

* linting and autocomplete for XQuery scripts written for the eXist-db Native XML Database
* execution of XQuery scripts within the editor (`Ctrl-Enter`)
* symbols view to navigate to functions and variables in current editor (`Meta-Shift-R`)

## Installation Instructions

The package requires a small support app to be installed in the eXist-db instance you want to access, so you need to clone and build this first (requires apache ant):

```shell
git clone https://github.com/wolfgangmm/atom-editor-support.git
cd atom-editor-support
ant
```

This creates `atom-editor-0.1.xar` inside the `build/` directory. Deploy this into your eXist instance using the dashboard.

Now clone the main package, cd into it and run `apm install` once. This creates a subdirectory `node_modules`. Next, call `apm link .` to register the package with Atom. The complete steps:

```shell
git clone https://github.com/wolfgangmm/atom-existdb.git
cd atom-existdb
apm install
apm link .
```

## Usage

### Introduction
The basic idea is that you work on a directory on the file system which is a copy of a collection stored inside the database. For example, you may have created an app package inside the database using eXide, then synced it to a directory. Or you checked out an existing app into a directory from github, built a xar and uploaded it to eXist. In both cases the contents of your directory will mirror the contents of the collection inside the database.

When configured properly, the Atom eXistdb integration will immediately sync any change you make to a file in the directory into the database. To make this possible, the Atom eXistdb package needs some information about the current project (which corresponds to the root of the directory).

### Project Configuration
To configure the current project directory, create a file called `.existdb.json`, which may look as follows:

```json
{
    "server": "http://localhost:8080/exist",
    "user": "admin",
    "password": null,
    "root": "/db/apps/tei-simple",
    "sync": true,
    "ignore": ["*.json", ".git/**"]
}
```

where *server* is the URL of the root of the eXist instance. *user* and *password* are the credentials to use for accessing it. *root* defines the root collection to which any changes to local files will be uploaded if *sync* is set to "true". Finally, *ignore* is an array of path patterns defining files which should be ignored and won't be uploaded automatically.

Once you created the configuration file, open Atom on the root directory. If you already opened that directory in Atom, reload the window (`Ctrl-Alt-Meta L`).

### Features

#### Linting
Whenever you change an XQuery file, its contents will be forwarded to eXist and any compile errors will pop up in the editor window. This will not only detect errors in the current file, but also issues in modules it imports.

#### Autocomplete
While you type, autocomplete will talk to the database to get a list of functions or variable names which may match what you just typed. This will show all functions visible in the current context, including globally defined functions or functions in imported modules.

#### Navigating to functions and variables
Press `Meta-Shift-R` to see all functions and variables visible in the current context. Select one to navigate to it. This works across all files in the current project.

#### Execute XQuery scripts
You can send the XQuery code in the current editor to eXist for execution by pressing `Ctrl-Enter`. The result will be displayed in a new editor tab.

## Limitations

* Deleting, renaming, moving or copying a file via Atom's tree view or outside Atom will not apply that change to the database. You have to manually repeat the change inside eXist using eXide or the dashboard.

## Todo

* jump to the definition of a function, e.g. by shift-clicking on its name
* add a command to force a sync for a single file or all files in a directory without having it open in the editor. This would also help to address the issue with deletions etc.
