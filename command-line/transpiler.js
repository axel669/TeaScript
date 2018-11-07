const parser = require("../TeaScript.js");
const beautify = require("js-beautify");

const beautifyOptions = {
    indent_size: 4,
    break_chained_methods: true,
    end_with_newline: true,
    brace_style: "end-expand"
};

module.exports = (source, makePretty = true) => {
    const {code} = parser.parse(source);
    return (makePretty === true)
        ? beautify(code, beautifyOptions)
        : code;
};
