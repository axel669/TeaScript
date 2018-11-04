const fs = require("fs");

const parser = require("./TeaScript.js");
const $code = fs.readFileSync(process.argv[2], {encoding: "utf8"});

console.log(
    parser.parse($code).code
);
