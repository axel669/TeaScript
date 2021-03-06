import resolve from "rollup-plugin-node-resolve";
import commonjs from "rollup-plugin-commonjs";

export default {
    input: "compiler/browser.js",
    output: {
        file: "standalone/transpiler.js",
        format: "iife"
    },
    plugins: [
        resolve({
            browser: true
        }),
        commonjs({
            include: [
                "**"
            ]
        })
    ]
};
