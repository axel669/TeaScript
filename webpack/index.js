const transpile = require("../compiler/compiler.js");

module.exports = function (source, options) {
    return transpile(source, this.query || {});
};
