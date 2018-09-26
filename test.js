const fs = require("fs");

const parser = require("./TeaScript.js");

console.log(
    parser.parse(
        fs.readFileSync("immutable-update.tea", {encoding: 'utf8'})
    )
);
