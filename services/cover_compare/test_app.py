"""
Minimal smoke coverage for the sidecar itself — the real validation
already happened empirically against ~65 real book covers (see the
2026-08-08 eval, not part of this repo's test suite). This just confirms
the HTTP plumbing and the three qualitative outcomes the eval
established: same image scores highest, a real image scores near zero
against an unrelated one, and a too-small/blank image degrades cleanly
instead of raising.
"""
import io

import numpy as np
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app import app

client = TestClient(app)


def _jpeg_bytes(array):
    buf = io.BytesIO()
    Image.fromarray(array).save(buf, format="JPEG")
    return buf.getvalue()


def _textured_image(seed):
    # ORB needs real texture/corners to find keypoints on — flat noise
    # stands in for a book-cover-like image without needing test fixtures.
    rng = np.random.default_rng(seed)
    return _jpeg_bytes(rng.integers(0, 255, size=(300, 200, 3), dtype=np.uint8))


def _shaped_image(width, height, seed):
    # Unlike _textured_image's per-pixel noise (which has no structure
    # that survives resizing — every pixel is independent, so downscaling
    # then rescaling destroys it completely), real book covers have
    # large-scale structure — edges, shapes, gradients — that DOES
    # survive resizing. A synthetic image needs that same property to
    # stand in for "the same cover at a different resolution."
    rng = np.random.default_rng(seed)
    img = Image.new("RGB", (width, height), tuple(rng.integers(0, 255, size=3)))
    draw = ImageDraw.Draw(img)
    for _ in range(15):
        shape = rng.choice(["rectangle", "ellipse"])
        x0, y0 = rng.integers(0, width * 3 // 4), rng.integers(0, height * 3 // 4)
        x1, y1 = x0 + rng.integers(width // 8, width // 3), y0 + rng.integers(height // 8, height // 3)
        color = tuple(int(c) for c in rng.integers(0, 255, size=3))
        getattr(draw, shape)([x0, y0, x1, y1], fill=color, outline="black", width=3)
    return np.array(img)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_identical_images_score_high():
    img = _textured_image(1)
    response = client.post(
        "/compare",
        files={"image_a": ("a.jpg", img, "image/jpeg"), "image_b": ("b.jpg", img, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["ratio"] > 0.9  # identical content, modulo JPEG re-encode noise
    assert body["inliers"] > 0


def test_the_same_cover_at_wildly_different_resolutions_still_scores_high():
    # Real bug, found live 2026-08-08: ISFDB scans and Goodreads' RSS
    # thumbnails routinely differ 3-5x in resolution. A genuinely
    # identical cover at ~5.7x apart scored 0.003 (indistinguishable from
    # a real conflict) before normalization was added, 0.34+ after.
    full_res = _shaped_image(600, 900, seed=7)
    thumbnail = np.array(Image.fromarray(full_res).resize((100, 150)))

    response = client.post(
        "/compare",
        files={"image_a": ("a.jpg", _jpeg_bytes(full_res), "image/jpeg"), "image_b": ("b.jpg", _jpeg_bytes(thumbnail), "image/jpeg")},
    )

    assert response.status_code == 200
    assert response.json()["ratio"] > 0.2


def test_unrelated_images_score_near_zero():
    response = client.post(
        "/compare",
        files={
            "image_a": ("a.jpg", _textured_image(1), "image/jpeg"),
            "image_b": ("b.jpg", _textured_image(2), "image/jpeg"),
        },
    )
    assert response.status_code == 200
    assert response.json()["ratio"] < 0.05


def test_too_small_to_find_keypoints_degrades_to_zero_not_an_error():
    tiny = _jpeg_bytes(np.zeros((4, 4, 3), dtype=np.uint8))
    response = client.post(
        "/compare",
        files={"image_a": ("a.jpg", tiny, "image/jpeg"), "image_b": ("b.jpg", tiny, "image/jpeg")},
    )
    assert response.status_code == 200
    assert response.json()["ratio"] == 0.0


def test_undecodable_upload_is_a_422_not_a_500():
    response = client.post(
        "/compare",
        files={"image_a": ("a.jpg", b"not an image", "image/jpeg"), "image_b": ("b.jpg", _textured_image(1), "image/jpeg")},
    )
    assert response.status_code == 422
