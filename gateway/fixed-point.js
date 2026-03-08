/**
 * Fixed-point Math Library (Deterministic)
 * Scale: 1000
 */

export const FP_SCALE = 1000;

export function fpRound(n) {
    if (n >= 0) {
        return Math.floor(n + 0.5);
    } else {
        return Math.ceil(n - 0.5);
    }
}

export function fpFromFloat(f) {
    return fpRound(f * FP_SCALE);
}

export function fpToFloat(i) {
    return i / FP_SCALE;
}

export function fpAdd(a, b) {
    return a + b;
}

export function fpSub(a, b) {
    return a - b;
}

export function fpMul(a, b) {
    return fpRound((a * b) / FP_SCALE);
}

export function fpDiv(a, b) {
    if (b === 0) return 0;
    return fpRound((a * FP_SCALE) / b);
}

export function fpAbs(a) {
    return Math.abs(a);
}

export function fpSign(a) {
    return a > 0 ? 1 : (a < 0 ? -1 : 0);
}

export function fpClamp(val, minVal, maxVal) {
    return Math.max(minVal, Math.min(maxVal, val));
}

export function fpDistSq(x1, y1, x2, y2) {
    const dx = fpSub(x2, x1);
    const dy = fpSub(y2, y1);
    return fpAdd(fpMul(dx, dx), fpMul(dy, dy));
}

export function fpDot(x1, y1, x2, y2) {
    return fpAdd(fpMul(x1, x2), fpMul(y1, y2));
}

export function fpSqrt(a) {
    return fpFromFloat(Math.sqrt(fpToFloat(a)));
}

export function fpLength(x, y) {
    return fpSqrt(fpDot(x, y, x, y));
}

/**
 * Deterministic PRNG: matches fb-next-rand in Lisp (src/utils.lisp)
 */
export function fbNextRand(seed) {
    const s = BigInt(seed);
    const newSeed = Number((s * 1103515245n + 12345n) % 2147483648n);
    const val = newSeed / 2147483648.0;
    return [newSeed, val];
}

export function fbRandInt(seed, max) {
    const [newSeed, val] = fbNextRand(seed);
    return [newSeed, Math.floor(val * max)];
}
