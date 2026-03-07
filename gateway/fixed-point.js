/**
 * Fixed-point Math Library (Deterministic)
 * Scale: 1000
 */

const FP_SCALE = 1000;

function fpRound(n) {
    if (n >= 0) {
        return Math.floor(n + 0.5);
    } else {
        return Math.ceil(n - 0.5);
    }
}

function fpFromFloat(f) {
    return fpRound(f * FP_SCALE);
}

function fpToFloat(i) {
    return i / FP_SCALE;
}

function fpAdd(a, b) {
    return a + b;
}

function fpSub(a, b) {
    return a - b;
}

function fpMul(a, b) {
    return fpRound((a * b) / FP_SCALE);
}

function fpDiv(a, b) {
    if (b === 0) return 0;
    return fpRound((a * FP_SCALE) / b);
}

function fpAbs(a) {
    return Math.abs(a);
}

function fpSign(a) {
    return a > 0 ? 1 : (a < 0 ? -1 : 0);
}

function fpClamp(val, minVal, maxVal) {
    return Math.max(minVal, Math.min(maxVal, val));
}

function fpDistSq(x1, y1, x2, y2) {
    const dx = fpSub(x2, x1);
    const dy = fpSub(y2, y1);
    return fpAdd(fpMul(dx, dx), fpMul(dy, dy));
}

function fpDot(x1, y1, x2, y2) {
    return fpAdd(fpMul(x1, x2), fpMul(y1, y2));
}

function fpSqrt(a) {
    return fpFromFloat(Math.sqrt(fpToFloat(a)));
}

function fpLength(x, y) {
    return fpSqrt(fpDot(x, y, x, y));
}

/**
 * Deterministic PRNG: matches fb-next-rand in Lisp (src/utils.lisp)
 */
function fbNextRand(seed) {
    const s = BigInt(seed);
    const newSeed = Number((s * 1103515245n + 12345n) % 2147483648n);
    const val = newSeed / 2147483648.0;
    return [newSeed, val];
}

function fbRandInt(seed, max) {
    const [newSeed, val] = fbNextRand(seed);
    return [newSeed, Math.floor(val * max)];
}

if (typeof module !== 'undefined') {
    module.exports = {
        FP_SCALE,
        fpRound,
        fpFromFloat,
        fpToFloat,
        fpAdd,
        fpSub,
        fpMul,
        fpDiv,
        fpAbs,
        fpSign,
        fpClamp,
        fpDistSq,
        fpDot,
        fpSqrt,
        fpLength,
        fbNextRand,
        fbRandInt
    };
}
