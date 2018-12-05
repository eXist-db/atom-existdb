Existdb = require '../lib/existdb'
_path = require 'path'


# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "Existdb", ->
  [workspaceElement, activationPromise] = []

  beforeEach ->
    workspaceElement = atom.views.getView(atom.workspace)
    activationPromise = atom.packages.activatePackage('existdb')

  describe "when the existdb:toggle-tree-view event is triggered", ->
    it "shows the database tree view", ->
      # Before the activation event the view is not on the DOM, and no panel
      # has been created
      expect(workspaceElement.querySelector('.existdb-tree')).not.toExist()

      # This is an activation event, triggering it will cause the package to be
      # activated.
      atom.commands.dispatch workspaceElement, 'existdb:toggle-tree-view'

      waitsForPromise ->
        activationPromise

      runs ->
        existdbElement = workspaceElement.querySelector('.existdb-tree')
        expect(existdbElement).toExist()

        expect(existdbElement.querySelectorAll('.collection').length).toBeGreaterThan(1)

# describe "Default config", ->
#   it "can be reached", ->
#     # expect("apples").toEqual("apples")
#     expect(_path.dirname(atom.config.getUserConfigPath()).toString().toEqual('~/.atom'))
