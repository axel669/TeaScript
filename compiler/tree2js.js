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
const globalFuncCalls = new Set();

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
    return `\n${body.map(line => genJS(line, scope) + ";").join("\n")}\n`;
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
        const bodyLines = formatBody(body, scope);

        const vars = dif(scope.vars, parentScope.vars);
        const code = vars.size !== 0
            ? `\nvar ${Array.from(vars).join(", ")};\n${bodyLines}`
            : bodyLines;
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

        return `${funcDef}{${code}}`;
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
    "object": ({pairs}, scope) => `{${pairs.map(p => genJS(p, scope)).join(",\n")}}`,
    "function-call": ({name, nullCheck, args}, scope) => {
        if (nullCheck === "?") {
            if (name.type === "bin-op" && name.op === "?.") {
                const nullRef = Token.Identifier(genVarName(scope, "callref")).toJS();
                const nullRef2 = Token.Identifier(genVarName(scope, "callref")).toJS();
                const code = [
                    `${nullRef} = ${name.genJS(left, scope)}`,
                    `${nullRef2} = ${binaryOp(Token.Identifier(nullRef), name.right, name.op).toJS(scope)}`,
                    `${nullRef2} != null ? ${nullRef2}.bind(${nullRef})(${args.map(i => genJS(i, scope)).join(", ")}) : undefined`
                ].join(", ");
                return `(${code})`;
            }
            const ref = Token.Identifier(genVarName(scope, "nullref"));
            return `((${genJS(ref, )} = ${genJS(name, scope)}) != null ? ${genJS(ref, )}(${args.map(i => genJS(i, scope)).join(", ")}) : undefined)`;
        }
        if (name.type === "bin-op" && name.op === "?.") {
            return binaryOp(
                name.left,
                Token.FunctionCall(name.right, nullCheck, args),
                "?."
            ).toJS(scope);
        }
        return `${genJS(name, scope)}(${args.map(i => genJS(i, scope)).join(", ")})`;
    },
    "new-call": ({name, args}, scope) => `new ${genJS(name, scope)}(${args.map(i => genJS(i, scope)).join(", ")})`,
    "array": ({items}, scope) => `[${items.map(i => genJS(i, scope)).join(", ")}]`,
    "pair": ({accessMod, decorators, key, value, sep}, scope) => {
        const simpled = decorators.filter(dec => dec.type === "simple-decorator");
        const normald = decorators.filter(dec => dec.type !== "simple-decorator");
        const decoString = normald.length === 0
            ? ""
            : `${normald.map(d => genJS(d, scope)).join("\n")}\n`;
        if (accessMod !== "") {
            return `${decoString}${genJS(value, scope, `${accessMod} ${genJS(key, scope)}`)}`;
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
                const ref = Token.Identifier(genVarName(scope, "nullref"));
                return `(((${genJS(ref, )} = ${genJS(left, scope)}) != null) ? ${genJS(ref, )}[${genJS(right, scope)}] : undefined)`;
            }

            case op === ".":
                return `${genJS(left, scope)}${op}${genJS(right, scope)}`;
            case op === "?.": {
                const ref = Token.Identifier(genVarName(scope, "nullref"));
                return `(((${genJS(ref, )} = ${genJS(left, scope)}) != null) ? ${genJS(ref, )}.${genJS(right, scope)} : undefined)`;
            }

            case op === "!=" || op === "==":
                return `${genJS(left, scope)} ${op}= ${genJS(right, scope)}`;

            case op === "??": {
                const ref = Token.Identifier(genVarName(scope, "nullref"));
                return `((${genJS(ref, )} = ${genJS(left, scope)}) != null ? ${genJS(ref, )} : ${genJS(right, scope)})`;
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
        if (body.length > 0 && body[body.length - 1].type !== 'break') {
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
    "for-range": ({item, expr, body}, scope) => {
        const loop = `for (const ${genJS(item)} of ${genJS(expr, scope)})`;
        const bodyLines = body.map(i => genJS(i, scope) + ";").join("\n");
        return `${loop} {\n${bodyLines}\n}`;
    }
};

const compileTree = (sourceTree) => {
    try {
        const {bin, imports, code, scope, globalCalls} = sourceTree;

        const compileScope = scope.copy();
        const binCode = bin === null ? "" : genJS(bin, compileScope) + "\n";
        const importsCode = imports.map(i => genJS(i, compileScope));
        const transpiledCode = [
            ...Array.from(globalFuncCalls).map(name => globalFuncs[name]),
            ...code.map(c => genJS(c, compileScope))
        ];

        const topLevelVars = dif(compileScope.vars, scope.vars);
        const tlvCode = topLevelVars.size > 0
            ? `var ${Array.from(topLevelVars).join(", ")}`
            : "";

        const allCode = [
            binCode,
            ...importsCode,
            tlvCode,
            ...transpiledCode
        ].filter(l => l !== "")
        .concat([""])
        .join(";\n");
        return allCode;
    }
    catch (e) {
        console.error(e);
        print(sourceTree);
    }
};

module.exports = compileTree;
