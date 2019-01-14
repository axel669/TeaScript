const util = require("util");
const print = (obj) => console.log(
    util.inspect(
        obj,
        {showHidden: false, depth: null}
    )
);

const globalFuncs = {
    range: "var range=function(a,b){for(var c=2<arguments.length&&void 0!==arguments[2]?arguments[2]:1,d=[],e=a;0<c&&e<b||0>c&&e>b;)d.push(e),e+=c;return d};"
};

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

const formatBody = (body, scope, top = false) => {
    if (body.length === 0) {
        return "";
    }
    return `\n${body.map(line => genJS(line, scope, top) + ";").join("\n")}\n`;
};
const genScopeVars = (scope, parentScope) => {
    const vars = dif(scope.vars, parentScope.vars);
    if (vars.size === 0) {
        return "";
    }
    return `var ${Array.from(vars).join(", ")};\n`;
};

const genJS = (token, scope, ...args) => {
    if (codeGen[token.type] === undefined) {
        throw new Error(`No js transform defined for token type: ${token.type}`);
    }
    return codeGen[token.type](token, scope, ...args);
};
const codeGen = {
    "number": ({value}) => value.toString(),
    "string": ({text}, scope) => {
        if (text.length === 1 && typeof text[0] === "string" && text[0].indexOf("\n") === -1) {
            return `"${text[0]}"`;
        }
        const parts = text.map(
            t => typeof t === "string" ? t : `\$\{${genJS(t, scope)}\}`
        );
        return `\`${parts.join("").replace(/`/g, "\\`")}\``;
    },
    "regex": ({regex}) => regex,
    "bool": ({value}) => value.toString(),
    "null": () => "null",
    "undefined": () => "undefined",
    "identifier": ({name}) => name,
    "mutable-identifier": ({name}) => name,
    "group": ({expr}, scope) => `(${genJS(expr, scope)})`,
    "create-const": ({name, value}, scope) => `const ${genJS(name)} = ${genJS(value, scope)}`,
    "create-let": ({name, value}, scope) => `let ${genJS(name)} = ${genJS(value, scope)}`,
    "create-let-list": ({names}) => `let ${names.map(name => `${name} = undefined`).join(", ")}`,
    "function-decl": ({args, body, bindable}, parentScope, forceName = null) => {
        const scope = Scope(parentScope);
        const argDef = `(${args.map(i => genJS(i, scope)).join(', ')})`;
        const bodyLines = formatBody(body, scope, true);

        const vars = dif(scope.vars, parentScope.vars);
        let code = vars.size !== 0
            ? `{\nvar ${Array.from(vars).join(", ")};\n${bodyLines}}`
            : `{${bodyLines}}`;
        const binding = (scope.flags.generator === true && bindable === false)
            ? ".bind(this)"
            : "";
        let funcDef = bindable === false
            ? `${argDef} => `
            : `function ${argDef} `;
        if (forceName !== null) {
            funcDef = `${forceName}${argDef} `;
        }
        if (scope.flags.generator === true) {
            funcDef = `function* ${argDef}`;
        }
        if (scope.flags.async === true) {
            funcDef = `async ${funcDef}`;
        }

        if (bindable === false && forceName === null && body.length === 1 && body[0].op === "return" && vars.size === 0) {
            code = `(${code.substring(
                code.indexOf("return") + 7,
                code.lastIndexOf(";")
            )})`;
        }

        return `${funcDef}${code}${binding}`;
    },
    "unary": ({op, expr, standAlone}, scope) => {
        if (op === "await") {
            scope.flags.async = true;
        }
        if (op === "yield") {
            scope.flags.generator = true;
        }
        const exprStr = expr ? genJS(expr, scope) : "";
        return `${op} ${exprStr}`.trim();
    },
    "object": ({pairs}, scope) => `{${pairs.length === 0 ? "" : "\n"}${pairs.map(p => genJS(p, scope)).join(",\n")}}`,
    "function-call": ({name, nullCheck, args}, scope) => {
        if (nullCheck === "?") {
            if (name.type === "bin-op" && name.op === "?.") {
                const nullRef = genVarName(scope, "callref");
                const nullRef2 = genVarName(scope, "callref");

                const code = [
                    `${nullRef} = ${name.genJS(left, scope)}`,
                    `${nullRef2} = ${binaryOp({type: "identifier", name: nullRef}, name.right, name.op).toJS(scope)}`,
                    `${nullRef2} != null ? ${nullRef2}.bind(${nullRef})(${args.map(i => genJS(i, scope)).join(", ")}) : undefined`
                ].join(", ");
                return `(${code})`;
            }
            const ref = genVarName(scope, "nullref");
            return `((${ref} = ${genJS(name, scope)}) != null ? ${ref}(${args.map(i => genJS(i, scope)).join(", ")}) : undefined)`;
        }
        if (name.type === "bin-op" && name.op === "?.") {
            const newTok = {
                type: "bin-op",
                left: name.left,
                right: {
                    type: "function-call",
                    name: name.right,
                    nullCheck,
                    args
                },
                op: "?."
            };
            return genJS(newTok, scope);
        }
        return `${genJS(name, scope)}(${args.map(i => genJS(i, scope)).join(", ")})`;
    },
    "new-call": ({name, args}, scope) => `new ${genJS(name, scope)}(${args.map(i => genJS(i, scope)).join(", ")})`,
    "array": ({items}, scope) => `[${items.map(i => genJS(i, scope)).join(", ")}]`,
    "pair": ({accessMod, decorators, key, value, sep = ":"}, scope) => {
        const simpled = decorators.filter(dec => dec.type === "simple-decorator");
        const normald = decorators.filter(dec => dec.type !== "simple-decorator");
        const decoString = normald.length === 0
            ? ""
            : `${normald.map(d => genJS(d, scope)).join("\n")}\n`;
        if (accessMod !== "") {
            return `${decoString}${genJS(value, scope, `${accessMod} ${genJS(key, scope)}`, true)}`;
        }
        const valueStr = simpled.reduceRight(
            (current, deco) => genJS(deco, scope, current),
            genJS(value, scope)
        );
        return `${decoString}${genJS(key, scope)}${sep} ${valueStr}`;
    },
    "decorator": ({func}, scope) => `@${genJS(func, scope)}`,
    "simple-decorator": ({func}, scope, content) => `${genJS(func, scope)}(${content})`,
    "if": ({condition, body, alternate, isReturn}, scope, skipIIFE = false) => {
        const alt = alternate === null
            ? ""
            : `\nelse {\n${alternate.map(i => genJS(i, scope)).join(";\n")};\n}`;
        const ifexpr = `if (${genJS(condition, scope)}) {\n${body.map(i => genJS(i, scope)).join(";\n")};\n}${alt}`;
        return (isReturn === true && skipIIFE === false)
            ? `(() => {${ifexpr}})()`
            : ifexpr;
    },
    "break": ({value, label}, scope) => {
        if (value !== null) {
            return `return ${genJS(value, scope)}`;
        }
        if (label !== null) {
            return `break ${label}`;
        }
        return "break";
    },
    "bin-op": ({left, right, op}, scope) => {
        switch (true) {
            case op === "**":
                return `Math.pow(${genJS(left, scope)}, ${genJS(right, scope)})`;

            case op === "access":
                return `${genJS(left, scope)}[${genJS(right, scope)}]`;
            case op === "null-access": {
                const ref = genVarName(scope, "nullref");
                return `(((${ref} = ${genJS(left, scope)}) != null) ? ${ref}[${genJS(right, scope)}] : undefined)`;
            }

            case op === ".":
                return `${genJS(left, scope)}${op}${genJS(right, scope)}`;
            case op === "?.": {
                const ref = genVarName(scope, "nullref");
                return `(((${ref} = ${genJS(left, scope)}) != null) ? ${ref}.${genJS(right, scope)} : undefined)`;
            }

            case op === "!=" || op === "==":
                return `${genJS(left, scope)} ${op}= ${genJS(right, scope)}`;

            case op === "?0":
            case op === "??": {
                const ref = genVarName(scope, "nullref");
                const compValue = (op === "??") ? "null" : "0";
                return `((${ref} = ${genJS(left, scope)}) != ${compValue} ? ${ref} : ${genJS(right, scope)})`;
            }

            default:
                return `${genJS(left, scope)} ${op} ${genJS(right, scope)}`;
        }
    },
    "switch": ({expr, cases, def}, scope) => {
        const body = cases.map(i => genJS(i, scope)).join("\n");
        const defCase = def === null ? "" : `${genJS(def, scope)}\n`;
        const switchexpr = `switch (${genJS(expr, scope)}) {\n${body}\n${defCase}}`;
        const hasBreakValue = [...cases, def]
            .filter(item => item !== null)
            .findIndex(
                c => c.body.findIndex(tok => tok.type === 'break' && tok.value !== null) !== -1
            ) !== -1;

        if (hasBreakValue === true) {
            return `(() =>{${switchexpr}})()`;
        }
        return switchexpr;
    },
    "value-case": ({value, body}, scope) => {
        const bodyCopy = [...body];
        const needsScope = bodyCopy.findIndex(tok => tok.type.startsWith("create-")) !== -1;
        if (body.length === 0 || (body.length > 0 && body[body.length - 1].type !== 'break')) {
            bodyCopy.push({type: "break", value: null, label: null});
        }
        const bodyLines = bodyCopy.map(i => genJS(i, scope) + ";").join("\n");
        const bodyCode = needsScope === true ? `{${bodyLines}}` : bodyLines;
        return `case ${genJS(value, scope)}:\n${bodyCode}`;
    },
    "compare-case": ({expr, body}, scope) => {
        const bodyCopy = [...body];
        const needsScope = bodyCopy.findIndex(tok => tok.type.startsWith("create-")) !== -1;
        if (body.length === 0 || (body.length > 0 && body[body.length - 1].type !== 'break')) {
            bodyCopy.push({type: "break", value: null, label: null});
        }
        const bodyLines = bodyCopy.map(i => genJS(i, scope) + ";").join("\n");
        const bodyCode = needsScope === true ? `{${bodyLines}}` : bodyLines;
        return `case (${genJS(expr, scope)}):\n${bodyCode}`;
    },
    "default-case": ({body}, scope) => {
        const needsScope = body.findIndex(tok => tok.type.startsWith("create-")) !== -1;
        const bodyLines = body.map(i => genJS(i, scope) + ";").join("\n");
        const bodyCode = needsScope === true ? `{${bodyLines}}` : bodyLines;
        return `default:\n${bodyCode}`;
    },
    "for-object": ({key, value, expr, body}, scope) => {
        let loop;
        let forBody = [...body];

        if (value === null) {
            loop = `for (const ${genJS(key)} of Object.keys(${genJS(expr, scope)}))`;
        }
        else {
            const objRef = {
                type: "identifier",
                name: genVarName(scope, "ref")
            };
            forBody.unshift(
                {
                    type: "create-const",
                    name: value,
                    value: {
                        type: "bin-op",
                        left: objRef,
                        right: key,
                        op: "access"
                    }
                }
            );
            loop = `for (const ${genJS(key)} of Object.keys(${genJS(objRef, )} = ${genJS(expr, scope)}))`;
        }

        const bodyLines = forBody.map(i => genJS(i, scope) + ";").join("\n");

        return `${loop} {\n${bodyLines}\n}`;
    },
    "for-range": ({item, expr, body, mod}, scope) => {
        if (mod === true) {
            scope.flags.async = true;
        }
        const loop = `for${mod ? " await" : ""} (const ${genJS(item)} of ${genJS(expr, scope)})`;
        const bodyLines = body.map(i => genJS(i, scope) + ";").join("\n");
        return `${loop} {\n${bodyLines}\n}`;
    },
    "while": ({condition, body}, scope) =>
        `while (${genJS(condition, scope)}) {\n${body.map(i => genJS(i, scope) + ";").join("\n")}\n}`,
    "assignment": ({name, value, op}, scope) => `(${genJS(name, scope)} ${op} ${genJS(value, scope)})`,
    "expansion": ({expr}, scope) => `...${genJS(expr, scope)}`,
    "range": ({start, end, inc}, scope) => `range(${genJS(start, scope)}, ${genJS(end, scope)}, ${genJS(inc, scope)})`,
    "import": ({structure, source}, scope) => {
        if (structure === null) {
            return `import ${genJS(source)}`;
        }
        return `import ${structure} from ${genJS(source)}`;
    },
    "export": ({source, isDefault}, scope) => {
        const def = isDefault ? "default " : "";
        return `export ${def}${genJS(source, scope)}`;
    },
    "block": ({body}, scope) => `{\n${body.map(i => genJS(i, scope) + ";").join("\n")}\n}`,
    "not": ({expr}, scope) => `!${genJS(expr, scope)}`,
    "class": ({decorators, name, extend, body}, scope, top = false) => {
        const decoString = decorators.length === 0
            ? ""
            : `${decorators.map(d => genJS(d, scope)).join("\n")}\n`;
        const extension = extend ? ` extends ${genJS(extend, scope)}` : "";
        const className = name ? name : "";
        const [funcs, vars, funcDecos] = body.reduce(
            ([funcs, vars, funcDecos], entry) => {
                if (entry.type.startsWith("class-static") === false || entry.name === null) {
                    // console.log(entry.name || entry.value.name);
                    funcs.push(entry);
                    if (entry.decorators !== undefined && entry.decorators.length > 0) {
                        funcDecos.push([
                            entry.name === null,
                            entry.name || entry.value.name,
                            entry.decorators
                        ]);
                    }
                }
                else {
                    vars.push(entry);
                }
                return [funcs, vars, funcDecos];
            },
            [[], [], []]
        );
        const bodyLines = funcs.map(l => genJS(l, scope)).join("\n");
        const classBase = `class ${className}${extension} {\n${bodyLines}\n}`;
        const classCode = [classBase];
        const ref = (() => {
            if (className.length === 0) {
                return genVarName(scope, "_class");
            }
            if ((vars.length > 0 || funcDecos.length > 0) && top === false) {
                return genVarName(scope, "_class");
            }
            return className;
        })();
        // console.log(funcDecos);
        if (funcDecos.length > 0) {
            classCode.push(
                ...funcDecos.map(
                    ([isStatic, name, decos]) => {
                        const iref = (decorators.length > 0) ? genVarName(scope, "__class") : ref;
                        const base = isStatic === false ? `${iref}.prototype` : iref;
                        const decoList = decos.map(deco => genJS(deco.func, scope)).join(",");
                        const decoString = `[${decoList}].reduceRight((descriptor, decorator) => decorator(${base}, "${name}", descriptor), Object.getOwnPropertyDescriptor(${base}, "${name}"))`;
                        if (iref !== ref) {
                            classCode[0] = `${iref} = ${classBase}`;
                        }

                        return `Object.defineProperty(\n${base},\n"${name}",\n${decoString}\n)`;
                    }
                )
            );
        }
        if (vars.length > 0) {
            classCode.push(
                ...vars.map(
                    svar => `${ref}.${svar.name} = ${genJS(svar.value, scope)}`
                )
            );
        }
        // if (
        if (decorators.length > 0) {
            // const iref = genVarName("_class_i", scope);
            const decoClass = decorators.reduceRight(
                (last, deco) => `${genJS(deco.func, scope)}(${last})`,
                classCode[0]
            );
            classCode[0] = decoClass;
        }
        if (decorators.length === 0) {
            if (top === true) {
                return classCode.map(line => line + ";").join("\n");
            }
            // if (vars.length !== 0) {
        }
        if (top === true) {
            return `const ${className} = ${classCode.map(line => line + ";").join("\n")}`;
        }
        if (vars.length !== 0 || funcDecos.length !== 0) {
            return `(${ref} = ${classCode.join(",")}, ${ref})`;
        }
        return classCode.join("\n");
    },
    "class-static-member": ({name, value}, scope) => `static ${genJS(value, scope)}`,
    "class-func": ({name, decorators, args, body}, parentScope) => {
        const scope = Scope(parentScope);
        const argDef = `(${args.map(i => genJS(i, scope)).join(', ')}) `;
        const bodyLines = body.map(i => genJS(i, scope) + ";").join("\n");
        const decoString = decorators.length === 0
            ? ""
            : `${decorators.map(d => genJS(d, parentScope)).join("\n")}\n`;

        const vars = dif(scope.vars, parentScope.vars);
        const code = vars.size !== 0
            ? `var ${Array.from(vars).join(", ")};\n${bodyLines}`
            : bodyLines;
        let funcName = name;
        if (scope.flags.generator === true) {
            funcName = `*${funcName}`;
        }
        if (scope.flags.async === true) {
            funcName = `async ${funcName}`;
        }

        return `${funcName}${argDef}{\n${code}\n}`;
    },
    "jsx-prop": ({key, value}, scope) => {
        if (key === null) {
            return `{...${genJS(value, scope)}}`;
        }
        if (value === undefined) {
            return key;
        }
        return `${key}={${genJS(value, scope)}}`;
    },
    "jsx-self-closing": ({tag, props}, scope) => {
        return codeGen["jsx-tag"](
            {open: {tag, props}, children: []},
            scope
        );
    },
    "jsx-tag-open": ({tag, props}, scope) => `<${tag} ${props.map(p => genJS(p, scope)).join(' ')}>`,
    "jsx-tag-close": ({tag}, scope) => `</${tag}>`,
    "jsx-tag": ({open, children, close}, scope) => {
        const isHTML = open.tag.type === "identifier"
            && /^[a-z]+$/.test(open.tag.name) === true;
        const tagArg = isHTML === true ? JSON.stringify(open.tag.name) : genJS(open.tag, scope);

        const props = genJS(
            {
                type: "object",
                pairs: open.props.map(
                    prop => {
                        if (prop.key === null) {
                            return {
                                type: "expansion",
                                expr: prop.value
                            };
                        }
                        return {
                            type: "pair",
                            accessMod: "",
                            decorators: [],
                            key: {
                                type: "identifier",
                                name: prop.key
                            },
                            value: prop.value
                        };
                    }
                )
            },
            scope
        );
        const childArgs = children.map(
            child => genJS(child, scope)
        ).join(",\n");
        // console.log(childArgs);
        // console.log(children);

        return `React.createElement(\n${tagArg},\n${props},\n${childArgs})`;
    },
    "jsx-content": ({content}) => JSON.stringify(content.replace(/\\\{/g, "{")),
    "jsx-expression": ({expr}, scope) => genJS(expr, scope),
    "ternary": ({condition, truish, falsish}, scope) => `${genJS(condition, scope)} ? ${genJS(truish, scope)} : ${genJS(falsish, scope)}`,
    "try-catch": ({attempt, cancel, error, final}, parentScope) => {
        if (error === null) {
            error = [
                {type: "identifier", name: "error"},
                [{
                    type: "function-call",
                    name: {
                        type: "bin-op",
                        left: {type: "identifier", name: "console"},
                        right: {type: "identifier", name: "log"},
                        op: "."
                    },
                    nullCheck: "",
                    args: [{type: "identifier", name: "error"}]
                }]
            ];
        }
        const tryScope = Scope(parentScope);
        const catchScope = Scope(parentScope);
        const finallyScope = Scope(parentScope);

        const tryLines = attempt.map(i => genJS(i, tryScope) + ";").join("\n");
        const catchLines = error[1].map(i => genJS(i, catchScope) + ";").join("\n");
        const finallyLines = (final === null) ? [] : final.map(i => genJS(i, finallyScope) + ";").join("\n");

        const tryCode = `${genScopeVars(tryScope, parentScope)}${tryLines}`;
        const catchCode = `${genScopeVars(catchScope, parentScope)}${catchLines}`;
        const finallyCode = `${genScopeVars(finallyScope, parentScope)}${finallyLines}`;

        const finallyText = (final === null) ? "" : `\nfinally {\n${finallyLines}\n}`;

        parentScope.flags.async = tryScope.flags.async || catchScope.flags.async || finallyScope.flags.async;
        parentScope.flags.generator = tryScope.flags.generator || catchScope.flags.generator || finallyScope.flags.generator;

        return `try {\n${tryCode}\n}\ncatch (${genJS(error[0])}) {\n${catchCode}\n}${finallyText}`;
    },
    "construct": ({decorators, name, body}, scope) => {
        const checks = [
            [
                part =>
                    part.name === "new" && part.type === "construct-function",
                "_constructor"
            ],
            [
                part => part.type === "construct-var",
                "vars"
            ],
            [
                part => part.scope === null && part.accessMod === "",
                "publicAPI"
            ],
            [
                part => part.scope === null && part.accessMod !== "",
                "publicAccess"
            ],
            [
                part => part.scope === "#",
                "self"
            ]
        ];
        const parts = body.reduce(
            (parts, part) => {
                for (const [check, target] of checks) {
                    if (check(part) === true) {
                        parts[target].push(part);
                        break;
                    }
                }
                return parts;
            },
            {
                _constructor: [],
                vars: [],
                // funcs: [],
                accessors: [],
                publicAPI: [],
                publicAccess: [],
                self: []
            }
        );
        // const [args, constructBody] = parts._constructor === null
        const [args, constructBody] = parts._constructor.length === 0
            ? [[], []]
            : [parts._constructor[0].args, [...parts._constructor[0].body]];
        const argDef = `(${args.map(i => genJS(i, scope)).join(', ')})`;
        const createLines = constructBody.map(i => genJS(i, scope) + ";");
        // const functionLines = parts.funcs.map(
        //     (func) => `this.${func.name} = ${genJS({type: "function-decl", args: func.args, body: func.body, bindable: false}, scope)};`
        // );
        const collectionMap = acc => (console.log(acc), {
            type: "pair",
            accessMod: "",
            decorators: [],
            key: {type: "identifier", name: acc.name},
            value: {
                type: "object",
                pairs: [
                    {
                        type: "pair",
                        accessMod: "",
                        decorators: [],
                        key: {type: "identifier", name: "configurable"},
                        value: {type: "bool", value: "false"}
                    },
                    {
                        type: "pair",
                        accessMod: "",
                        decorators: [],
                        key: {type: "identifier", name: acc.accessMod || "get"},
                        value: {
                            type: "function-decl",
                            args: [],
                            body: (acc.accessMod === '') ? [acc] : acc.body,
                            bindable: false
                        }
                    }
                ]
            }
        });
        const collection = {
            type: "object",
            pairs: parts.publicAPI.map(collectionMap)
        };
        const accessors = {
            type: "object",
            pairs: parts.publicAccess.map(collectionMap)
        };
        const selfCollection = {
            type: "object",
            pairs: parts.self.map(collectionMap)
        };
        const staticVars = parts.vars.map(
            (svar) => `${name}.${svar.name} = ${genJS(svar.value, scope)}`
        );

        const constructBodyCode = [
            "const self = {};",
            "const publicAPI = {};",
            `Object.defineProperties(publicAPI, ${genJS(collection, scope)});`,
            `Object.defineProperties(self, ${genJS(selfCollection, scope)});`,
            "Object.defineProperties(self, Object.getOwnPropertyDescriptors(publicAPI));",
            `Object.defineProperties(publicAPI, ${genJS(accessors, scope)});`,
            // ...functionLines,
            ...createLines,
            `return publicAPI;`
        ].join("\n");

        const constructCode = decorators.reduceRight(
            (current, deco) => {
                return `${deco.genJS(func, scope)}(${current})`;
            },
            `function construct${argDef} {${constructBodyCode}}`
        );
        return `const ${name} = (() => {\nconst construct = ${constructCode}\nreturn (...args) => construct.apply({}, args);})();\n${staticVars.join(";\n")}`;
    },
    "negation": ({expr}, scope) => `(-(${genJS(expr, scope)}))`
};

const compileTree = (sourceTree, options) => {
    const {bin, imports, code, scope, globalCalls} = sourceTree;

    const compileScope = scope.copy();
    compileScope.options = options;

    const binCode = bin === null ? "" : genJS(bin, compileScope) + "\n";
    const importsCode = imports.map(i => genJS(i, compileScope));
    const transpiledCode = code.map(c => genJS(c, compileScope, true));

    const topLevelVars = dif(compileScope.vars, scope.vars);
    const tlvCode = topLevelVars.size > 0
        ? `var ${Array.from(topLevelVars).join(", ")}`
        : "";

    const allCode = [
        binCode,
        `"use strict"`,
        ...importsCode,
        ...Array.from(globalCalls).map(name => globalFuncs[name]),
        tlvCode,
        ...transpiledCode
    ].filter(l => l !== "")
    .concat([""])
    .join(";\n");
    return allCode;
};

module.exports = compileTree;
