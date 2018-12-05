const fs = require("fs");

// const beautify = require("js-beautify");
const prettier = require("prettier");

const parser = require("./parser.js");
const compile = require("./tree2js.js");

const prettyOptions = {
    tabWidth: 4,
    arrowParens: "always",
    parser: "babylon"
};

// const test = fs.readFileSync("../point.tea", {encoding: "utf8"});
// const test = `
// try {
//     thing()
// }
//
// try {
//     thing2()
// }
// catch err {
//     console.log(err)
// }
//
// try {
//     wat()
// }
// finally {
//     clean()
// }
// `;

// const result = parser.parse(test);
// const code = compile(result);
//
// if (code !== null) {
//     const pretty = prettier.format(code, prettyOptions);
//     console.log(code);
//     console.log('----------------------------------------------');
//     console.log(pretty);
// }

module.exports = (tea, makePretty = true) => {
    const rawJS = compile(
        parser.parse(tea)
    );
    if (makePretty === false) {
        return rawJS;
    }
    return prettier.format(
        rawJS,
        prettyOptions
    );
}
