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

    const dif = (a, b) => new Set(Array.from(a).filter(i => b.has(i) === false));

    const usedVars = new Set();
    const genVarName = (scope, name) => {
        for (let i = 0; i < 1e6; i += 1) {
            const test = `${name}${i}`;
            if (scope.has(test) === false) {
                scope.add(test);
                return test;
            }
        }
    };

    const mtoJS = t => t.toJS();
    const Token = {
        Number: value => ({
            type: "number",
            value,
            toJS() {
                return value.toString();
            }
        }),
        String: text => ({
            type: "string",
            text,
            toJS() {
                return text;
            }
        }),
        Bool: (value) => ({
            type: "bool",
            value,
            toJS() {
                return value.toString();
            }
        }),
        Null: () => ({type: "null", toJS() {return "null";}}),
        Undefined: () => ({type: "undefined", toJS() {return "undefined";}}),
        Identifier: name => ({
            type: "identifier",
            name,
            toJS() {
                return name;
            }
        }),
        Grouped: expr => ({
            expr,
            toJS() {
                return `(${expr.toJS()})`;
            }
        }),
        MutableIdentifier: name => ({
            type: "mutable-identifier",
            name,
            toJS() {
                return name;
            }
        }),
        Let: (name, value) => ({
            type: "create-const",
            name, value,
            toJS(scope) {
                // return `const ${name.toJS()} = ${value.toJS(scope)};`;
                return `const ${name.toJS()} = ${value.toJS(scope)}`;
            }
        }),
        Mut: (name, value) => ({
            type: "create-let",
            name, value,
            toJS(scope) {
                // return `let ${name.toJS()} = ${value.toJS(scope)};`;
                return `let ${name.toJS()} = ${value.toJS(scope)}`;
            }
        }),
        MutList: (names) => ({
            type: "create-let-list",
            names,
            toJS() {
                const list = names.map(name => `${name} = undefined`)
                // return `let ${list.join(", ")};`;
                return `let ${list.join(", ")}`;
            }
        }),
        FunctionDecl: (args, body) => ({
            type: "function-decl",
            args, body,
            toJS(parentScope) {
                // const a = args.map(i => i.toJS());
                const scope = new Set(parentScope);
                const argDef = `(${args.map(i => i.toJS()).join(', ')}) => `;
                // const bodyLines = body.map(i => i.toJS(scope)).join("\n");
                const bodyLines = body.map(i => i.toJS(scope)).join(";\n");

                // console.log("SCOPE", scope, parentScope);
                const vars = dif(scope, parentScope);
                const code = vars.size !== 0
                    ? `var ${Array.from(vars).join(", ")};\n${bodyLines}`
                    : bodyLines;

                return `${argDef}{${code};}`;
            }
        }),
        FunctionCall: (name, nullCheck, args) => ({
            type: "function-call",
            name, args, nullCheck,
            toJS(scope) {
                return `${name.toJS()}${nullCheck}(${args.map(i => i.toJS(scope)).join(", ")})`;
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
            toJS(nameGen) {
                // return `${type} ${expr.toJS()}${standAlone === true ? ";" : ""}`;
                return `${type} ${expr.toJS()}`;
            }
        }),
        Array: items => ({
            type: "array",
            items,
            toJS(nameGen) {
                return `[${items.map(mtoJS).join(", ")}]`;
            }
        }),
        Object: pairs => ({
            type: "object",
            pairs,
            toJS(scope) {
                const p = pairs.map(i => i.toJS(scope));
                return `{${p.join(", ")}}`;
            }
        }),
        Pair: (key, value) => ({
            type: "pair",
            key, value,
            toJS(scope) {
                return `${key.toJS(scope)}: ${value.toJS(scope)}`;
            }
        }),
        Null: () => ({
            type: "null",
            toJS() {
                return "null";
            }
        }),
        If: (condition, body, alternate) => ({
            type: "if",
            condition, body, alternate,
            toJS(scope) {
                const alt = alternate === null
                    ? ""
                    // : `\nelse {\n${alternate.map(i => i.toJS(scope)).join("\n")}\n}`;
                    : `\nelse {\n${alternate.map(i => i.toJS(scope)).join(";\n")};\n}`;
                // const ifexpr = `if (${condition.toJS()}) {\n${body.map(i => i.toJS(scope)).join("\n")}\n}${alt}`;
                const ifexpr = `if (${condition.toJS()}) {\n${body.map(i => i.toJS(scope)).join(";\n")};\n}${alt}`;

                const breakValue = token => token.type === "break" && token.value !== null;
                if (body.findIndex(breakValue) !== -1 || (alternate !== null && alternate.findIndex(breakValue) !== -1)) {
                    return `(() => {${ifexpr}})()`;
                }
                return ifexpr;
            }
        }),
        Break: (value = null, label = null) => ({
            type: "break",
            value, label,
            toJS(scope) {
                if (value !== null) {
                    // return `return ${value.toJS(scope)};`;
                    return `return ${value.toJS(scope)}`;
                }
                if (label !== null) {
                    // return `break ${label};`;
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
                return `switch (${expr.toJS()}) {\n${body}\n${defCase}}`;
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
                // const bodyLines = bodyCopy.map(i => i.toJS(scope)).join("\n");
                const bodyLines = bodyCopy.map(i => i.toJS(scope)).join(";\n");
                // return `case ${value.toJS(scope)}: {\n${bodyLines}\n}`;
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
                const bodyLines = bodyCopy.map(i => i.toJS(scope)).join("\n");
                return `case (${expr.toJS()}): {\n${bodyLines}\n}`;
            }
        }),
        DefaultCase: (body) => ({
            type: "default-case",
            body,
            toJS(scope) {
                // const bodyLines = body.map(i => toJS(scope)).join("\n");
                // return `default: {\n${bodyLines}\n}`;
                const bodyLines = body.map(i => toJS(scope)).join(";\n");
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

                // const bodyLines = forBody.map(i => i.toJS(scope)).join("\n");
                const bodyLines = forBody.map(i => i.toJS(scope)).join(";\n");

                // return `${loop} {\n${bodyLines}\n}`;
                return `${loop} {\n${bodyLines};\n}`;
            }
        }),
        ForIn: (item, expr, body) => ({
            type: "for-range",
            item, expr, body,
            toJS(scope) {
                const loop = `for (const ${item.toJS()} of ${expr.toJS(scope)})`;
                // const bodyLines = body.map(i => i.toJS(scope)).join("\n");
                // return `${loop} {\n${bodyLines}\n}`;
                const bodyLines = body.map(i => i.toJS(scope)).join(";\n");
                return `${loop} {\n${bodyLines};\n}`;
            }
        }),
        While: (condition, body) => ({
            type: "while",
            condition, body,
            toJS(scope) {
                // return `while (${condition.toJS(scope)}) {\n${body.map(i => i.toJS(scope)).join("\n")}\n}`;
                return `while (${condition.toJS(scope)}) {\n${body.map(i => i.toJS(scope)).join(";\n")};\n}`;
            }
        }),
        Comment: (text) => ({
            type: "comment",
            text,
            toJS() {
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
            toJS() {
                if (structure === null) {
                    // return `import ${source.toJS()};`;
                    return `import ${source.toJS()}`;
                }
                // return `import ${structure} from ${source.toJS()};`;
                return `import ${structure} from ${source.toJS()}`;
            }
        }),
        Block: (body) => ({
            type: "block",
            body,
            toJS(scope) {
                // return `{\n${body.map(i => i.toJS(scope)).join("\n")}\n}`;
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
                return `(${name.toJS()} ${op} ${value.toJS(scope)})`;
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
                    // return `${left.toJS(scope)}?[${right.toJS(scope)}]`;
                    return `((${ref.toJS()} = ${left.toJS(scope)}) != null) ? ${ref.toJS()}[${right.toJS(scope)}] : undefined)`;
                }

                case op === ".":
                    return `${left.toJS(scope)}${op}${right.toJS(scope)}`;
                case op === "?.": {
                    const ref = Token.Identifier(genVarName(scope, "nullref"));
                    // return `${left.toJS(scope)}${op}${right.toJS(scope)}`;
                    return `((${ref.toJS()} = ${left.toJS(scope)}) != null ? ${ref.toJS()}.${right.toJS(scope)} : undefined)`;
                }

                case op === "!=" || op === "==":
                    return `${left.toJS(scope)} ${op}= ${right.toJS(scope)}`;

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

    const tokenRegex = /^[a-zA-Z_$][a-zA-Z_$0-9]*$/;
}

TopLevel
    = imports:(_ Import __)* _ program:Program {
        console.log(imports, program);
        try {
            console.log(usedVars);
            const newScope = new Set(usedVars);
            // const gen = uniqueGen({ref: 0, key: 0, value: 0});
            const transpiled = [
                ...Array.from(globalFuncCalls).map(name => globalFuncs[name]),
                ...program.map(l => l.toJS(newScope))
            ].join(";\n");

            const vars = dif(newScope, usedVars);
            const code = vars.size !== 0
                ? `var ${Array.from(vars).join(", ")};\n${transpiled}`
                : transpiled;
            const $code = [
                ...imports.map(i => i[1].toJS()),
                code
            ].join(";\n");
            // console.log(newScope);
            console.log($code);
            window.$code = $code;
        }
        catch (e) {
            console.error(e);
        }
        return program;
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
ImportName = name:Word {usedVars.add(name); return name;}
ImportAs = source:Word __ "as" __ name:Word {usedVars.add(name); return text();}
ImportStructure
    = "{" _ first:(ImportAs / ImportName) tail:(_ "," _ (ImportAs / ImportName))* "}" {
        const list = [first, ...tail.map(i => i[3])].join(", ");
        return `{${list}}`;
    }
ImportStar = "*" __ "as" __ name:Word {usedVars.add(name); return text();}
ImportDefault = name:Word {usedVars.add(name); return text();}

VariableCreate
    = "let" __ "mut" __ name:Word __ "=" __ value:Expression {
        usedVars.add(name);
        return Token.Mut(Token.Identifier(name), value);
    }
    / "let" __ "mut" __ name:Word tail:(_ "," _ "mut" __ Word)* {
        const list = [
            name,
            ...tail.map(i => i[5])
        ];
        for (const varName of list) {
            usedVars.add(varName);
        }
        return Token.MutList(list);
    }
    / "let" __ name:Word __ "=" __ value:Expression {
        usedVars.add(name);
        return Token.Let(Token.Identifier(name), value);
    }
    / "let" __ "mut" __ name:Destructure __ "=" __ value:Expression {
        return Token.Mut(Token.Identifier(name), value);
    }
    / "let" __ name:Destructure __ "=" __ value:Expression {
        return Token.Let(Token.Identifier(name), value);
    }

Destructure
    = "[" first:(Word / "*" / Destructure) tail:(_ "," _ (Word / "*" / Destructure))* rest:(_ "," _ "..." Word)? "]" {
        const tokens = [
            first,
            ...tail.map(i => i[3])
        ];
        if (rest !== null) {
            usedVars.add(rest[4]);
            tokens.push(`...${rest[4]}`);
        }
        for (const tok of tokens) {
            if (tokenRegex.test(tok) === true) {
                usedVars.add(tok);
            }
        }
        return `[${tokens.map(i => i === "*" ? "" : i).join(", ")}]`;
    }
    / "{" first:(DestructureAs / DestructureNested / Word) tail:(_ "," _ (DestructureAs / DestructureNested / Word))* rest:(_ "," _ "..." Word)? "}" {
        const tokens = [
            first,
            ...tail.map(i => i[3])
        ];
        if (rest !== null) {
            usedVars.add(rest[4]);
            tokens.push(`...${rest[4]}`);
        }
        for (const tok of tokens) {
            if (tokenRegex.test(tok) === true) {
                usedVars.add(tok);
            }
        }
        return `{${tokens.map(i => i === "*" ? "" : i).join(", ")}}`;
    }
DestructureAs
    = name:Word __ "as" __ newName:Word {
        usedVars.add(newName);
        return `${name}: ${newName}`;
    }
DestructureNested
    = key:Word ":" __ value:Destructure {
        return `${key}: ${value}`;
    }

Expression
    = If
    / For
    / While
    / Switch
    / Return
    / Await
    / Yield
    / Break
    / Logical
    / NullCoalesce

Assignment
    = name:(Identifier / Destructure {return Token.Identifier(text());}) __ op:("=" / "+=" / "-=" / "*=" / "/=" / "**=") __ value:Expression {
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
    = "(" _ args:ArgList _ ")" __ "=>" __ expr:Expression {
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
    = name:Identifier __ "=" __ expr:Expression {
        return binaryOp(name, expr, "=");
    }
    / "mut" __ id:Identifier {return Token.MutableIdentifier(id.name);}
    / Identifier

FunctionCall
    = name:(Grouped / Identifier) end:CallBit tail:(CallBit / AccessBit)* {
        let current = Token.FunctionCall(name, end.nullCheck, end.args);

        for (const item of tail) {
            if (item.args !== undefined) {
                current = Token.FunctionCall(current, item.nullCheck, item.args);
            }
            else {
                current = binaryOp(current, item.name, item.op);
            }
        }

        return current;
    }
CallArgList
    = first:Expression? rest:(_Separator Expression)* {
        return listProcess(first, rest, 1);
    }
CallBit
    = nullCheck:"?"? "(" _ args:CallArgList _ ")" {
        return {nullCheck: nullCheck || "", args};
    }
AccessBit
    = _ op:$("?"? ".") _ name:Identifier {
        return {name, op};
    }

Typeof
    = "typeof" __ expr:(NullCoalesce / Logical) {return Token.Unary("typeof", expr, false);}

Return
    = "return" __ expr:Expression {return Token.Unary("return", expr);}
Await
    = "await" __ expr:Expression {return Token.Unary("await", expr, false);}
Yield
    = "yield" __ expr:Expression {return Token.Unary("yield", expr, false);}

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
    = "switch" __ expr:Logical __ "{" _ cases:ValueCases _ def:DefaultCase? _ "}" {
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

Token
    = Number
    / Typeof
    / String
    / Bool
    / Null
    / Undefined
    / FunctionDecl
    / FunctionCall
    / Grouped
    / ArrayLiteral
    / ObjectLiteral
    / Identifier
    / Negated
    / Not

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
    = text:$('"' ([^"\\] / "\\\"" / "\\u" . . . .)* '"') {
        return Token.String(text);
    }

Bool = value:("true" / "false") {return Token.Bool(value === "true");}
Undefined = "undefined" {return Token.Undefined();}
Null = "null" {return Token.Null();}

Identifier
    = _this:"@"? name:Word tail:(DotAccess / ArrayAccess)* {
        let current = Token.Identifier(name);

        if (_this !== null) {
            current = binaryOp(Token.Identifier("this"), current, ".");
        }
        for (const {op, value} of tail) {
            current = binaryOp(current, value, op);
        }
        return current;
    }
    /* / name:$("@" Word) {
        return Token.Identifier(name);
    } */
Word = $([a-zA-Z_$] [$a-zA-Z_\-0-9]*)
DotAccess
    = _ op:$("?"? ".") _ value:(Word / String) {
        if (value.type !== "string") {
            return {op, value: Token.Identifier(value)};
        }
        else {
            return {op: op === "." ? "access" : "null-access", value: Token.String(value)};
        }
    }
ArrayAccess
    = nullish:"?"? "[" value:Expression "]" {
        return {op: nullish === null ? "access" : "null-access", value};
    }

DotCall
    = _ op:$("?"? ".") _ name:Identifier call:CallBit {
        return {op, value: Token.FunctionCall(name, call.nullCheck, call.args)};
    }
ArrayLiteral
    = "[" _ first:ArrayEntry? rest:(_Separator ArrayEntry?)* _ "]" tail:(DotCall / DotAccess / ArrayAccess)* {
        let current = Token.Array(listProcess(first, rest, 1));
        for (const {op, value} of tail) {
            current = binaryOp(current, value, op);
        }
        return current;
    }
    / "[" range:Range map:(":" __ FunctionDecl)? _ "]" tail:(DotCall / DotAccess / ArrayAccess)* {
        const tok = Token.FunctionCall(Token.Identifier("range"), "", [range.start, range.end, range.inc]);
        let current = tok;

        if (map !== null) {
            current = Token.FunctionCall(
                binaryOp(tok, Token.Identifier("map"), "."),
                "",
                [map[2]]
            );
        }
        for (const {op, value} of tail) {
            current = binaryOp(current, value, op);
        }

        return current;
    }
ArrayEntry = Expression / Expansion

Range
    = start:NullCoalesce "..." end:NullCoalesce inc:(__ "by" __ NullCoalesce)? {
        globalFuncCalls.add("range");
        return Token.Range(start, end, inc ? inc[3] : Token.Number(1));
    }

ObjectLiteral
    = "{" _ first:ObjectEntry? rest:(_Separator ObjectEntry?)* _ "}" {
        return Token.Object(listProcess(first, rest, 1));
    }
ObjectEntry = Pair / Expansion
Pair
    = key:(Identifier / CalculatedKey) ":" l__ value:Expression {
        return Token.Pair(key, value);
    }
    / key:(Identifier / CalculatedKey) "(" _ args:ArgList _ ")" __ "=>" __ expr:AddSub {
        return Token.Pair(
            key,
            Token.FunctionDecl(
                args,
                [Token.Unary("return", expr)]
            )
        );
    }
    / key:(Identifier / CalculatedKey) "(" _ args:ArgList _ ")" __ "=>" __ "{" body:Program "}" {
        return Token.Pair(
            key,
            Token.FunctionDecl(args, body)
        );
    }
    / key:Identifier {
        return Token.Pair(key, key);
    }
CalculatedKey
    = "[" expr:Expression "]" {
        return Token.Array([expr]);
    }
Expansion
    = "..." expr:Expression {
        return Token.Expansion(expr);
    }

Comment
    = "//" text:$([^\n]*) {
        return Token.Comment(text);
    }
    / "/*" text:$((__ / "*" [^\/] / [^\*] . / [^\*])*) "*/" {
        return Token.Comment(text);
    }

__ "Whitespace"
    = [ \t\r\n]+
_ "Optional Whitespace"
    = [ \t\n\r]*
w__ "Whitespace Separator"
    = [ \t]* [\r\n]+ _
l__ "Optional Whitespace"
    = [ \t*]
_Separator
    = w__
    / _ "," _
