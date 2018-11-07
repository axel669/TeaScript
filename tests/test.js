const fs = require("fs");

const beautify = require("js-beautify");

const parser = require("./TeaScript.js");
const $code = fs.readFileSync(process.argv[2], {encoding: "utf8"});

console.time("parse time");
const {code} = parser.parse($code)
const bcode = beautify(
    code,
    {
        indent_size: 4,
        break_chained_methods: true,
        end_with_newline: true,
        brace_style: "end-expand"
    }
);
console.timeEnd("parse time");

console.log(
    bcode
);
