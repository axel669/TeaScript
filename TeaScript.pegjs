{
    const uniqueGen = source => {
        source = {...source};
        const func = name => {
            if (source[name] !== undefined) {
                const i = source[name] + 1;
                source[name] = i;
                return `${name}${i}`;
            }
            return name;
        };
        func.source = source;
        return func;
    };

    const mtoJS = gen => t => t.toJS(gen);
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
        Identifier: name => ({
            type: "identifier",
            name,
            toJS() {
                return name;
            }
        }),
        Grouped: expr => ({
            expr,
            toJS(nameGen) {
                return `(${expr.toJS(nameGen)})`;
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
            toJS(nameGen) {
                return `const ${name.toJS(nameGen)} = ${value.toJS(nameGen)};`;
            }
        }),
        Mut: (name, value) => ({
            type: "create-let",
            name, value,
            toJS(nameGen) {
                return `let ${name.toJS(nameGen)} = ${value.toJS(nameGen)};`;
            }
        }),
        FunctionDecl: (args, body) => ({
            type: "function-decl",
            args, body,
            toJS(nameGen) {
                // const a = args.map(i => i.toJS());
                return `(${args.map(mtoJS(nameGen)).join(', ')}) => {${body.map(mtoJS(nameGen)).join("\n")}}`;
            }
        }),
        FunctionCall: (name, nullCheck, args) => ({
            type: "function-call",
            name, args, nullCheck,
            toJS(nameGen) {
                return `${name.toJS(nameGen)}${nullCheck}(${args.map(mtoJS(nameGen)).join(", ")})`;
            }
        }),
        NewCall: (name, args) => ({
            type: "new-call",
            name, args,
            toJS(nameGen) {
                return `new ${name.toJS(nameGen)}(${args.map(mtoJS(nameGen)).join(", ")})`;
            }
        }),
        Return: expr => ({
            type: "return",
            expr,
            toJS(nameGen) {
                return `return ${expr.toJS(nameGen)};`;
            }
        }),
        Await: expr => ({
            type: "await",
            expr,
            toJS(nameGen) {
                return `await ${expr.toJS(nameGen)};`;
            }
        }),
        Yield: expr => ({
            type: "yield",
            expr,
            toJS(nameGen) {
                return `yield ${expr.toJS(nameGen)};`;
            }
        }),
        Delete: expr => ({
            type: "delete",
            expr,
            toJS(nameGen) {
                return `delete ${expr.toJS(nameGen)};`;
            }
        }),
        Array: items => ({
            type: "array",
            items,
            toJS(nameGen) {
                return `[${items.map(mtoJS(nameGen)).join(", ")}]`;
            }
        }),
        Object: pairs => ({
            type: "object",
            pairs,
            toJS(nameGen) {
                // const p = pairs.map(
                //     pair => `${pair.key.toJS()}: ${pair.value.toJS()}`
                // );
                const p = pairs.map(mtoJS(nameGen));
                return `{${p.join(", ")}}`;
            }
        }),
        Pair: (key, value) => ({
            type: "pair",
            key, value,
            toJS(nameGen) {
                return `${key.toJS(nameGen)}: ${value.toJS(nameGen)}`;
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
            toJS(nameGen) {
                const alt = alternate === null
                    ? ""
                    : `\nelse {\n${alternate.map(mtoJS(nameGen)).join("\n")}\n}`;
                const ifexpr = `if (${condition.toJS(nameGen)}) {\n${body.map(mtoJS(nameGen)).join("\n")}\n}${alt}`;

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
            toJS(nameGen) {
                if (value !== null) {
                    return `return ${value.toJS(nameGen)};`;
                }
                if (label !== null) {
                    return `break ${label};`;
                }
                return "break;";
            }
        }),
        Switch: (expr, cases) => ({
            type: "switch",
            expr, cases
        }),
        ForObject: (key, value, expr, body) => {
            return {
                type: "for-object",
                key, value, expr, body,
                toJS(nameGen) {
                    const objRef = Token.Identifier(nameGen("ref"));

                    const refLine = Token.Let(objRef, expr);
                    // const refLine = Token.Let(
                    //     objRef,
                    //     Token.FunctionCall(
                    //         Token.Identifier("Object.keys"),
                    //         "",
                    //         [expr]
                    //     )
                    // );

                    const forBody = body;
                    if (value !== null) {
                        forBody.unshift(
                            Token.Let(value, binaryOp(objRef, key, "access"))
                        );
                    }
                    return `${refLine.toJS(nameGen)}\nfor (const ${key.toJS(nameGen)} of Object.keys(${objRef.toJS()})) {${forBody.map(mtoJS(nameGen)).join("\n")}}`;
                }
            };
        },
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
            toJS(nameGen) {
                return `...${expr.toJS(nameGen)}`;
            }
        })
    };
    const binaryOp = (left, right, op) => ({
        type: "bin-op",
        left, right, op,
        toJS() {
            switch (true) {
                case op === "**":
                    return `Math.pow(${left.toJS()}, ${right.toJS()})`;

                case op === "access":
                    return `${left.toJS()}[${right.toJS()}]`;
                case op === "null-access":
                    return `${left.toJS()}?[${right.toJS()}]`;

                case op === "." || op === "?.":
                    return `${left.toJS()}${op}${right.toJS()}`;

                case op === "!=" || op === "==":
                    return `${left.toJS()} ${op}= ${right.toJS()}`;

                default:
                    return `${left.toJS()} ${op} ${right.toJS()}`;
            }
        }
    });
    const unaryOp = (expr, op) => ({
        type: "unary-op",
        expr, op,
        toJS() {
            return `${op}${expr.toJS()}`;
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
}

TopLevel
    = program:Program {
        console.log(program);
        try {
            // scan tree for all vars, never worry again HYPERS
            const gen = uniqueGen({ref: 0, key: 0, value: 0});
            console.log(
                program.map(l => l.toJS(gen)).join("\n")
            );
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
    = Comment
    / VariableCreate
    / Assignment
    / Expression

VariableCreate
    = "let" __ "mut" __ name:Identifier __ "=" __ value:Expression {
        return Token.Mut(name, value);
    }
    / "let" __ "mut" __ name:Identifier {
        return Token.Mut(name, Token.Null());
    }
    / "let" __ name:Identifier __ "=" __ value:Expression {
        return Token.Let(name, value);
    }

Expression
    = If
    / For
    / Switch
    / Return
    / Await
    / Yield
    / Break
    / Logical
    / NullCoalesce

Assignment
    = name:(Access / Identifier) __ op:("=" / "+=" / "-=" / "*=" / "/=" / "**=") __ value:Expression {
        return binaryOp(name, value, op);
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
    = left:NullCoalesce _ op:("==" / "!=" / "<" / ">" / "<=" / ">=") _ right:NullCoalesce {
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
    = head:(Access / Token) tail:( __ "**" __ (Access / Token))* {
        return tailProcess(head, tail);
    }

Access
    = first:(Identifier / FunctionCall / Grouped) tail:("[" _ Expression _ "]")+ {
        return tail.reduce(
            (current, [, , token]) => binaryOp(current, token, "access"),
            first
        );
    }

Grouped
    = "(" _ expr:(Expression) _ ")" {
        return Token.Grouped(expr);
    }

Negated
    = "-" expr:(Identifier / Grouped) {
        return Token.Grouped(unaryOp(expr, "-"));
    }

FunctionDecl
    = "(" _ args:ArgList _ ")" __ "=>" __ expr:Expression {
        return Token.FunctionDecl(
            args,
            [Token.Return(expr)]
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
    = "mut" __ id:Identifier {return Token.MutableIdentifier(id.name);}
    / Identifier

FunctionCall
    = name:Identifier nullCheck:"?"? "(" _ args:CallArgList _ ")" {
        return Token.FunctionCall(name, nullCheck || "", args);
    }
    / name:Identifier construct:"*"? "(" _ args:CallArgList _ ")" {
        return Token.NewCall(name, args);
    }
CallArgList
    = first:Expression? rest:(_Separator Expression)* {
        return listProcess(first, rest, 1);
    }

Return
    = "return" __ expr:Expression {return Token.Return(expr);}
Await
    = "await" __ expr:Expression {return Token.Await(expr);}
Yield
    = "yield" __ expr:Expression {return Token.Yield(expr);}

Delete
    = "delete" __ expr:Expression {return Token.Delete(expr);}

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
    = "switch" __ expr:NullCoalesce __ "{" _ cases:ValueCases def:DefaultCase? _ "}" {
        return Token.Switch(expr, cases);
    }
DefaultCase
    = "default" __ "{" _ body:Program _ "}"
ValueCase
    = "case" __ value:Token __ "{" _ body:Program _ "}"
ValueCases
    = first:ValueCase? tail:( __ ValueCase)* {
        return listProcess(first, tail);
    }

For
    = "for" __ "{" _ key:Identifier value:(_ "," _ Identifier)? _ "}" __ "in" __ expr:Expression __ "{" body:Program "}" {
        return Token.ForObject(
            key,
            (value === null) ? null : value[3],
            expr,
            body
        );
    }

Token
    = Number
    / String
    / FunctionDecl
    / Grouped
    / ArrayLiteral
    / ObjectLiteral
    / FunctionCall
    / Identifier
    / Negated

Number
    = text:$("-"? [0-9]+) {
        return Token.Number(parseInt(text, 10));
    }

String
    = text:$('"' ([^"\\] / "\\\"" / "\\u" . . . .)* '"') {
        return Token.String(text);
    }

Identifier
    = name:Word tail:( _ ("." / "?.") _ (Word / String) )* {
        let current = Token.Identifier(name);
        for (const [, op, , token] of tail) {
            if (token.type === "string") {
                current = binaryOp(current, token, op === "." ? "access" : "null-access");
            }
            else {
                current = binaryOp(current, Token.Identifier(token), op);
            }
        }
        return current;
    }
    / name:$("@" Word) {
        return Token.Identifier(name);
    }
Word = $([a-zA-Z_$] [$a-zA-Z_\-0-9]*)

ArrayLiteral
    = "[" _ first:ArrayEntry? rest:(_Separator ArrayEntry?)* _ "]" {
        return Token.Array(listProcess(first, rest, 1));
    }
ArrayEntry = Expression / Expansion

ObjectLiteral
    = "{" _ first:ObjectEntry? rest:(_Separator ObjectEntry?)* _ "}" {
        return Token.Object(listProcess(first, rest, 1));
    }
ObjectEntry = Pair / Expansion
Pair
    = key:Identifier ":" l__ value:Expression {
        return Token.Pair(key, value);
    }
    / key:Identifier "(" _ args:ArgList _ ")" __ "=>" __ expr:AddSub {
        return Token.Pair(
            key,
            Token.FunctionDecl(
                args,
                [Token.Return(expr)]
            )
        );
    }
    / key:Identifier "(" _ args:ArgList _ ")" __ "=>" __ "{" body:Program "}" {
        return Token.Pair(
            key,
            Token.FunctionDecl(args, body)
        );
    }
    / key:Identifier {
        return Token.Pair(key, key);
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
