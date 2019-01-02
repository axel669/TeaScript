# TeaScript
For people that don't care for Coffee

TeaScript is a JavaScript-like language inspired by a few different languages
including CoffeeScript and Rust.
The syntax is very similar to standard JS with some changes directly
from CS.

The biggest difference from standard JS is the lack of semicolons. Semicolons
are not optional, but are instead not allowed. Rather than attempting to end
expressions early, TS attempts to parse expressions as long as it can
reasonably (With one change to function call syntax to facilitate this).

## Variables
```js
let pi = 3.141592
let e = 2.718
let mut lastUpdate = Date.now()
let mut x
let mut y
```

## Numbers
```js
3 + 0.14 + 1e5 + 0x92 + 0b11111111 + 0o65
```

## Functions
```js
let f = (x) => x ** 2
let abs = (x) => {
    if x < 0 {
        return -x
    }
    return x
}

let pow = (a, b = 2) => a ** b

let tail = ([head, ...tail]) => tail
let tailObj = ({head, ...tail}) => tail

let noOp = () => {null}
let emptyObj = () => {}
let merge = (a, b) => {
    ...a
    ...b
}

// Calling
f(10)
abs(-5)
pow(2)
pow(2, 4)
tail([1, 2, 3, 4])
noOp()

//  Not a call
f
(10)
```

## Strings
```js
let basicString = "basic string"
let multiline = "multiline
string"
let interpolated = "${value} interpolated"
```
