/** @babel */
import XQueryProlog from './xq-prolog.js';

export function getSolutions(editor, msg, range, importsView) {
    const solutions = new Array();
    if (/No namespace defined/i.test(msg)) {
        solutions.push({
            title: "Import existing module",
            position: range,
            apply: () => importModule(editor, msg, importsView)
        });
        solutions.push({
            title: "Declare namespace",
            position: range,
            apply: () => declareNamespace(editor, msg)
        })
    }
    return solutions;
}

function importModule(editor, msg, importsView) {
    const m = /prefix\s+(.*)$/.exec(msg);
    const prefix = m[1];
    importsView.show(editor, prefix);
}

function declareNamespace(editor, msg) {
    const m = /prefix\s+(.*)$/.exec(msg);
    const prefix = m[1];
    const prolog = new XQueryProlog(editor);
    prolog.addNamespaceDecl(prefix);
}
