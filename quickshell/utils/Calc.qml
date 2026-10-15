pragma Singleton
import Quickshell

// Launcher calculator. No eval: a small recursive-descent parser.
// - Math: + - * / % ^, parentheses, unary minus, pi, e, and sqrt sin cos tan asin acos atan
//   log (base 10) ln abs round floor ceil.
// - Units: "<number> <unit> to|in <unit>", e.g. "10 km to mi", "72 f in c", "3.5 gb to mib".
// evaluate() returns the result as text, or "" if the input isn't a calculation.
Singleton {
    id: root

    // factor to the base unit of its group; temperatures are handled separately
    readonly property var units: ({
        // length (m)
        mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000],
        in: ["len", 0.0254], inch: ["len", 0.0254], ft: ["len", 0.3048], yd: ["len", 0.9144], mi: ["len", 1609.344],
        // mass (kg)
        mg: ["mass", 1e-6], g: ["mass", 0.001], kg: ["mass", 1], t: ["mass", 1000], oz: ["mass", 0.028349523125], lb: ["mass", 0.45359237],
        // time (s)
        ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], min: ["time", 60], h: ["time", 3600], hr: ["time", 3600], d: ["time", 86400], day: ["time", 86400], week: ["time", 604800],
        // data (bytes)
        b: ["data", 1], kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
        kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824], tib: ["data", 1099511627776],
        // volume (l)
        ml: ["vol", 0.001], l: ["vol", 1], gal: ["vol", 3.785411784],
        // speed (m/s)
        "km/h": ["speed", 1 / 3.6], kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704], "m/s": ["speed", 1],
        // temperature (special)
        c: ["temp", 0], f: ["temp", 0], k: ["temp", 0]
    })

    function format(v) {
        if (!isFinite(v))
            return "";
        const r = Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0) ? v.toExponential(6) : String(Math.round(v * 1e10) / 1e10);
        return r;
    }

    function evaluate(input) {
        const s = input.trim().toLowerCase();
        if (s === "")
            return "";
        const conv = s.match(/^(.+?)\s*([a-z/]+)\s+(?:to|in)\s+([a-z/]+)$/);
        if (conv) {
            const n = root.math(conv[1]);
            const r = n === null ? null : root.convert(n, conv[2], conv[3]);
            if (r !== null)
                return root.format(r) + " " + conv[3];
        }
        // Only treat it as maths if it has an operator or a function (so "2048" isn't a "result")
        if (!/[-+*/%^()]|\b(sqrt|sin|cos|tan|asin|acos|atan|log|ln|abs|round|floor|ceil|pi)\b/.test(s))
            return "";
        const v = root.math(s);
        return v === null ? "" : root.format(v);
    }

    function convert(n, from, to) {
        const a = root.units[from], b = root.units[to];
        if (!a || !b || a[0] !== b[0])
            return null;
        if (a[0] !== "temp")
            return n * a[1] / b[1];
        const k = from === "c" ? n + 273.15 : from === "f" ? (n - 32) * 5 / 9 + 273.15 : n;
        return to === "c" ? k - 273.15 : to === "f" ? (k - 273.15) * 9 / 5 + 32 : k;
    }

    // --- parser ---
    function math(src) {
        const toks = src.match(/\d+(?:\.\d+)?(?:e[-+]?\d+)?|\.\d+|[a-z]+|\*\*|[-+*/%^()]/g);
        if (!toks || toks.join("") !== src.replace(/\s+/g, ""))
            return null;
        let i = 0;
        const peek = () => toks[i];
        const take = () => toks[i++];
        const fns = { sqrt: Math.sqrt, sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
            log: Math.log10, ln: Math.log, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil };
        function expr() {
            let v = term();
            while (peek() === "+" || peek() === "-")
                v = take() === "+" ? v + term() : v - term();
            return v;
        }
        function term() {
            let v = unary();
            while (peek() === "*" || peek() === "/" || peek() === "%") {
                const op = take(), r = unary();
                v = op === "*" ? v * r : op === "/" ? v / r : v % r;
            }
            return v;
        }
        // Power binds tighter than unary minus: -3^2 = -9, 2^-1 = 0.5
        function unary() {
            if (peek() === "-") { take(); return -unary(); }
            if (peek() === "+") { take(); return unary(); }
            return power();
        }
        function power() {
            const b = atom();
            if (peek() === "^" || peek() === "**") {
                take();
                return Math.pow(b, unary());
            }
            return b;
        }
        function atom() {
            const t = take();
            if (t === undefined)
                throw "end";
            if (t === "(") {
                const v = expr();
                if (take() !== ")")
                    throw "paren";
                return v;
            }
            if (t === "pi")
                return Math.PI;
            if (t === "e")
                return Math.E;
            if (t in fns) {
                if (take() !== "(")
                    throw "call";
                const v = expr();
                if (take() !== ")")
                    throw "paren";
                return fns[t](v);
            }
            const n = Number(t);
            if (isNaN(n))
                throw "token";
            return n;
        }
        try {
            const v = expr();
            return i === toks.length ? v : null;
        } catch (e) {
            return null;
        }
    }
}
