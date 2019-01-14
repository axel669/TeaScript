const parser = require("../TeaScript.js");
const beautify = require("js-beautify");

const beautifyOptions = {
    indent_size: 4,
    break_chained_methods: true,
    end_with_newline: true,
    brace_style: "end-expand"
};

module.exports = (source, {makePretty, ...options} = {}) => {
    const {code} = parser.parse(source, options);
    return (makePretty === true)
        ? beautify(code, beautifyOptions)
        : code;
};
