import parser from "./parser.js";
import compile from "./tree2js.js";

const prettyOptions = {
    tabWidth: 4,
    arrowParens: "always",
    parser: "babylon"
};

const transpile = (tea, options = {}) => {
    try {
        return compile(
            parser.parse(tea),
            options
        );
    }
    catch (error) {
        if (error.location !== undefined) {
            error.sourceCode = tea;
        }
        throw error;
    }
};

document.addEventListener(
    "DOMContentLoaded",
    evt => {
        const scripts = [
            ...document.querySelectorAll("script[type='text/teascript']")
        ];
        for (const scriptTag of scripts) {
            new Function(
                transpile(scriptTag.innerText)
            )();
            // console.log(scriptTag.innerText);
        }
    }
);
