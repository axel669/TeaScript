import country from "./countries.json";
const functionMap = [
    ["ms", "milliseconds", "millisecond"],
    ["s", "seconds", "second"],
    ["min", "minutes", "minute"],
    ["hr", "hours", "hour"],
    ["day", "days"],
    ["wk", "week", "weeks"],
    ["mon", "month", "months"],
    ["qtr", "quarter", "quarters"],
    ["yr", "year", "years"],
    ["decade", "decades"]
].reduce((mapped, names) => {
    const target = names[0];
    for (const name of names) {
        (mapped[name] = target);
    };
    return mapped;
}, {

});
