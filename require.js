const Module = require("module");
const path = require("path");
const fs = require("fs");

// const tea = require("./TeaScript.js");
const transpile = require("./command-line/transpiler.js");

const _load = Module.prototype.load;
Module.prototype.load = function(source) {
    if (source.endsWith(".tea") === true) {
        const fileName = require.resolve(source);
        const code = transpile(
            fs.readFileSync(fileName, {encoding: "utf8"})
        );
        // const code = tea.parse(
        //     fs.readFileSync(fileName, {encoding: "utf8"})
        // ).code;

        this.filename = source;
        this.paths = Module._nodeModulePaths(path.dirname(fileName));
        this._compile(code, source);
    }
    else {
        _load.call(this, source);
    }
    this.loaded = true;
    return true;
};
