const fs = require("fs");

const beautify = require("js-beautify");

const parser = require("./parser.js");
const compile = require("./tree2js.js");

const beautifyOptions = {
    indent_size: 4,
    break_chained_methods: true,
    end_with_newline: true,
    brace_style: "end-expand"
};

// const test = fs.readFileSync("../point.tea", {encoding: "utf8"});
const test = `
for key of obj {
    console.log(key)
}
for key, value of obj {
    console.log(key, value)
}

for item in items {
    console.log(item)
}
for name in set {
    console.log(name)
}
`;
// const test = "let a = if Math.random() < 0.5 { break 10 } else { break 0 }";

const result = parser.parse(test);
const code = compile(result);

const pretty = beautify(code, beautifyOptions);
console.log(pretty);

// fs.writeFileSync("results.json", JSON.stringify(result, null, "    "));
