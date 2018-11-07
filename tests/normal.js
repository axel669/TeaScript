import update from "immutable-update-values";
const b = Date.now();
const itemSource = {
    source: {
        [b + 1]: {
            name: "Herbs",
            weight: 0.25
        },
        [b + 2]: {
            name: "Sword",
            weight: 2
        },
        [b + 3]: {
            name: "Backpack",
            weight: null,
            limit: null
        },
        [b + 4]: {
            name: "Candle",
            weight: 0.5
        },
        [b + 5]: {
            name: "Bag of Holding",
            weight: 5,
            limit: 500
        },
        [b + 6]: {
            name: "Kobold Skull",
            weight: 0
        }
    },
    structure: [
        [b + 1, 5],
        [b + 2, 2],
        [b + 3, [
            [b + 4, 3],
            [b + 5, [
                [b + 6, 2]
            ]]
        ]]
    ]
};
export default (state = itemSource, action) => {
    return (() => {
        switch (action.type) {
            case "inventory.update.count":
                {
                    return update(state, {
                        [`structure.${action.path}.1.$apply`]: (value) => {
                            return value + action.value;
                        }
                    });
                    break;;
                }
            default:
                {
                    return state;
                }
        }
    })();
};

