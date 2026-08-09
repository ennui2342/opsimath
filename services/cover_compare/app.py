"""
cover-compare — a pure image-similarity computation service, no policy.

Answers one question: "how much of image A's content re-appears in image
B under a consistent geometric transform?" via ORB keypoint matching +
RANSAC homography fitting. Deliberately not perceptual hashing (pHash) —
validated empirically against ~65 real book-cover pairs (opsimath,
2026-08-08) that pHash can't reliably separate "same cover, cluttered
with an added badge" from "a genuinely different cover that happens to
share a catalog ID" (isfdb-adapter's own documented ISBN-reuse caveat),
while ORB+RANSAC gives a clean, wide separation between those two cases
because it reasons about *local* correspondence, not a global summary.

What "ratio" means and how to use it (decided in the eval, not here):
inlier keypoint count divided by the smaller image's total keypoint
count, computed AFTER both images are rescaled to a common canonical
size (see _normalize) — ISFDB scans and Goodreads' RSS-feed thumbnails
routinely differ 3-5x in resolution (Goodreads' own image URLs literally
encode a target size, e.g. `_SY475_`/`_SX50_`), and ORB's keypoint
repeatability degrades badly across that big a scale gap even for the
identical cover — confirmed live, 2026-08-08: a real same-cover pair at
5.7x apart scored 0.003 unnormalized (indistinguishable from a genuinely
different cover) and 0.34 once rescaled to the same size first. Without
this step the scale gap dominates the score more than actual cover
similarity does.

Empirically (post-normalization): genuinely different covers score
under ~0.01; editions sharing the same base artwork but with a real
printed difference (a badge, a blurb, retypeset text) score ~0.02-0.14;
the same photographed object under different lighting/crop/angle scores
~0.08 and up, usually well above 0.2. There's a narrow, understood
overlap band (~0.08-0.14) for severe cases — a real angled photo, a
badly out-of-focus source photo, a big crop-area mismatch (front-only
vs. full wraparound scan), or a cover that's mostly flat/low-texture
(large solid-color fields, bold sparse typography give ORB little to
find keypoints on regardless of scale) — where the two classes aren't
cleanly separable; the caller is expected to treat that band as "still
uncertain, don't auto-resolve," not push the threshold to try to split
it. THIS SERVICE ONLY COMPUTES THE NUMBER — deciding what counts as "the
same" is a policy call that belongs to the caller (opsimath's
Enrichment::CoverApplier), not here, the same way FieldApplier's own
plan/commit split keeps "what did the fetch say" separate from "what do
we do about it."
"""

import io

import cv2
import numpy as np
from fastapi import FastAPI, File, HTTPException, UploadFile
from pydantic import BaseModel

app = FastAPI(title="cover-compare", version="0.1.0")

_ORB = cv2.ORB_create(nfeatures=2000)
_MATCHER = cv2.BFMatcher(cv2.NORM_HAMMING)

# Long-side target every image is rescaled to before ORB ever sees it —
# picked from the real conflict-pair diagnosis, not a round default: the
# working image sizes across ~90 real cover pairs (both ISFDB scans and
# Goodreads thumbnails) cluster in the 300-800px range, so 600 sits in
# the middle rather than forcing everything up to the largest scan's
# native size (wasteful) or down to the smallest thumbnail's (throws away
# real detail the larger image actually has).
_CANONICAL_LONG_SIDE = 600


class CompareResult(BaseModel):
    ratio: float
    inliers: int
    keypoints_a: int
    keypoints_b: int


def _decode(raw: bytes):
    arr = np.frombuffer(raw, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise ValueError("not a decodable image")
    return _normalize(img)


def _normalize(img):
    long_side = max(img.shape)
    if long_side == _CANONICAL_LONG_SIDE:
        return img

    scale = _CANONICAL_LONG_SIDE / long_side
    interpolation = cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC
    return cv2.resize(img, (round(img.shape[1] * scale), round(img.shape[0] * scale)), interpolation=interpolation)


def _compare(img_a, img_b) -> CompareResult:
    kp_a, des_a = _ORB.detectAndCompute(img_a, None)
    kp_b, des_b = _ORB.detectAndCompute(img_b, None)
    n_a, n_b = len(kp_a or []), len(kp_b or [])

    if des_a is None or des_b is None or n_a < 8 or n_b < 8:
        return CompareResult(ratio=0.0, inliers=0, keypoints_a=n_a, keypoints_b=n_b)

    knn = _MATCHER.knnMatch(des_a, des_b, k=2)
    # Lowe's ratio test — keeps a match only when it's a clearly better
    # fit than the second-best candidate, filtering out ambiguous matches
    # in repetitive/textured regions before RANSAC ever sees them.
    good = [m for m, n in knn if n and m.distance < 0.75 * n.distance]
    if len(good) < 8:
        return CompareResult(ratio=0.0, inliers=0, keypoints_a=n_a, keypoints_b=n_b)

    src = np.float32([kp_a[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([kp_b[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    _, mask = cv2.findHomography(src, dst, cv2.RANSAC, 5.0)
    inliers = int(mask.sum()) if mask is not None else 0

    return CompareResult(ratio=inliers / max(min(n_a, n_b), 1), inliers=inliers, keypoints_a=n_a, keypoints_b=n_b)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/compare", response_model=CompareResult)
async def compare(image_a: UploadFile = File(...), image_b: UploadFile = File(...)):
    try:
        img_a = _decode(await image_a.read())
        img_b = _decode(await image_b.read())
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))

    return _compare(img_a, img_b)
