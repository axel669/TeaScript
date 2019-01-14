#!/usr/bin/env node

const path = require("path");
const fs = require("fs");

const glob = require("glob");
const mkdirp = require("mkdirp");

const transpile = require("../compiler/compiler.js");
const argv = require("@axel669/arg-parser")({
    "_:": [i => i],
    "print:p|print": undefined,
    "targetFile:o|output|target-file": [i => i],
    "eval:e|eval": [i => i],
    "help:h|help": undefined,
    "sourceCode:s|source-code": [i => i],
    "ugly:u|ugly": undefined,
    "noImport:no-import": undefined,
    "directory:d|directory|dir": [i => i, i => i]
});

const sourceFile = (argv._.length > 0)
    ? path.resolve(
        process.cwd(),
        argv._[0]
    )
    : null;
const compilerOptions = {
    makePretty: argv.ugly !== true,
    importAsRequire: argv.noImport === true
};

try {
    switch (true) {
        case (argv.help === true): {
            const package = require("../package.json");
            console.log(`${package.name} ${package.version}`);
            break;
        }
        case (argv.directory !== undefined): {
            const [source, dest] = argv.directory;
            const replacerRegex = new RegExp(`^${source}`);

            glob(
                `${source}/**/*.tea`.replace("//", "/"),
                (err, files) => {
                    for (const file of files) {
                        console.log(">", file);
                        const destFile = file
                            .replace(replacerRegex, dest)
                            .replace(/\.tea$/, ".js");
                        const sourceCode = fs.readFileSync(file, {encoding: 'utf8'});
                        const transpiledCode = transpile(sourceCode, compilerOptions);

                        mkdirp.sync(
                            path.dirname(destFile)
                        );

                        fs.writeFileSync(
                            destFile,
                            transpiledCode
                        );
                    }
                }
            );
            break;
        }
        case (argv.targetFile !== undefined): {
            const sourceCode = fs.readFileSync(sourceFile, {encoding: 'utf8'});
            const transpiledCode = transpile(sourceCode, compilerOptions);
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
            const transpiledCode = transpile(sourceCode, compilerOptions);
            console.log(transpiledCode);
            break;
        }
        case (argv.eval !== undefined): {
            const transpiledCode = transpile(argv.eval[0], compilerOptions);
            new Function(transpiledCode)();
            break;
        }
        default: {
            require("../require.js");
            require(sourceFile);
        }
    }
}
catch (error) {
    if (error.location !== undefined) {
        const {start, end} = error.location;
        const snippet = error.sourceCode.substring(
            start.offset - start.column + 1,
            end.offset + 5
        )
        const arrow = " ".repeat(start.column + 1) + "^"
        console.error(
            `Parse Error\n  Line: ${start.line}\n  ${snippet}\n${arrow}\n${error.message}\n`
        );
        // console.log(error.location);
    }
    else {
        throw error;
    }
}
