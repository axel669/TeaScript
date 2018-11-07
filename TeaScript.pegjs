{
    /*
    const range = (start, end, inc = 1) => {
        const array = [];
        let current = start;
        while ( (inc > 0 && current < end) || (inc < 0 && current > end) ) {
            array.push(current);
            current += inc;
        }
        return array;
    };
    */
    const globalFuncs = {
        range: "var range=function(a,b){for(var c=2<arguments.length&&void 0!==arguments[2]?arguments[2]:1,d=[],e=a;0<c&&e<b||0>c&&e>b;)d.push(e),e+=c;return d};"
    };
    const globalFuncCalls = new Set();
    // let lastRef = null;

    const dif = (a, b) => new Set(Array.from(a).filter(i => b.has(i) === false));

    const usedVars = new Set();
    const genVarName = (scope, name) => {
        for (let i = 0; i < 1e6; i += 1) {
            const test = `${name}${i}`;
            if (scope.vars.has(test) === false) {
                scope.vars.add(test);
                return test;
            }
        }
    };

    const Scope = (baseScope = null) => {
        const vars = new Set(baseScope ? baseScope.vars : []);
        const flags = {async: false, generator: false};
        return {vars, flags};
    };
    const topLevelScope = Scope();

    const formatBody = (body, scope) => {
        if (body.length === 0) {
            return "";
        }
        return `\n${body.map(line => line.toJS(scope) + ";").join("\n")}\n`;
    };
    const genScopeVars = (scope, parentScope) => {
        const vars = dif(scope.vars, parentScope.vars);
        if (vars.size === 0) {
            return "";
        }
        return `var ${Array.from(vars).join(", ")};\n`;
    };

    const lastRef = (value, ref) => ({
        ref,
        toString() {
            return value;
        }
    });
    const mtoJS = t => t.toJS();
    const Token = {
        Number: value => ({
            type: "number",
            value,
            toJS(scope) {
                return value.toString();
            }
        }),
        String: text => ({
            type: "string",
            text,
            toJS(scope) {
                if (text.length === 1 && typeof text[0] === "string" && text[0].indexOf("\n") === -1) {
                    return `"${text[0]}"`;
                }
                const parts = text.map(
                    t => typeof t === "string" ? t : `\$\{${t.toJS(scope)}\}`
                );
                return `\`${parts.join("")}\``;
            }
        }),
        Regex: (regex) => ({
            type: "regex",
            regex,
            toJS(scope) {
                return regex;
            }
        }),
        Bool: (value) => ({
            type: "bool",
            value,
            toJS(scope) {
                return value.toString();
            }
        }),
        Null: () => ({type: "null", toJS(scope) {return "null";}}),
        Undefined: () => ({type: "undefined", toJS(scope) {return "undefined";}}),
        Identifier: name => ({
            type: "identifier",
            name,
            toJS(scope) {
                return name;
            }
        }),
        Grouped: expr => ({
            expr,
            toJS(scope) {
                return `(${expr.toJS(scope)})`;
            }
        }),
        MutableIdentifier: name => ({
            type: "mutable-identifier",
            name,
            toJS(scope) {
                return name;
            }
        }),
        Let: (name, value) => ({
            type: "create-const",
            name, value,
            toJS(scope) {
                return `const ${name.toJS()} = ${value.toJS(scope)}`;
            }
        }),
        Mut: (name, value) => ({
            type: "create-let",
            name, value,
            toJS(scope) {
                return `let ${name.toJS()} = ${value.toJS(scope)}`;
            }
        }),
        MutList: (names) => ({
            type: "create-let-list",
            names,
            toJS(scope) {
                const list = names.map(name => `${name} = undefined`)
                return `let ${list.join(", ")}`;
            }
        }),
        FunctionDecl: (args, body) => ({
            type: "function-decl",
            args, body,
            toJS(parentScope, forceName = null) {
                // const scope = new Set(parentScope);
                const scope = Scope(parentScope);
                const argDef = `(${args.map(i => i.toJS(scope)).join(', ')})`;
                // const bodyLines = body.map(i => i.toJS(scope)).join(";\n");
                const bodyLines = formatBody(body, scope);

                const vars = dif(scope.vars, parentScope.vars);
                const code = vars.size !== 0
                    ? `\nvar ${Array.from(vars).join(", ")};\n${bodyLines}`
                    : bodyLines;
                let funcDef = `${argDef} => `;
                if (forceName !== null) {
                    funcDef = `${forceName}${argDef} `;
                }
                if (scope.flags.generator === true) {
                    funcDef = `function* ${argDef}`;
                }
                if (scope.flags.async === true) {
                    funcDef = `async ${funcDef}`;
                }

                return `${funcDef}{${code}}`;
            }
        }),
        FunctionCall: (name, nullCheck, args) => ({
            type: "function-call",
            name, args, nullCheck,
            toJS(scope) {
                if (nullCheck === "?") {
                    if (name.type === "bin-op" && name.op === "?.") {
                        const nullRef = Token.Identifier(genVarName(scope, "callref")).toJS();
                        const nullRef2 = Token.Identifier(genVarName(scope, "callref")).toJS();
                        const code = [
                            `${nullRef} = ${name.left.toJS(scope)}`,
                            `${nullRef2} = ${binaryOp(Token.Identifier(nullRef), name.right, name.op).toJS(scope)}`,
                            `${nullRef2} != null ? ${nullRef2}.bind(${nullRef})(${args.map(i => i.toJS(scope)).join(", ")}) : undefined`
                        ].join(", ");
                        return `(${code})`;
                    }
                    const ref = Token.Identifier(genVarName(scope, "nullref"));
                    return `((${ref.toJS()} = ${name.toJS(scope)}) != null ? ${ref.toJS()}(${args.map(i => i.toJS(scope)).join(", ")}) : undefined)`;
                }
                if (name.type === "bin-op" && name.op === "?.") {
                    return binaryOp(
                        name.left,
                        Token.FunctionCall(name.right, nullCheck, args),
                        "?."
                    ).toJS(scope);
                }
                return `${name.toJS(scope)}(${args.map(i => i.toJS(scope)).join(", ")})`;
            }
        }),
        NewCall: (name, args) => ({
            type: "new-call",
            name, args,
            toJS(scope) {
                return `new ${name.toJS(scope)}(${args.map(i => i.toJS(scope)).join(", ")})`;
            }
        }),
        Unary: (type, expr, standAlone = true) => ({
            type, expr,
            toJS(scope) {
                if (type === "await") {
                    scope.flags.async = true;
                }
                if (type === "yield") {
                    scope.flags.generator = true;
                }
                return `${type} ${expr.toJS(scope)}`;
            }
        }),
        Array: items => ({
            type: "array",
            items,
            toJS(scope) {
                return `[${items.map(i => i.toJS(scope)).join(", ")}]`;
            }
        }),
        Object: pairs => ({
            type: "object",
            pairs,
            toJS(scope) {
                const p = pairs.map(i => i.toJS(scope));
                return `{\n${p.join(",\n")}\n}`;
            }
        }),
        Pair: (accessMod, decorators, key, value, sep = ":") => ({
            type: "pair",
            accessMod, decorators, key, value,
            toJS(scope) {
                const decoString = decorators.length === 0
                    ? ""
                    : `${decorators.map(d => d.toJS(scope)).join("\n")}\n`;
                if (accessMod !== "") {
                    return `${decoString}${value.toJS(scope, `${accessMod} ${key.toJS(scope)}`)}`;
                }
                return `${decoString}${key.toJS(scope)}${sep} ${value.toJS(scope)}`;
            }
        }),
        Null: () => ({
            type: "null",
            toJS(scope) {
                return "null";
            }
        }),
        If: (condition, body, alternate, sub = false) => ({
            type: "if",
            condition, body, alternate,
            toJS(scope) {
                const breakValue = token => token.type === "break" && token.value !== null;
                if (sub === false && (body.findIndex(breakValue) !== -1 || (alternate !== null && alternate.findIndex(breakValue) !== -1))) {
                    return Token.FunctionCall(
                        Token.Grouped(
                            Token.FunctionDecl(
                                [],
                                [Token.If(condition, body, alternate, true)]
                            )
                        ),
                        "",
                        []
                    ).toJS(scope);
                }
                const alt = alternate === null
                    ? ""
                    : `\nelse {\n${alternate.map(i => i.toJS(scope)).join(";\n")};\n}`;
                const ifexpr = `if (${condition.toJS(scope)}) {\n${body.map(i => i.toJS(scope)).join(";\n")};\n}${alt}`;
                return ifexpr;
            }
        }),
        Break: (value = null, label = null) => ({
            type: "break",
            value, label,
            toJS(scope) {
                if (value !== null) {
                    return `return ${value.toJS(scope)}`;
                }
                if (label !== null) {
                    return `break ${label}`;
                }
                return "break;";
            }
        }),
        Switch: (expr, cases, def) => ({
            type: "switch",
            expr, cases, def,
            toJS(scope) {
                const body = cases.map(i => i.toJS(scope)).join("\n");
                const defCase = def === null ? "" : `${def.toJS(scope)}\n`;
                const switchexpr = `switch (${expr.toJS(scope)}) {\n${body}\n${defCase}}`;
                const hasBreakValue = [...cases, def]
                    .filter(item => item !== null)
                    .findIndex(
                        c => c.body.findIndex(tok => tok.type === 'break' && tok.value !== null) !== -1
                    ) !== -1;

                if (hasBreakValue === true) {
                    return `(() =>{${switchexpr}})()`;
                }
                return switchexpr;
            }
        }),
        ValueCase: (value, body) => ({
            type: "value-case",
            value, body,
            toJS(scope) {
                const bodyCopy = [...body];
                if (body.length > 0 && body[body.length - 1].type !== 'break') {
                    bodyCopy.push(Token.Break());
                }
                const bodyLines = bodyCopy.map(i => i.toJS(scope)).join(";\n");
                return `case ${value.toJS(scope)}: {\n${bodyLines};\n}`;
            }
        }),
        CompareCase: (expr, body) => ({
            type: "compare-case",
            expr, body,
            toJS(scope) {
                const bodyCopy = [...body];
                if (body.length > 0 && body[body.length - 1].type !== 'break') {
                    bodyCopy.push(Token.Break());
                }
                const bodyLines = bodyCopy.map(i => i.toJS(scope)).join(";\n");
                return `case (${expr.toJS(scope)}): {\n${bodyLines};\n}`;
            }
        }),
        DefaultCase: (body) => ({
            type: "default-case",
            body,
            toJS(scope) {
                const bodyLines = body.map(i => i.toJS(scope)).join(";\n");
                return `default: {\n${bodyLines};\n}`;
            }
        }),
        ForObject: (key, value, expr, body) => ({
            type: "for-object",
            key, value, expr, body,
            toJS(scope) {
                let loop;
                let forBody = body;

                if (value === null) {
                    loop = `for (const ${key.toJS()} of Object.keys(${expr.toJS(scope)}))`;
                }
                else {
                    const objRef = Token.Identifier(genVarName(scope, "ref"));
                    forBody.unshift(
                        Token.Let(value, binaryOp(objRef, key, "access"))
                    );
                    loop = `for (const ${key.toJS()} of Object.keys(${objRef.toJS()} = ${expr.toJS(scope)}))`;
                }

                const bodyLines = forBody.map(i => i.toJS(scope)).join(";\n");

                return `${loop} {\n${bodyLines};\n}`;
            }
        }),
        ForIn: (item, expr, body) => ({
            type: "for-range",
            item, expr, body,
            toJS(scope) {
                const loop = `for (const ${item.toJS()} of ${expr.toJS(scope)})`;
                const bodyLines = body.map(i => i.toJS(scope)).join(";\n");
                return `${loop} {\n${bodyLines};\n}`;
            }
        }),
        While: (condition, body) => ({
            type: "while",
            condition, body,
            toJS(scope) {
                return `while (${condition.toJS(scope)}) {\n${body.map(i => i.toJS(scope)).join(";\n")};\n}`;
            }
        }),
        Comment: (text) => ({
            type: "comment",
            text,
            toJS(scope) {
                return `/* ${text} */`;
            }
        }),
        Expansion: (expr) => ({
            type: "exapnsion",
            expr,
            toJS(scope) {
                return `...${expr.toJS(scope)}`;
            }
        }),
        Range: (start, end, inc) => ({
            type: "range",
            start, end, inc,
            toJS(scope) {
                return `range(${start.toJS(scope)}, ${end.toJS(scope)}, ${inc.toJS(scope)})`;
            }
        }),
        Import: (structure, source) => ({
            type: "import",
            structure, source,
            toJS(scope) {
                if (structure === null) {
                    return `import ${source.toJS()}`;
                }
                return `import ${structure} from ${source.toJS()}`;
            }
        }),
        Export: (source, isDefault = false) => ({
            type: "export",
            source, isDefault,
            toJS(scope) {
                const def = isDefault ? "default " : "";
                return `export ${def}${source.toJS(scope)}`;
            }
        }),
        Block: (body) => ({
            type: "block",
            body,
            toJS(scope) {
                return `{\n${body.map(i => i.toJS(scope)).join(";\n")};\n}`;
            }
        }),
        Not: (expr) => ({
            type: "not",
            expr,
            toJS(scope) {
                return `!${expr.toJS(scope)}`;
            }
        }),
        Assignment: (name, value, op) => ({
            type: "assignment",
            name, value, op,
            toJS(scope) {
                return `(${name.toJS(scope)} ${op} ${value.toJS(scope)})`;
            }
        }),
        Decorator: (func) => ({
            type: "decorator",
            func,
            toJS(scope) {
                return `@${func.toJS(scope)}`;
            }
        }),
        Class: (decorators, name, extend, body) => ({
            type: "class",
            decorators, name, extend, body,
            toJS(scope) {
                const decoString = decorators.length === 0
                    ? ""
                    : `${decorators.map(d => d.toJS(scope)).join("\n")}\n`;
                const extension = extend ? ` extends ${extend.toJS(scope)}` : "";
                const className = name ? ` ${name}` : "";
                const bodyLines = body.map(l => l.toJS(scope)).join("\n");
                return `${decoString}class${className}${extension} {\n${bodyLines}\n}`;
            }
        }),
        ClassStaticVar: (name, value) => ({
            type: "class-static-var",
            name, value,
            toJS(scope) {
                return `static ${name} = ${value.toJS(scope)};`;
            }
        }),
        ClassFunction: (name, decorators, args, body) => ({
            type: "class-func",
            body,
            toJS(parentScope) {
                // const scope = new Set(parentScope);
                const scope = Scope(parentScope);
                const argDef = `(${args.map(i => i.toJS(scope)).join(', ')}) `;
                const bodyLines = body.map(i => i.toJS(scope) + ";").join("\n");
                const decoString = decorators.length === 0
                    ? ""
                    : `${decorators.map(d => d.toJS(parentScope)).join("\n")}\n`;

                const vars = dif(scope.vars, parentScope.vars);
                const code = vars.size !== 0
                    ? `var ${Array.from(vars).join(", ")};\n${bodyLines}`
                    : bodyLines;
                let funcName = name;
                if (scope.flags.generator === true) {
                    funcName = `${funcName}*`;
                }
                if (scope.flags.async === true) {
                    funcName = `async ${funcName}`;
                }

                return `${decoString}${funcName}${argDef}{\n${code}\n}`;
                // return `constructor(${args.toJS(scope)}) {\n${body.map(i => i.toJS(scope))}\n}`;
            }
        }),
        JSXProp: (key, value) => ({
            type: "jsx-prop",
            key, value,
            toJS(scope) {
                if (key === null) {
                    return `{...${value.toJS(scope)}}`;
                }
                if (value === undefined) {
                    return key;
                }
                return `${key}={${value.toJS(scope)}}`;
            }
        }),
        JSXSelfClosing: (tag, props) => ({
            type: "jsx-self-closing",
            tag, props,
            toJS(scope) {
                return `<${tag} ${props.map(p => p.toJS(scope)).join(' ')} />`;
            }
        }),
        JSXTagOpen: (tag, props) => ({
            type: "jsx-tag-open",
            tag, props,
            toJS(scope) {
                return `<${tag} ${props.map(p => p.toJS(scope)).join(' ')}>`;
            }
        }),
        JSXTagClose: (tag) => ({
            type: "jsx-tag-close",
            tag,
            toJS(scope) {
                return `</${tag}>`;
            }
        }),
        JSXTag: (open, children, close) => ({
            type: "jsx-tag",
            open, children, close,
            toJS(scope) {
                return `${open.toJS(scope)}\n${children.map(c => c.toJS(scope)).join("\n")}\n${close.toJS()}`;
            }
        }),
        JSXContent: (content) => ({
            type: "jsx-content",
            content,
            toJS(scope) {
                return content;
            }
        }),
        JSXExpression: (expr) => ({
            type: "jsx-expression",
            expr,
            toJS(scope) {
                return `{${expr.toJS(scope)}}`;
            }
        }),
        Ternary: (condition, truish, falsish) => ({
            type: "ternary",
            condition, truish, falsish,
            toJS(scope) {
                return `${condition.toJS(scope)} ? ${truish.toJS(scope)} : ${falsish.toJS(scope)}`;
            }
        }),
        Try: (attempt, cancel, error, final) => ({
            type: "try-catch",
            attempt, cancel, error, final,
            toJS(parentScope) {
                if (error === null) {
                    error = [
                        Token.Identifier("erorr"),
                        [Token.FunctionCall(
                            binaryOp(Token.Identifier("console"), Token.Identifier("error"), "."),
                            "",
                            [Token.Identifier("error")]
                        )]
                    ];
                }
                const tryScope = Scope(parentScope);
                const catchScope = Scope(parentScope);
                const finallyScope = Scope(parentScope);

                const tryLines = attempt.map(i => i.toJS(tryScope) + ";").join("\n");
                const catchLines = error[1].map(i => i.toJS(catchScope) + ";").join("\n");
                const finallyLines = (final === null) ? [] : final.map(i => i.toJS(finallyScope) + ";").join("\n");

                const tryCode = `${genScopeVars(tryScope, parentScope)}${tryLines}`;
                const catchCode = `${genScopeVars(catchScope, parentScope)}${catchLines}`;
                const finallyCode = `${genScopeVars(finallyScope, parentScope)}${finallyLines}`;

                const finallyText = (final === null) ? "" : `\nfinally {\n${finallyLines}\n}`;

                parentScope.flags.async = tryScope.flags.async || catchScope.flags.async || finallyScope.flags.async;
                parentScope.flags.generator = tryScope.flags.generator || catchScope.flags.generator || finallyScope.flags.generator;

                return `try {\n${tryCode}\n}\ncatch (${error[0].toJS()}) {\n${catchCode}\n}${finallyText}`;
            }
        })
    };
    const binaryOp = (left, right, op) => ({
        type: "bin-op",
        left, right, op,
        toJS(scope) {
            switch (true) {
                case op === "**":
                    return `Math.pow(${left.toJS(scope)}, ${right.toJS(scope)})`;

                case op === "access":
                    return `${left.toJS(scope)}[${right.toJS(scope)}]`;
                case op === "null-access": {
                    const ref = Token.Identifier(genVarName(scope, "nullref"));
                    return `(((${ref.toJS()} = ${left.toJS(scope)}) != null) ? ${ref.toJS()}[${right.toJS(scope)}] : undefined)`;
                }

                case op === ".":
                    return `${left.toJS(scope)}${op}${right.toJS(scope)}`;
                case op === "?.": {
                    const ref = Token.Identifier(genVarName(scope, "nullref"));
                    return `(((${ref.toJS()} = ${left.toJS(scope)}) != null ? ${ref.toJS()}.${right.toJS(scope)} : undefined)`;
                }

                case op === "!=" || op === "==":
                    return `${left.toJS(scope)} ${op}= ${right.toJS(scope)}`;

                case op === "??": {
                    const ref = Token.Identifier(genVarName(scope, "nullref"));
                    return `((${ref.toJS()} = ${left.toJS(scope)}) != null ? ${ref.toJS()} : ${right.toJS(scope)})`;
                }

                default:
                    return `${left.toJS(scope)} ${op} ${right.toJS(scope)}`;
            }
        }
    });
    const unaryOp = (expr, op) => ({
        type: "unary-op",
        expr, op,
        toJS(scope) {
            return `${op}${expr.toJS(scope)}`;
        }
    });

    const tailProcess = (head, tail) => tail.reduce(
        (current, [, op, , token]) => binaryOp(current, token, op),
        head
    );
    const listProcess = (first, rest, i) => first === null
        ? []
        : [
            first,
            ...rest.map(item => item[i]).filter(item => item !== null)
        ];
    const processTail = (first, tail) => {
        let current = first;
        for (const item of tail) {
            if (item.args !== undefined) {
                if (item.newCall === true) {
                    current = Token.NewCall(current, item.args);
                }
                else {
                    if (item.name !== undefined) {
                        current = binaryOp(current, Token.Identifier(item.name), `${item.nullish || ""}.`);
                    }
                    // console.log(current);
                    current = Token.FunctionCall(current, item.nullCheck, item.args);
                }
            }
            else {
                current = binaryOp(current, item.name, item.op);
            }
        }
        return current;
    };

    const tokenRegex = /^[a-zA-Z_$][a-zA-Z_$0-9]*$/;
}

TopLevel
    = _ imports:(_ Import __)* _ program:TopLevelProgram _ {
        try {
            const tree = [...imports.map(i => i[1]), ...program];

            const $code = (() => {
                try {
                    // const newScope = new Set(usedVars);
                    const newScope = Scope(topLevelScope);
                    const transpiled = [
                        ...Array.from(globalFuncCalls).map(name => globalFuncs[name]),
                        ...program.map(l => l.toJS(newScope))
                    ].join(";\n");

                    // const vars = dif(newScope, usedVars);
                    const vars = dif(newScope.vars, topLevelScope.vars);
                    const code = vars.size !== 0
                        ? `var ${Array.from(vars).join(", ")};\n${transpiled}`
                        : transpiled;
                    // const $code = [
                    return [
                        ...imports.map(i => i[1].toJS()),
                        code
                    ].join(";\n") + ";\n";
                }
                catch (e) {
                    console.error(e);
                }
                return undefined;
            })();

            // window.$code = $code;
            return {tree, code: $code};
        }
        catch (e) {console.error(e);}
    }
TopLevelProgram
    = _ first:(Export / Instruction)? rest:(__ (Export / Instruction))* _ {
        if (first === null) {
            return [];
        }
        const list = listProcess(first, rest, 1);
        return list;
    }

Program
    = _ first:Instruction? rest:(__ Instruction)* _ {
        if (first === null) {
            return [];
        }
        const list = listProcess(first, rest, 1);
        return list;
    }

Instruction
    = VariableCreate
    / Assignment
    / Expression
    / Block

Block = "{" _ body:Program _ "}" {return Token.Block(body);}

Import
    = "import" __ source:String {
        return Token.Import(null, source);
    }
    / "import" __ structure:ImportStructure __ "from" __ source:String {
        return Token.Import(structure, source);
    }
    / "import" __ star:ImportStar __ "from" __ source:String {
        return Token.Import(star, source);
    }
    / "import" __ name:ImportDefault parts:(_ "," _ (ImportStructure / ImportStar))? __ "from" __ source:String {
        const form = parts === null
            ? name
            : `${name}, ${parts[3]}`;
        return Token.Import(form, source);
    }
ImportName = name:Word {topLevelScope.vars.add(name); return name;}
ImportAs = source:Word __ "as" __ name:Word {topLevelScope.vars.add(name); return text();}
ImportStructure
    = "{" _ first:(ImportAs / ImportName) tail:(_ "," _ (ImportAs / ImportName))* "}" {
        const list = [first, ...tail.map(i => i[3])].join(", ");
        return `{${list}}`;
    }
ImportStar = "*" __ "as" __ name:Word {topLevelScope.vars.add(name); return text();}
ImportDefault = name:Word {topLevelScope.vars.add(name); return text();}

Export
    = "export" __ "default" __ expr:Expression {
        return Token.Export(expr, true);
    }
    / "export" __ exports:ExportList {
        return Token.Export(Token.Identifier(exports));
    }
ExportList = $("{" _ ExportEntry (_ "," _ ExportEntry)* _ "}")
ExportEntry = Word / $(Word __ "as" __ Word)

VariableCreate
    = "let" __ "mut" __ name:Word __ "=" __ value:(Ternary / Expression) {
        topLevelScope.vars.add(name);
        return Token.Mut(Token.Identifier(name), value);
    }
    / "let" __ "mut" __ name:Word tail:(_ "," _ "mut" __ Word)* {
        const list = [
            name,
            ...tail.map(i => i[5])
        ];
        for (const varName of list) {
            topLevelScope.vars.add(varName);
        }
        return Token.MutList(list);
    }
    / "let" __ name:Word __ "=" __ value:(Ternary / Expression) {
        topLevelScope.vars.add(name);
        return Token.Let(Token.Identifier(name), value);
    }
    / "let" __ "mut" __ name:Destructure __ "=" __ value:(Ternary / Expression) {
        return Token.Mut(Token.Identifier(name), value);
    }
    / "let" __ name:Destructure __ "=" __ value:(Ternary / Expression) {
        return Token.Let(name, value);
    }

Destructure
    = "[" first:(DestructureDefault / Identifier / "*" / Destructure) tail:(_ "," _ (DestructureDefault / Identifier / "*" / Destructure))* rest:(_ "," _ "..." Word)? "]" {
        const tokens = [
            first,
            ...tail.map(i => i[3])
        ]
        .map(
            tok => (tok === "*") ? Token.Identifier("") : tok
        );
        if (rest !== null) {
            topLevelScope.vars.add(rest[4]);
            tokens.push(Token.Identifier(`...${rest[4]}`));
            // tokens.push(`...${rest[4]}`);
        }
        for (const tok of tokens) {
            if (tokenRegex.test(tok.name) === true) {
                topLevelScope.vars.add(tok.name);
            }
        }
        return Token.Array(tokens);
        // return `[${tokens.map(i => i === "*" ? "" : i).join(", ")}]`;
        // return Token.Identifier(`[${tokens.map(i => i === "*" ? "" : i).join(", ")}]`);
    }
    / "{" first:(DestructureAs / DestructureNested / DestructureDefault / Identifier) tail:(_ "," _ (DestructureAs / DestructureNested / DestructureDefault / Identifier))* rest:(_ "," _ "..." Word)? "}" {
        const tokens = [
            first,
            ...tail.map(i => i[3])
        ];
        if (rest !== null) {
            topLevelScope.vars.add(rest[4]);
            tokens.push(Token.Identifier(`...${rest[4]}`));
            // tokens.push(`...${rest[4]}`);
        }
        for (const tok of tokens) {
            if (tokenRegex.test(tok.name) === true) {
                topLevelScope.vars.add(tok.name);
            }
        }
        return Token.Object(tokens);
        // return `{${tokens.map(i => i === "*" ? "" : i).join(", ")}}`;
    }
DestructureAs
    = name:Word __ "as" __ newName:Word {
        topLevelScope.vars.add(newName);
        return Token.Pair("", [], Token.Identifier(name), Token.Identifier(newName));
        // return `${name}: ${newName}`;
    }
DestructureNested
    = key:Word ":" __ value:Destructure {
        return Token.Pair("", [], Token.Identifier(key), value);
        // return `${key}: ${value}`;
    }
DestructureDefault
    = name:Word __ "=" __ value:(Number / String / IdentifierToken) {
        return Token.Pair("", [], Token.Identifier(name), value, "=");
        // return `${key} = ${value.toJS()}
    }

Expression
    = If
    / For
    / While
    / Switch
    / Try
    / Return
    / Await
    / Yield
    / Break
    / Logical
    / Class
    / NullCoalesce
    / JSX

Try
    = "try" __ "{" _ body:Program _ "}" error:Catch? final:Finally? {
            return Token.Try(body, null, error, final);
    }
Cancel
    = __ "cancel" __ "{" _ body:Program _ "}" {
        return body;
    }
Catch
    = __ "catch" __ name:Word __ "{" _ body:Program _ "}" {
        return [Token.Identifier(name), body];
    }
Finally
    = __ "finally" __ "{" _ body:Program _ "}" {
        return body;
    }

JSX = JSXSelfClosing / JSXTag
JSXSelfClosing
    = "<" tag:JSXTagName __ props:(JSXProp* __)? "/>" {
        return Token.JSXSelfClosing(tag, props ? props[0] : []);
    }
JSXTag
    = open:JSXTagOpen _ children:(_ (JSXContent / JSX) _)* _ close:JSXTagClose {
        return Token.JSXTag(open, children.map(c => c[1]), close);
    }
JSXTagOpen
    = "<" tag:JSXTagName props:(__ JSXProp*)? _ ">" {
        return Token.JSXTagOpen(tag, props ? props[1] : []);
    }
JSXTagClose
    = "</" tag:JSXTagName _ ">" {return Token.JSXTagClose(tag);}
JSXProp
    = _ key:Word "=" value:Token {
        return Token.JSXProp(key, value);
    }
    / _ key:Word "=" "{" _ value:Expression _ "}" {
        return Token.JSXProp(key, value);
    }
    / "{..." expr:(Token / Grouped) "}" {
        return Token.JSXProp(null, expr);
    }
    / _ key:Word {
        return Token.JSXProp(key, undefined);
    }
JSXTagName = $(Word ("." Word)*)
JSXContent
    = "{" _ expr:Expression _ "}" {return Token.JSXExpression(expr);}
    / content:$("\\{" / [^<\n])+ {return Token.JSXContent(content);}

Assignment
    = name:(IdentifierToken / Destructure {return Token.Identifier(text());}) __ op:("=" / "+=" / "-=" / "*=" / "/=" / "**=") __ value:(Ternary / Expression) {
        return Token.Assignment(name, value, op);
    }

Logical
    = head:Compare tail:( _ "&&" _ Compare)+ {
        return tailProcess(head, tail);
    }
    / head:Compare tail:( _ "||" _ Compare)+ {
        return tailProcess(head, tail);
    }
    / Compare

Compare
    = left:(NullCoalesce) __ op:("==" / "!=" / "<" / ">" / "<=" / ">=" / "instanceof") __ right:(NullCoalesce) {
        return binaryOp(left, right, op);
    }
    / "(" _ logical:Logical _ ")" {
        return Token.Grouped(logical);
    }

Ternary
    = condition:Logical __ "?" __ truish:Expression __ ":"__ falsish:Expression {
        return Token.Ternary(condition, truish, falsish);
    }
NullCoalesce
    = head:AddSub tail:(__ "??" __ AddSub)* {
        return tailProcess(head, tail);
    }
AddSub
    = head:MulDivMod tail:( __ ("+" / "-") __ MulDivMod)* {
        return tailProcess(head, tail);
    }

MulDivMod
    = head:Power tail:( __ ("*" / "/" / "%") __ Power)* {
        return tailProcess(head, tail);
    }

Power
    = head:(Token) tail:( __ "**" __ (Token))* {
        return tailProcess(head, tail);
    }

Grouped
    = "(" _ expr:(Expression) _ ")" {
        return Token.Grouped(expr);
    }

Negated
    = "-" expr:(Identifier / Grouped) {
        return Token.Grouped(unaryOp(expr, "-"));
    }
Not = "!" expr:(Identifier / Grouped) {return Token.Not(expr);}

FunctionDecl
    = "(" _ args:ArgList _ ")" __ "=>" __ "{" _ Null _ "}" {
        return Token.FunctionDecl(
            args,
            []
        );
    }
    / "(" _ args:ArgList _ ")" __ "=>" __ expr:(Ternary / Expression) {
        return Token.FunctionDecl(
            args,
            // [Token.Grouped(expr)]
            [Token.Unary("return", expr)]
        );
    }
    / "(" _ args:ArgList _ ")" __ "=>" __ "{" body:Program "}" {
        return Token.FunctionDecl(args, body);
    }
ArgList
    = first:Arg? rest:(_ "," _ Arg)* {
        return listProcess(first, rest, 3);
    }
Arg
    = name:(Identifier / Destructure) __ "=" __ expr:Expression {
        // return binaryOp(typeof name === "string" ? Token.Identifier(name) : name, expr, "=");
        return binaryOp(name, expr, "=");
    }
    /* / "mut" __ id:(Identifier / Destructure) {return Token.MutableIdentifier(id.name);} */
    / "mut" __ id:Identifier {return Token.MutableIdentifier(id.name);}
    /* / "mut" __ id:Destructure {return id;} */
    / Identifier
    /* / structure:Destructure {return Token.Identifier(structure);} */
    / Destructure
    / "..." id:Word {
        const name = Token.Identifier(id);
        return {
            type: "cheat",
            name,
            toJS(scope) {
                return `...${id}`;
            }
        };
    }

//  Modified token but i dont want to delete this yet
/* FunctionCall
    = name:(Grouped / Identifier) end:CallBit tail:(CallBit / AccessBit)* {
    = name:(Grouped / Identifier) end:CallBit {
        let current = end.newCall === true
            ? Token.NewCall(name, end.args)
            : Token.FunctionCall(name, end.nullCheck, end.args);

        // for (const item of tail) {
        //     if (item.args !== undefined) {
        //         if (item.newCall === true) {
        //             current = Token.NewCall(current, item.args);
        //         }
        //         else {
        //             current = Token.FunctionCall(current, item.nullCheck, item.args);
        //         }
        //     }
        //     else {
        //         current = binaryOp(current, item.name, item.op);
        //     }
        // }

        return current;
    } */
CallArgList
    = first:CallArg? rest:(_Separator CallArg)* {
        return listProcess(first, rest, 1);
    }
CallArg
    = Expression
    / "..." expr:Expression {
        return {
            type: "cheat",
            expr,
            toJS(scope) {
                return `...${expr.toJS(scope)}`;
            }
        };
    }
CallBit
    = nullCheck:"?"? "(" _ args:CallArgList _ ")" {
        return {nullCheck: nullCheck || "", args};
    }
    /* / _ op:("?"? ".") _ name:String _ nullCheck:"?"? "(" _ args:CallArgList _ ")" {
        return {
    } */
    / "*" "(" _ args:CallArgList _ ")" {
        return {newCall: true, args};
    }
AccessBit
    = _ op:$("?"? ".") _ name:Identifier {
        return {name, op};
    }
    / _ op:$("?"? ".") _ name:String {
        return {name, op: op === "." ? "access" : "null-access"};
    }

Typeof
    = "typeof" __ expr:(NullCoalesce / Logical) {return Token.Unary("typeof", expr, false);}

Return
    = "return" __ expr:(Ternary / Expression) {return Token.Unary("return", expr);}
Await
    = "await" __ expr:Expression {return Token.Unary("await", expr, false);}
Yield
    = "yield" __ expr:(Ternary / Expression) {return Token.Unary("yield", expr, false);}

Delete
    = "delete" __ expr:Expression {return Token.Unary("delete", expr);}

If
    = "if" __ condition:Logical __ "{" body:Program "}" els:(__ Else)? {
        return Token.If(condition, body, els ? els[1] : null);
    }
Else
    = "else" __ "{" body:Program "}" {
        return body;
    }

Break
    = "break" __ ":" label:Word {return Token.Break(null, label);}
    / "break" __ value:Expression {return Token.Break(value);}
    / "break" {return Token.Break();}

Switch
    = "switch" __ expr:NullCoalesce __ "{" _ cases:ValueCases _ def:DefaultCase? _ "}" {
        return Token.Switch(expr, cases, def);
    }
    / "switch" __ "{" _ cases:CompareCases _ def:DefaultCase? _ "}" {
        return Token.Switch(Token.Bool(true), cases, def);
    }
DefaultCase
    = "default" __ "{" _ body:Program _ "}" {
        return Token.DefaultCase(body);
    }
ValueCase
    = "case" __ value:Token __ "{" _ body:Program _ "}" {
        return Token.ValueCase(value, body);
    }
ValueCases
    = first:ValueCase? tail:( __ ValueCase)* {
        return listProcess(first, tail, 1);
    }
CompareCase
    = "case" __ condition:Logical __ "{" _ body:Program _ "}" {
        return Token.CompareCase(condition, body);
    }
CompareCases
    = first:CompareCase? tail:( __ CompareCase)* {
        return listProcess(first, tail, 1);
    }

For
    = "for" __ key:Word value:(_ "," _ Identifier)? __ "of" __ expr:Expression __ "{" body:Program "}" {
        return Token.ForObject(
            Token.Identifier(key),
            (value === null) ? null : value[3],
            expr,
            body
        );
    }
    / "for" __ key:Word __ "in" __ range:Range __ "{" _ body:Program _ "}" {
        return Token.ForIn(Token.Identifier(key), range, body);
    }
    / "for" __ key:ForInVars __ "in" __ expr:Expression __ "{" _ body:Program _ "}" {
        return Token.ForIn(key, expr, body);
    }
ForInVars
    = Identifier
    / "[" first:Word tail:(_ "," _ Word?)* "]" {
        return Token.Identifier(
            `[${[first, ...tail.map(i => i[3] || "")].join(", ")}]`
        );
    }
    / "{" first:Word tail:(_ "," _ Word?)* "}" {
        return Token.Identifier(
            `{${[first, ...tail.map(i => i[3] || "")].join(", ")}}`
        );
    }

While
    = "while" __ condition:Logical __ "{" _ body:Program _ "}" {
        return Token.While(condition, body);
    }
    / "loop" __ "{" _ body:Program _ "}" {
        return Token.While(Token.Bool(true), body);
    }

Class
    = decorators:(_ Decorator _)* "class" header:ClassHeader "{" _ body:ClassBody _ "}" {
        return Token.Class(
            decorators.map(d => d[1]),
            header.name,
            header.extend,
            body
        );
    }
ClassHeader
    = __ "extends" __ extend:Token __ {return {name: null, extend};}
    / __ name:Word __ "extends" __ extend:Token __ {return {name, extend};}
    / __ name:Word __ {return {name, extend: null};}
    / __ {return {name: null, extend: null};}
ClassBody
    = entries:(_ ClassEntry _)* {
        return entries.map(e => e[1]);
    }
ClassEntry
    = ClassStaticVar / ClassFunction
ClassStaticVar
    = "static" __ name:Word __ "=" __ value:Expression {
        return Token.ClassStaticVar(name, value)
    }
ClassFunction
    = decorators:(_ Decorator _)* name:Word func:FunctionDecl {
        return Token.ClassFunction(name, decorators.map(d => d[1]), func.args, func.body);
    }

Token
    = first:(
        Number
        / Typeof
        / String
        / Bool
        / Null
        / Undefined
        / FunctionDecl
        / Grouped
        / ArrayLiteral
        / ObjectLiteral
        / Identifier
        / Negated
        / Not
        / Regex
    ) tail:(CallBit / AccessBit / ArrayAccess)* {
        return processTail(first, tail);
        // let current = first;
        // for (const item of tail) {
        //     if (item.args !== undefined) {
        //         if (item.newCall === true) {
        //             current = Token.NewCall(current, item.args);
        //         }
        //         else {
        //             current = Token.FunctionCall(current, item.nullCheck, item.args);
        //         }
        //     }
        //     else {
        //         current = binaryOp(current, item.name, item.op);
        //     }
        // }
        // return current;
    }
IdentifierToken
    = first:Identifier tail:(AccessBit / ArrayAccess)* {
        return tail.reduce(
            (current, {op, name}) => binaryOp(current, name, op),
            first
        )
    }

Number
    = text:$("-"? [0-9]+ "." [0-9]+ ("e" ("+" / "-")? [0-9]+)?) {
        return Token.Number(parseFloat(text));
    }
    / text:$("-"? [0-9]+) {
        return Token.Number(parseInt(text, 10));
    }
    / text:$("0x" Hex+) {
        return Token.Number(parseInt(text, 16));
    }
    / text:$("0b" [01]+) {
        return Token.Number(parseInt(text, 2));
    }
    / text:$("0o" [0-7]+) {
        return Token.Number(parseInt(text, 8));
    }
Hex = [0-9a-f]i

String
    = text:('"' ("\\$" / ("${" Expression "}") / [^"\\] / "\\\"" / "\\u" . . . .)* '"') {
        const bits = text[1].reduce(
            ({current, all}, next, index) => {
                if (Array.isArray(next) === true) {
                    all.push(current.join(""));
                    all.push(next[1]);
                    current = [];
                }
                else {
                    current.push(next);
                }

                if (index === text[1].length - 1 && current.length > 0) {
                    all.push(current.join(""));
                }

                return {current, all};
            },
            {current: [], all: []}
        ).all;
        return Token.String(bits);
    }

Regex
    = text:$("/" ("\\/" / [^\/])+ "/" ("g" / "m" / "i")*) {
        return Token.Regex(text);
    }

Bool = value:("true" / "false") {return Token.Bool(value === "true");}
Undefined = "undefined" {return Token.Undefined();}
Null = "null" {return Token.Null();}

Identifier
    = _this:"@"? name:Word {
        let current = Token.Identifier(name);

        if (_this !== null) {
            current = binaryOp(Token.Identifier("this"), current, ".");
        }
        return current;
    }
    / "@" {return Token.Identifier("this");}
Word = $([a-zA-Z_$] [$a-zA-Z_\-0-9]*)
DotAccess
    = _ op:$("?"? ".") _ value:(Word / String) {
        if (value.type !== "string") {
            return {op, value: Token.Identifier(value)};
        }
        else {
            return {op: op === "." ? "access" : "null-access", value};
        }
    }
ArrayAccess
    = nullish:"?"? "[" value:Expression "]" {
        return {op: nullish === null ? "access" : "null-access", name: value};
    }
    / nullish:"?"? "[" range:SliceRange "]" {
        return {op: "slice", nullish, name: "slice", args: [range.start, range.end]};
    }

DotCall
    = _ op:$("?"? ".") _ name:Identifier call:CallBit {
        return {op, value: Token.FunctionCall(name, call.nullCheck, call.args)};
    }
ArrayLiteral
    /* = "[" _ first:ArrayEntry? rest:(_Separator ArrayEntry?)* _ "]" tail:(DotCall / DotAccess / ArrayAccess)* { */
    = "[" _ first:ArrayEntry? rest:(_Separator ArrayEntry?)* _ "]" {
        let current = Token.Array(listProcess(first, rest, 1));
        return current;
    }
    /* / "[" range:Range map:(":" __ FunctionDecl)? _ "]" tail:(DotCall / DotAccess / ArrayAccess)* { */
    / "[" range:Range map:(":" __ FunctionDecl)? _ "]" {
        const tok = Token.FunctionCall(Token.Identifier("range"), "", [range.start, range.end, range.inc]);
        let current = tok;

        if (map !== null) {
            current = Token.FunctionCall(
                binaryOp(tok, Token.Identifier("map"), "."),
                "",
                [map[2]]
            );
        }

        return current;
    }
ArrayEntry = Ternary / Expression / Expansion

Range
    = start:NullCoalesce "..." end:NullCoalesce inc:(__ "by" __ NullCoalesce)? {
        globalFuncCalls.add("range");
        return Token.Range(start, end, inc ? inc[3] : Token.Number(1));
    }
SliceRange
    = start:NullCoalesce "..." end:NullCoalesce {
        return {start, end};
    }
    / start:NullCoalesce "..." {
        return {start, end: Token.Undefined()};
    }
    / "..." end:NullCoalesce {
        return {start: Token.Number(0), end};
    }

ObjectLiteral
    = "{" _ first:ObjectEntry? rest:(_Separator ObjectEntry?)* _ "}" {
        return Token.Object(listProcess(first, rest, 1));
    }
ObjectEntry = Pair / Expansion
Pair
    = decorators:(_ Decorator _)* key:(Identifier / String / CalculatedKey) ":" l__ value:(Ternary / Expression) {
        const k = (key.type === "string" && key.text.length > 1) ? Token.Array([key]) : key;
        return Token.Pair("", decorators.map(d => d[1]), k, value);
    }
    / decorators:(_ Decorator _)* accessMod:(("get" / "set") __)? key:(Identifier / String / CalculatedKey) func:FunctionDecl {
        const k = (key.type === "string" && key.text.length > 1) ? Token.Array([key]) : key;
        return Token.Pair(accessMod ? accessMod[0] : "", decorators.map(d => d[1]), k, func);
    }
    / decorators:(_ Decorator _)* key:(IdentifierToken / Identifier) {
        const k = key.right === undefined ? key : key.right;
        return Token.Pair("", decorators.map(d => d[1]), k, key);
    }
CalculatedKey
    = "[" expr:Expression "]" {
        return Token.Array([expr]);
    }
Expansion
    = "..." expr:Expression {
        return Token.Expansion(expr);
    }

Decorator
    = "@" call:Token {
        return Token.Decorator(call);
    }
    /* / "@" name:Identifier {
        return Token.Decorator(name);
    } */

Comment
    = "//" text:$([^\n]*) {
        return Token.Comment(text);
    }
    / "/*" text:$((__ / "*" [^\/] / [^\*] . / [^\*])*) "*/" {
        return Token.Comment(text);
    }

__ "Whitespace"
    = (Comment / [ \t\r\n]+)+
_ "Optional Whitespace"
    = (Comment / [ \t\n\r]+)*
w__ "Whitespace Separator"
    = [ \t]* [\r\n]+ _
l__ "Optional Whitespace"
    = [ \t*]
_Separator
    = w__
    / _ "," _
