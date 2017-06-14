/** @babel */
import XQUtils from './xquery-helper';
import ASTVisitor from './visitor';

export default class XQueryProlog extends ASTVisitor {

    constructor(editor) {
        super();
        this.editor = editor;
        this.importedModules = new Array();
        const ast = editor.getBuffer()._ast;

        this.visit(ast, this);
    }

    addImport(prefix, uri, at) {
        let code = `import module namespace ${prefix}="${uri}"`;
        if (at) {
            code += ` at "${at}"`;
        }
        code += ';';
        const lastLine = this.importedModules[this.importedModules.length - 1].line;
        this.editor.setCursorBufferPosition([lastLine, 0]);
        this.editor.moveToEndOfLine();
        this.editor.insertNewline();
        this.editor.insertText(code);
    }

    Prolog(prolog) {
        this.prolog = prolog;
        this.visitChildren(prolog, this);
    }

    VersionDecl(decl) {
        this.version = decl;
    }

    ModuleImport(modImport) {
        const uris = XQUtils.findChildren(modImport, 'URILiteral');
        const props = {
            "uri": uris[0].value,
            "line": modImport.pos.el
        };
        if (uris.length > 1) {
            props.at = uris[1].value;
        }
        this.importedModules.push(props);
    }
}
