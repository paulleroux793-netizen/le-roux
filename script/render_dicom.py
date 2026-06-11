#!/usr/bin/env python3
# Render a SIDEXIS DICOM (.dcm) to a PNG with adjustable window/level (brightness/contrast),
# applied server-side. Powers the in-Ivory DICOM viewer. Read-only on the archive.
import sys, io
import pydicom, numpy as np
from PIL import Image


def render(path, wc=None, ww=None, invert=False, max_dim=2400):
    ds = pydicom.dcmread(path)
    arr = ds.pixel_array.astype(np.float32)

    # Multi-frame / 3D volumes (e.g. CBCT) come through as a 3D+ array — render a representative
    # MIDDLE slice instead of erroring. RGB images (last axis == 3) are left as-is.
    while arr.ndim > 2 and arr.shape[-1] != 3:
        arr = arr[arr.shape[0] // 2]

    # Modality LUT (rescale) if present.
    slope = float(getattr(ds, "RescaleSlope", 1) or 1)
    intercept = float(getattr(ds, "RescaleIntercept", 0) or 0)
    arr = arr * slope + intercept

    # Window/level: use caller's, else the DICOM's stored window, else full min/max.
    def first(v):
        if v is None:
            return None
        if isinstance(v, (list, tuple)) or (hasattr(v, "__iter__") and not isinstance(v, str)):
            return float(v[0])
        return float(v)

    if wc is None or ww is None:
        wc = first(ds.get("WindowCenter"))
        ww = first(ds.get("WindowWidth"))
    if wc is None or ww is None:
        wc = (float(arr.max()) + float(arr.min())) / 2.0
        ww = (float(arr.max()) - float(arr.min())) or 1.0
    ww = ww or 1.0

    lo = wc - ww / 2.0
    hi = wc + ww / 2.0
    out = np.clip((arr - lo) / (hi - lo) * 255.0, 0, 255).astype(np.uint8)

    # MONOCHROME1 stores inverted; honour it, plus an optional user invert toggle.
    if ds.get("PhotometricInterpretation") == "MONOCHROME1":
        out = 255 - out
    if invert:
        out = 255 - out

    img = Image.fromarray(out)
    if max(img.size) > max_dim:
        img.thumbnail((max_dim, max_dim))
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue(), wc, ww, img.size


if __name__ == "__main__":
    path = sys.argv[1]
    wc = float(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] != "-" else None
    ww = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] != "-" else None
    png, wc, ww, size = render(path, wc, ww)
    sys.stderr.write(f"rendered {len(png)} bytes {size} wc={wc} ww={ww}\n")
    sys.stdout.buffer.write(png)
