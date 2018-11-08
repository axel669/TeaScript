#!/usr/bin/env node

const path = require("path");
const fs = require("fs");

const argParser = require("./arg-parser.js");
const transpile = require("./transpiler.js");

argParser.arg(i => i);
argParser.option("p", "print");
argParser.option("u", "ugly");
argParser.option("e", "eval", [source => source]);

const {args, options} = argParser.parse();

const sourceFile = path.resolve(
    process.cwd(),
    args[0]
);

switch (true) {
    case (options.print !== undefined): {
        const sourceCode = fs.readFileSync(sourceFile, {encoding: 'utf8'});
        const transpiledCode = transpile(sourceCode, options.ugly === undefined);
        console.log(transpiledCode);
        break;
    }
    case (options.eval !== undefined): {
        const transpiledCode = transpile(options.eval[0]);
        new Function(transpiledCode)();
        break;
    }
    default: {
        require("../require.js");
        require(sourceFile);
    }
}
