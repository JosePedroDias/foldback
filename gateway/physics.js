/**
 * Shared Fixed-Point Physics & Collision
 */

import { fpAdd, fpMul, fpDistSq, fpSub, fpSqrt, fpDiv, fpClamp, fpAbs } from './fixed-point.js';

// --- Circle vs Circle ---

export function fpCirclesOverlapP(x1, y1, r1, x2, y2, r2) {
    const minDist = fpAdd(r1, r2);
    const minDistSq = fpMul(minDist, minDist);
    const actualDistSq = fpDistSq(x1, y1, x2, y2);
    return actualDistSq < minDistSq;
}

export function fpPushCircles(x1, y1, r1, x2, y2, r2) {
    const dx = fpSub(x1, x2);
    const dy = fpSub(y1, y2);
    const distSq = fpAdd(fpMul(dx, dx), fpMul(dy, dy));
    const minDist = fpAdd(r1, r2);
    const dist = fpSqrt(distSq);
    const overlap = fpSub(minDist, dist);

    if (dist === 0) {
        return { nx: 1000, ny: 0, overlap: minDist };
    }
    return {
        nx: fpDiv(dx, dist),
        ny: fpDiv(dy, dist),
        overlap: overlap
    };
}

// --- Circle vs Segment ---

export function fpClosestPointOnSegment(px, py, x1, y1, x2, y2) {
    const dx = fpSub(x2, x1);
    const dy = fpSub(y2, y1);
    const lenSq = fpAdd(fpMul(dx, dx), fpMul(dy, dy));
    const tProj = (lenSq === 0) ? 0 : fpClamp(fpDiv(fpAdd(fpMul(fpSub(px, x1), dx), fpMul(fpSub(py, y1), dy)), lenSq), 0, 1000);
    
    return {
        x: fpAdd(x1, fpMul(tProj, dx)),
        y: fpAdd(y1, fpMul(tProj, dy))
    };
}

// --- AABB ---

export function fpAABBOverlapP(x1, y1, w1, h1, x2, y2, w2, h2) {
    const halfW1 = w1 / 2;
    const halfH1 = h1 / 2;
    const halfW2 = w2 / 2;
    const halfH2 = h2 / 2;

    return (fpAbs(fpSub(x1, x2)) < fpAdd(halfW1, halfW2)) &&
           (fpAbs(fpSub(y1, y2)) < fpAdd(halfH1, halfH2));
}
