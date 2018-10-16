const Module = require("module");
const path = require("path");
const fs = require("fs");

const tea = require("./TeaScript.js");

const req = Module.prototype.require;
Module.prototype.require = function(src) {
    if (src.endsWith(".tea") === true) {
        const fileName = require.resolve(src);
        const source = tea.parse(fs.readFileSync(fileName, {encoding: "utf8"})).code;
        const m = new Module(src, module.parent);
        m.filename = fileName;
        m._compile(source, src);
        return m.exports;
    }
    return req.call(this, src);
};
