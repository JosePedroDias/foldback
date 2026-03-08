// tests/fixed-point-cross-test.js

import * as fs from 'fs';
import * as assert from 'assert';
import * as fp from '../gateway/fixed-point.js';

// 1. Read and parse the Lisp results file
const lispResults = new Map();
const resultsFile = fs.readFileSync('tests/fixed-point-results.dat', 'utf8');
const lines = resultsFile.split('\n');
const lineRegex = /\("(.+)" \. (-?\d+)\)/;

for (const line of lines) {
    if (line.trim() === '') continue;
    const match = line.match(lineRegex);
    if (match) {
        lispResults.set(match[1], parseInt(match[2], 10));
    } else {
        console.error(`Could not parse line: ${line}`);
    }
}

console.log('Lisp results loaded. Running JS tests...');

// 2. Run JS tests and assert against Lisp results
function runTest(testName, jsResult) {
    const lispResult = lispResults.get(testName);
    // console.log(`[${testName}] Lisp: ${lispResult}, JS: ${jsResult}`);
    assert.strictEqual(jsResult, lispResult, `Mismatch in test: ${testName}`);
}

// --- Test Cases (must match Lisp test file exactly) ---
const v1 = fp.fpFromFloat(3.5);
const v2 = fp.fpFromFloat(-3.5);
const v3 = fp.fpFromFloat(8.0);
const v4 = fp.fpFromFloat(-10.0);

// fp-round (as part of fpFromFloat)
runTest("round_1", fp.fpFromFloat(0.0));
runTest("round_2", fp.fpFromFloat(0.499));
runTest("round_3", fp.fpFromFloat(0.5));
runTest("round_4", fp.fpFromFloat(0.501));
runTest("round_5", fp.fpFromFloat(-0.499));
runTest("round_6", fp.fpFromFloat(-0.5));
runTest("round_7", fp.fpFromFloat(-0.501));

// fp-abs
runTest("abs_1", fp.fpAbs(v1));
runTest("abs_2", fp.fpAbs(v2));
runTest("abs_3", fp.fpAbs(fp.fpFromFloat(0)));

// fp-sign
runTest("sign_1", fp.fpSign(v1));
runTest("sign_2", fp.fpSign(v2));
runTest("sign_3", fp.fpSign(fp.fpFromFloat(0)));

// fp-clamp
runTest("clamp_1", fp.fpClamp(fp.fpFromFloat(5.0), fp.fpFromFloat(0), fp.fpFromFloat(10.0)));
runTest("clamp_2", fp.fpClamp(fp.fpFromFloat(-5.0), fp.fpFromFloat(0), fp.fpFromFloat(10.0)));
runTest("clamp_3", fp.fpClamp(fp.fpFromFloat(15.0), fp.fpFromFloat(0), fp.fpFromFloat(10.0)));

// fp-add, fp-sub, fp-mul, fp-div
runTest("add_1", fp.fpAdd(v1, v3));
runTest("sub_1", fp.fpSub(v3, v1));
runTest("mul_1", fp.fpMul(v1, v2));
runTest("div_1", fp.fpDiv(v4, v1));
runTest("div_2", fp.fpDiv(v3, fp.fpFromFloat(0)));

// fp-dot, fp-dist-sq, fp-length
runTest("dot_1", fp.fpDot(v1, v2, v3, v4));
runTest("dist_sq_1", fp.fpDistSq(v1, v2, v3, v4));
runTest("length_1", fp.fpLength(v3, v4));

// fp-sqrt
runTest("sqrt_1", fp.fpSqrt(fp.fpFromFloat(144.0)));
runTest("sqrt_2", fp.fpSqrt(fp.fpFromFloat(2.0)));
runTest("sqrt_3", fp.fpSqrt(fp.fpFromFloat(-4.0)));

// fp-to-float
runTest("to_float_1", Math.round(fp.fpToFloat(fp.fpFromFloat(123.456)) * 1000));

// fb-rand-int
const [seed1, val1] = fp.fbRandInt(1, 100);
runTest("rand_1_seed", seed1);
runTest("rand_1_val", val1);

const [seed2, val2] = fp.fbRandInt(seed1, 100);
runTest("rand_2_seed", seed2);
runTest("rand_2_val", val2);

console.log('✅ All fixed-point cross-tests passed!');
