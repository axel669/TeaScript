const Point = (() => {
    const construct = function construct(x, y) {
        const self = {};
        Object.defineProperties(this, {
            x: {
                get: () => {
                    return self.x;
                }
            },
            y: {
                get: () => {
                    return self.y;
                }
            },
            mag: {
                get: () => {
                    return Math.pow(
                        Math.pow(self.x, 2) + Math.pow(self.y, 2),
                        0.5
                    );
                }
            }
        });
        this.add = (point) => {
            return Point(point.x + self.x, point.y + self.y);
        };
        this.toString = () => {
            return `Point(${self.x}, ${self.y})`;
        };
        this.normalize = () => {
            return Point(self.x / this.mag, self.y / this.mag);
        };
        this.taxicab = function*(dest) {
            for (const x of range(self.x, dest.x, 1)) {
                yield Point(x, self.y);
            }
            for (const y of range(self.y, dest.y, 1)) {
                yield Point(dest.x, y);
            }
        }.bind(this);
        this.print = () => {
            return console.log(this.toString());
        };
        Point.count += 1;
        [self.x, self.y] = [x, y];
        return this;
    };
    return (...args) => construct.apply({}, args);
})();
Point.count = 0;
const a = Point(1, 2);
const b = Point(3, 4);
a.add(b).print();
a.add(b)
    .normalize()
    .print();

