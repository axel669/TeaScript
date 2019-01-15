const prettier = require("prettier");

const parser = require("./parser.js");
const compile = require("./tree2js.js");

const prettyOptions = {
    tabWidth: 4,
    arrowParens: "always",
    parser: "babylon"
};

module.exports = (tea, {makePretty, ...options} = {}) => {
    try {
        const rawJS = compile(
            parser.parse(tea),
            options
        );
        if (makePretty === false) {
            return rawJS;
        }
        return prettier.format(
            rawJS,
            prettyOptions
        );
    }
    catch (error) {
        if (error.location !== undefined) {
            error.sourceCode = tea;
        }
        throw error;
    }
}
