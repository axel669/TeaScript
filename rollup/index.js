const {createFilter} = require("rollup-pluginutils");
const transpile = require("../compiler/compiler.js");

module.exports = function teascriptPlugin(_options = {}) {
    const {include, exclude, ...options} = _options;
    const filter = createFilter(include, exclude);

    return {
        transform(code, id) {
            if (!filter(id)) {
                return;
            }

            return {
                code: transpile(code, options),
                map: {mappings: ""}
            };
        }
    };
};
