{
    const Scope = (baseScope = null) => {
        const vars = new Set(baseScope ? baseScope.vars : []);
        const flags = {async: false, generator: false};
        const self = {vars, flags};
        self.copy = () => Scope(self);
        return self;
    };
    const topLevelScope = Scope();
    const globalFuncCalls = new Set();

    const tokenType = (type, ...names) =>
        (...args) => names.reduce(
            (token, name, index) => {
                if (typeof name === "function") {
                    return name(token);
                }
                const [varName, defaultValue] = Array.isArray(name) === true
                    ? name
                    : [name, undefined];
                const value = args[index];
                return {
                    ...token,
                    [varName]: value === undefined ? defaultValue : value
                };
            },
            {type}
        );
    const tokenIsRBreak = token => token.type === "break" && token.value !== null;
    const hasRBreak = tokens => tokens !== null && tokens.findIndex(tokenIsRBreak) !== -1;
    const Token = {
        Number: tokenType("number", "location", "value"),
        String: tokenType("string", "location", "text"),
        Regex: tokenType("regex", "regex"),
        Bool: tokenType("bool", "value"),
        Null: tokenType("null"),
        Undefined: tokenType("undefined"),
        Identifier: tokenType("identifier", "name"),
        MutableIdentifier: tokenType("mutable-identifier", "name"),
        Grouped: tokenType("group", "expr"),
        Let: tokenType("create-const", "name", "value"),
        Mut: tokenType("create-let", "name", "value"),
        MutList: tokenType("create-let-list", "names"),
        FunctionDecl: tokenType("function-decl", "args", "body", ["bindable", false]),
        FunctionCall: tokenType("function-call", "name", "nullCheck", "args"),
        NewCall: tokenType("new-call", "name", "args"),
        Unary: tokenType("unary", "op", "expr", ["standAlone", true]),
        Array: tokenType("array", "items"),
        Object: tokenType("object", "pairs"),
        Pair: tokenType("pair", "accessMod", "decorators", "key", "value", ["sep", ":"]),
        If: tokenType(
            "if", "condition", "body", "alternate",
            (tok) => ({
                ...tok,
                isReturn: hasRBreak(tok.body) || hasRBreak(tok.alternate)
            })
        ),
        Break: tokenType("break", ["value", null], ["label", null]),
        Switch: tokenType("switch", "expr", "cases", "def"),
        ValueCase: tokenType("value-case", "value", "body"),
        CompareCase: tokenType("compare-case", "expr", "body"),
        DefaultCase: tokenType("default-case", "body"),
        ForObject: tokenType("for-object", "key", "value", "expr", "body"),
        ForIn: tokenType("for-range", "item", "mod", "expr", "body"),
        While: tokenType("while", "condition", "body"),
        Comment: tokenType("comment", "text"),
        Expansion: tokenType("expansion", "expr"),
        Range: tokenType("range", "start", "end", "inc"),
        Import: tokenType("import", "structure", "source"),
        Export: tokenType("export", "source", ["isDefault", false]),
        Block: tokenType("block", "body"),
        Not: tokenType("not", "expr"),
        Assignment: tokenType("assignment", "name", "value", "op"),
        Decorator: tokenType("decorator", "func"),
        SimpleDecorator: tokenType("simple-decorator", "func"),
        Class: tokenType("class", "decorators", "name", "extend", "body"),
        ClassStaticVar: tokenType("class-static-var", "name", "value"),
        ClassFunction: tokenType("class-func", "name", "decorators", "args", "body"),
        Construct: tokenType("construct", "decorators", "name", "body"),
        ConstructFunction: tokenType("construct-function", "accessMod", "name", "decorators", "args", "body"),
        ConstructVar: tokenType("construct-var", "name", "value"),
        JSXProp: tokenType("jsx-prop", "key", "value"),
        JSXSelfClosing: tokenType("jsx-self-closing", "tag", "props"),
        JSXTagOpen: tokenType("jsx-tag-open", "tag", "props"),
        JSXTagClose: tokenType("jsx-tag-close", "tag"),
        JSXTag: tokenType("jsx-tag", "open", "children", "close"),
        JSXContent: tokenType("jsx-content", "content"),
        JSXExpression: tokenType("jsx-expression", "expr"),
        Ternary: tokenType("ternary", "condition", "truish", "falsish"),
        Try: tokenType("try-catch", "attempt", "cancel", "error", "final"),
        BinMagic: tokenType("bin-magic", "comment")
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
                    return `(((${ref.toJS()} = ${left.toJS(scope)}) != null) ? ${ref.toJS()}.${right.toJS(scope)} : undefined)`;
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
                    current = Token.FunctionCall(current, item.nullCheck, item.args);
                }
            }
            else {
                current = binaryOp(current, item.name, item.op);
            }
        }
        return current;
    };

    const checkForCall = (token) => {
        if (token.type === "function-call") {
            return true;
        }
        if (token.items !== undefined) {
            for (const item of token.items) {
                if (checkForCall(item) === true) {
                    return true;
                }
            }
        }
        return false;
    };

    const tokenRegex = /^[a-zA-Z_$][a-zA-Z_$0-9]*$/;
}

TopLevel
    = bin:(BinMagic n__ / _) imports:(_ Import __)* _ program:TopLevelProgram _ {
        return {
            bin: bin.length === 2 ? bin[0] : null,
            imports: imports.map(i => i[1]),
            code: program,
            scope: topLevelScope,
            globalCalls: globalFuncCalls
        };
    }
TopLevelProgram
    = _ first:(Export / Instruction)? rest:(__ (Export / Instruction))* _ {
        if (first === null) {
            return [];
        }
        const list = listProcess(first, rest, 1);
        return list;
    }

BinMagic
    = comment:$("#!" ("/" [a-zA-Z0-9_]+)*) {
        return Token.BinMagic(comment);
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
    / "import" __ name:ImportDefault parts:(_ "," _ (ImportStructure / ImportStar)) __ "from" __ source:String {
        // const form = parts === null
        // ? name
        // : `${name}, ${parts[3]}`;
        const form = `${name}, ${parts[3]}`;
        return Token.Import(form, source);
    }
    / "import" __ structure:ImportStructure __ "from" __ source:String {
        return Token.Import(structure, source);
    }
    / "import" __ star:ImportStar __ "from" __ source:String {
        return Token.Import(star, source);
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
        return Token.Mut(name, value);
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
        }
        for (const tok of tokens) {
            if (tokenRegex.test(tok.name) === true) {
                topLevelScope.vars.add(tok.name);
            }
        }
        return Token.Array(tokens);
    }
    / "{" first:(DestructureAs / DestructureNested / DestructureDefault / Identifier) tail:(_ "," _ (DestructureAs / DestructureNested / DestructureDefault / Identifier))* rest:(_ "," _ "..." Word)? "}" {
        const tokens = [
            first,
            ...tail.map(i => i[3])
        ];
        if (rest !== null) {
            topLevelScope.vars.add(rest[4]);
            tokens.push(Token.Identifier(`...${rest[4]}`));
        }
        for (const tok of tokens) {
            if (tokenRegex.test(tok.name) === true) {
                topLevelScope.vars.add(tok.name);
            }
        }
        return Token.Object(tokens);
    }
DestructureAs
    = name:Word __ "as" __ newName:Word {
        topLevelScope.vars.add(newName);
        return Token.Pair("", [], Token.Identifier(name), Token.Identifier(newName));
    }
DestructureNested
    = key:Word ":" __ value:Destructure {
        return Token.Pair("", [], Token.Identifier(key), value);
    }
DestructureDefault
    = name:IdentifierToken __ "=" __ value:(Number / String / IdentifierToken) {
        return Token.Pair("", [], name, value, "=");
    }

DestructureLValue
    = "[" first:(DestructureDefault / IdentifierTokenLValue / "*" / Destructure)
            tail:(_ "," _ (DestructureDefault / IdentifierTokenLValue / "*" / Destructure))*
            rest:(_ "," _ "..." IdentifierTokenLValue)? "]" {
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
        }
        return Token.Array(tokens);
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
    / Construct
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
    = name:(IdentifierTokenLValue / DestructureLValue) __ op:("=" / "+=" / "-=" / "*=" / "/=" / "**=") __ value:(Ternary / Expression) {
        if (checkForCall(name) === true) {
            throw new Error("cannot assign to function call");
        }
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
    = left:(NullCoalesce) tail:(__ ("==" / "!=" / "<" / ">" / "<=" / ">=" / "instanceof") __ NullCoalesce)+ {
        // console.log(tail);
        if (tail.length === 1) {
            const [, op, , right] = tail[0];
            return binaryOp(left, right, op);
        }
        return null;
    }
    / "(" _ logical:Logical _ ")" {
        return Token.Grouped(logical);
    }

Ternary
    = condition:Logical __ "?" __ truish:Expression __ ":"__ falsish:Expression {
        return Token.Ternary(condition, truish, falsish);
    }
NullCoalesce
    = head:Bitwise tail:(__ "??" __ Bitwise)* {
        return tailProcess(head, tail);
    }
Bitwise
    = head:AddSub tail:(__ ("|" / "&" / "^" / "<<<" / ">>>" / "<<" / ">>") __ AddSub)* {
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
            [Token.Unary("return", expr)]
        );
    }
    / "(" _ args:ArgList _ ")" __ "=>*" __ expr:(Ternary / Expression) {
        return Token.FunctionDecl(
            args,
            [Token.Unary("return", expr)],
            true
        );
    }
    / "(" _ args:ArgList _ ")" __ "=>" __ "{" body:Program "}" {
        return Token.FunctionDecl(args, body);
    }
    / "(" _ args:ArgList _ ")" __ "=>*" __ "{" body:Program "}" {
        return Token.FunctionDecl(args, body, true);
    }
ArgList
    = first:Arg? rest:(_ "," _ Arg)* {
        return listProcess(first, rest, 3);
    }
Arg
    = name:(Identifier / Destructure) __ "=" __ expr:Expression {
        return binaryOp(name, expr, "=");
    }
    / "mut" __ id:Identifier {return Token.MutableIdentifier(id.name);}
    / Identifier
    / Destructure
    / "..." id:Word {
        return Token.Expansion(
            Token.Identifier(id)
        );
        // const name = Token.Identifier(id);
        // return {
        //     type: "cheat",
        //     name,
        //     toJS(scope) {
        //         return `...${id}`;
        //     }
        // };
    }

CallArgList
    = first:CallArg? rest:(_Separator CallArg)* {
        return listProcess(first, rest, 1);
    }
CallArg
    = Expression
    / "..." expr:Expression {
        return Token.Expansion(expr);
        // return {
        //     type: "cheat",
        //     expr,
        //     toJS(scope) {
        //         return `...${expr.toJS(scope)}`;
        //     }
        // };
    }
CallBit
    = nullCheck:"?"? "(" _ args:CallArgList _ ")" {
        return {nullCheck: nullCheck || "", args};
    }
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
    / _ "::" value:Word {
        return {op: ".", name: Token.Identifier(`prototype.${value}`)};
    }

Typeof
    = "typeof" __ expr:(NullCoalesce / Logical) {return Token.Unary("typeof", expr, false);}

Return
    = "return" __ expr:(Ternary / Expression) {return Token.Unary("return", expr);}
    / "return" {return Token.Unary("return");}
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
    / mod:("wait" __)? "for" __ key:Word __ "in" __ range:Range __ "{" _ body:Program _ "}" {
        return Token.ForIn(Token.Identifier(key), mod !== null, range, body);
    }
    / mod:("wait" __)? "for" __ key:ForInVars __ "in" __ expr:Expression __ "{" _ body:Program _ "}" {
        return Token.ForIn(key, mod !== null, expr, body);
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

Construct
    = decorators:(_ Decorator _)* "construct" __ name:Word __ "{" _ body:ConstructBody _ "}" {
        return Token.Construct(
            decorators.map(d => d[1]),
            name,
            body
        );
    }
ConstructBody
    = entries:(_ (ConstructVar / ConstructFunction) _)* {
        return entries.map(e => e[1]);
    }
ConstructVar
    = "static" __ name:Word __ "=" __ value:Expression {
        return Token.ConstructVar(name, value);
    }
ConstructFunction
    = decorators:(_ Decorator _)* accessMod:(("get" / "set") __)? name:Word func:FunctionDecl {
        return Token.ConstructFunction(
            accessMod ? accessMod[0] : "",
            name,
            decorators.map(d => d[1]),
            func.args,
            func.body
        );
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
    }
IdentifierToken
    = first:Identifier tail:(AccessBit / ArrayAccess)* {
        return processTail(first, tail);
    }
IdentifierTokenLValue
    = first:Identifier tail:(CallBit / AccessBit / ArrayAccess)* {
        const last = tail.slice(-1)[0];
        return processTail(first, tail);
    }
    / Identifier

Number
    = text:$("-"? [0-9]+ ("." [0-9]+)? ("e" ("+" / "-")? [0-9]+)?) {
        return Token.Number(location(), parseFloat(text));
    }
    / text:$("-"? [0-9]+) {
        return Token.Number(location(), parseInt(text, 10));
    }
    / text:$("0x" Hex+) {
        return Token.Number(location(), parseInt(text, 16));
    }
    / text:$("0b" [01]+) {
        return Token.Number(location(), parseInt(text, 2));
    }
    / text:$("0o" [0-7]+) {
        return Token.Number(location(), parseInt(text, 8));
    }
Hex = [0-9a-f]i

String
    = text:('"' ("\\$" / ("${" Expression "}") / [^"\\] / "\\\"" / "\\u" . . . . / "\\\\")* '"') {
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
        return Token.String(location(), bits);
    }

Regex
    = text:$("/" ("\\/" / [^\/])+ "/" ("g" / "m" / "i")*) {
        return Token.Regex(text);
    }

Bool = value:("true" / "false") {return Token.Bool(value === "true");}
Undefined = ("undefined" / "void") {return Token.Undefined();}
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
    / _this:"#"? name:Word {
        let current = Token.Identifier(name);

        if (_this !== null) {
            current = binaryOp(Token.Identifier("self"), current, ".");
        }
        return current;
    }
    / "#" {return Token.Identifier("self");}
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
    = "[" _ first:ArrayEntry? rest:(_Separator ArrayEntry?)* _ "]" {
        let current = Token.Array(listProcess(first, rest, 1));
        return current;
    }
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
        return Token.Range(start, end, inc ? inc[3] : Token.Number(null, 1));
    }
SliceRange
    = start:NullCoalesce "..." end:NullCoalesce {
        return {start, end};
    }
    / start:NullCoalesce "..." {
        return {start, end: Token.Undefined()};
    }
    / "..." end:NullCoalesce {
        return {start: Token.Number(null, 0), end};
    }

ObjectLiteral
    = "{" _ first:ObjectEntry? rest:(_Separator ObjectEntry?)* _ "}" {
        return Token.Object(listProcess(first, rest, 1));
    }
ObjectEntry = Pair / Expansion
Pair
    = decorators:(_ (SimpleDecorator / Decorator) _)* key:(Identifier / String / CalculatedKey) ":" l__ value:(Ternary / Expression) {
        const k = (key.type === "string" && key.text.length > 1) ? Token.Array([key]) : key;
        return Token.Pair("", decorators.map(d => d[1]), k, value);
    }
    / decorators:(_ (SimpleDecorator / Decorator) _)* accessMod:(("get" / "set") __)? key:(Identifier / String / CalculatedKey) func:FunctionDecl {
        const k = (key.type === "string" && key.text.length > 1) ? Token.Array([key]) : key;
        return Token.Pair(accessMod ? accessMod[0] : "", decorators.map(d => d[1]), k, func);
    }
    / decorators:(_ (SimpleDecorator / Decorator) _)* key:(IdentifierToken / Identifier) {
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
SimpleDecorator
    = "@@" call:Token {
        return Token.SimpleDecorator(call);
    }

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
n__ "Newline"
    = [\r\n]+
w__ "Whitespace Separator"
    = [ \t]* [\r\n]+ _
l__ "Optional Whitespace"
    = [ \t*]
_Separator
    = w__
    / _ "," _
