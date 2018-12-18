const {createFilter} = require("rollup-pluginutils");
const transpile = require("../compiler/compiler.js");

module.exports = function teascriptPlugin(options = {}) {
    const filter = createFilter(options.include, options.exclude);

    return {
        transform(code, id) {
            if (!filter(id)) {
                return;
            }

            return {
                code: transpile(code),
                map: {mappings: ""}
            };
        }
    };
};
