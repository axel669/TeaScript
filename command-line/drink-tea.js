#!/usr/bin/env node

const path = require("path");
const fs = require("fs");

const transpile = require("../compiler/compiler.js");
const argv = require("@axel669/arg-parser")({
    "_:": [i => i],
    "print:p|print": undefined,
    "targetFile:o|output|target-file": [i => i],
    "eval:e|eval": [i => i],
    "help:h|help": undefined,
    "sourceCode:s|source-code": [i => i]
});

const sourceFile = (argv._.length > 0)
    ? path.resolve(
        process.cwd(),
        argv._[0]
    )
    : null;

switch (true) {
    case (argv.help === true): {
        const package = require("../package.json");
        console.log(`${package.name} ${package.version}`);
        break;
    }
    case (argv.targetFile !== undefined): {
        const sourceCode = fs.readFileSync(sourceFile, {encoding: 'utf8'});
        const transpiledCode = transpile(sourceCode, argv.ugly !== true);
        fs.writeFileSync(
            path.resolve(
                process.cwd(),
                argv.targetFile[0]
            ),
            transpiledCode
        );
        break;
    }
    case (argv.print === true): {
        const sourceCode = (argv.sourceCode === undefined)
            ? fs.readFileSync(sourceFile, {encoding: 'utf8'})
            : argv.sourceCode[0];
        const transpiledCode = transpile(sourceCode, argv.ugly !== true);
        console.log(transpiledCode);
        break;
    }
    case (argv.eval !== undefined): {
        const transpiledCode = transpile(argv.eval[0]);
        new Function(transpiledCode)();
        break;
    }
    default: {
        require("../require.js");
        require(sourceFile);
    }
}
