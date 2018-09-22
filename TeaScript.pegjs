{
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
            toJS() {
                return `const ${name.toJS()} = ${value.toJS()};`;
            }
        }),
        Mut: (name, value) => ({
            type: "create-let",
            name, value,
            toJS() {
                return `let ${name.toJS()} = ${value.toJS()};`;
            }
        }),
        FunctionDecl: (args, body) => ({
            type: "function-decl",
            args, body,
            toJS() {
                // const a = args.map(i => i.toJS());
                return `(${args.map(mtoJS).join(', ')}) => {${body.map(mtoJS).join("\n")}}`;
            }
        }),
        FunctionCall: (name, nullCheck, args) => ({
            type: "function-call",
            name, args, nullCheck,
            toJS() {
                return `${name.toJS()}${nullCheck}(${args.map(mtoJS).join(", ")})`;
            }
        }),
        Return: expr => ({
            type: "return",
            expr,
            toJS() {
                return `return ${expr.toJS()};`;
            }
        }),
        Await: expr => ({
            type: "await",
            expr,
            toJS() {
                return `await ${expr.toJS()};`;
            }
        }),
        Yield: expr => ({
            type: "yield",
            expr,
            toJS() {
                return `yield ${expr.toJS()};`;
            }
        }),
        Array: items => ({
            type: "array",
            items,
            toJS() {
                return `[${items.map(mtoJS).join(", ")}]`;
            }
        }),
        Object: pairs => ({
            type: "object",
            pairs,
            toJS() {
                const p = pairs.map(
                    pair => `${pair.key.toJS()}: ${pair.value.toJS()}`
                );
                return `{${p.join(", ")}}`;
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
            toJS() {
                const alt = alternate === null
                    ? ""
                    : `\nelse {\n${alternate.map(mtoJS).join("\n")}\n}`;
                const ifexpr = `if (${condition.toJS()}) {\n${body.map(mtoJS).join("\n")}\n}${alt}`;

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
            toJS() {
                if (value !== null) {
                    return `return ${value.toJS()};`;
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

                default:
                    return `${left.toJS()} ${op} ${right.toJS()}`;
            }
            // if (op === "**") {
            //     return `Math.pow(${left.toJS()}, ${right.toJS()})`;
            // }
            // return `${left.toJS()} ${op} ${right.toJS()}`;
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

Program
    = _ first:Instruction? rest:(__ Instruction)* _ {
        if (first === null) {
            return [];
        }
        const list = listProcess(first, rest, 1);
        // console.log(list);
        // console.log(
        //     list.map(l => l.toJS()).join("\n")
        // );
        return list;
    }

Instruction
    = VariableCreate
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
    / Switch
    / Return
    / Await
    / Yield
    / Break
    / Logical
    / NullCoalesce

Assignment
    = name:Identifier __ op:("=" / "+=" / "-=" / "*=" / "/=" / "**=") __ value:Expression {
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
    = head:Token tail:( __ "**" __ Token)* {
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
    = "switch" __ expr:NullCoalesce __ "{" _ cases:ValueCases _ "}" {
        return Token.Switch(expr, cases);
    }
ValueCase
    = "case" __ value:Token __ "{" _ _ "}"
ValueCases
    = first:ValueCase? tail:( __ ValueCase)* {
        return listProcess(first, tail);
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
    = text:$([0-9]+) {
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
        // console.log(tail);
        // return Token.Identifier(name);
    }
    / name:$("@" Word) {
        return Token.Identifier(name);
    }
Word = $([a-zA-Z_$] [$a-zA-Z_\-0-9]*)

ArrayLiteral
    = "[" _ first:Expression? rest:(_Separator AddSub?)* _ "]" {
        return Token.Array(listProcess(first, rest, 1));
    }

ObjectLiteral
    = "{" _ first:Pair? rest:(_Separator Pair?)* _ "}" {
        return Token.Object(listProcess(first, rest, 1));
    }
Pair
    = key:Identifier ":" l__ value:Expression {
        return {key, value};
    }
    / key:Identifier "(" args:ArgList ")" __ "=>" __ expr:AddSub {
        return {
            key,
            value: Token.FunctionDecl(
                args,
                [Token.Return(expr)]
            )
        };
    }
    / key:Identifier {
        return {key, value: key};
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
