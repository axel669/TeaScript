const argParsers = [];
const addArg = parser => argParsers.push(parser);

const optionParsers = {};
const optionNames = {};
const addOption = (shortName, longName, parsers = []) => {
    if (shortName !== null) {
        optionParsers[shortName] = parsers;
        optionNames[shortName] = longName || "";
    }
    if (longName !== null) {
        optionParsers[longName] = parsers;
    }
};

module.exports = {
    arg: addArg,
    option: addOption,
    parse() {
        const sourceArgs = process.argv.slice(2);

        const parsers = [[null, argParsers]];
        let tokens = [];

        for (const arg of sourceArgs) {
            if (arg.startsWith("-") === true) {
                const [, dashes, name] = arg.match(/(\-\-?)(.+)/);
                if (dashes === "-") {
                    for (const letter of name) {
                        parsers.push([optionNames[letter], optionParsers[letter]]);
                    }
                }
                else {
                    parsers.push([name, optionParsers[name]]);
                }
            }
            else {
                tokens.push(arg);
            }
        }

        const args = {options: {}};
        for (const [name, parserList] of parsers) {
            const values = parserList.map(
                (parser, index) => parser(tokens[index])
            );
            tokens = tokens.slice(parserList.length);
            if (name === null) {
                args.args = values;
            }
            else {
                args.options[name] = values;
            }
        }

        return args;
    }
};
