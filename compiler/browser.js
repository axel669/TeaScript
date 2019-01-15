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
    async evt => {
        const scripts = [
            ...document.querySelectorAll("script[type='text/teascript']")
        ];
        for (const scriptTag of scripts) {
            let source = scriptTag.innerText;

            if (scriptTag.src !== "") {
                const response = await fetch(scriptTag.src);

                if (response.status < 200 || response.status >= 300) {
                    throw new Error(await response.text());
                }
                source = await response.text();
            }

            new Function(
                transpile(source)
            )();
        }
    }
);
