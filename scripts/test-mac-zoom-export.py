#!/usr/bin/env python3
"""Read back PNGs exported via native UI. This does not automate or imply screen capture."""
from pathlib import Path
import hashlib
import json
from datetime import datetime, timezone
from PIL import Image, ImageChops, ImageDraw

root = Path(__file__).resolve().parents[1]
fixture = root / 'artifacts/fixtures'
source = Image.open(fixture / 'zoom-long-input.png').convert('RGB')
boxes = [(115, 190, 291, 265), (115, 2193, 291, 2268)]
results = []
for name, count in [('zoom-retina-export.png', 2), ('zoom-undo-export.png', 1)]:
    image = Image.open(fixture / name).convert('RGB')
    assert image.size == source.size == (800, 3200), 'export resized source'
    diff = ImageChops.difference(source, image)
    for left, top, right, bottom in boxes[:count]:
        # Antialiasing is allowed on the subpixel horizontal edge only.
        interior = image.crop((left+1, top+1, right-1, bottom-1))
        assert interior.getextrema() == ((0, 0), (0, 0), (0, 0)), 'cover is not opaque black'
    outside = diff.copy()
    draw = ImageDraw.Draw(outside)
    for left, top, right, bottom in boxes[:count]:
        draw.rectangle((left, top, right-1, bottom-1), fill=(0, 0, 0))
    assert outside.getbbox() is None, 'unexpected pixels changed outside expected source region'
    results.append({'file': name, 'covers': count, 'size': image.size, 'diff_bbox': diff.getbbox(), 'outside_exact': True})
paths = ['macos/Sources/Framelet/CanvasGeometry.swift', 'macos/Sources/Framelet/Views.swift',
         'macos/Sources/Framelet/Model.swift', 'macos/Sources/Framelet/SelfTest.swift',
         'build/Framelet.app/Contents/MacOS/Framelet', 'scripts/test-mac-zoom-export.py']
paths += ['artifacts/fixtures/'+n for n in ['zoom-long-input.png','zoom-retina-export.png','zoom-undo-export.png']]
paths += ['artifacts/visual/'+n for n in ['mac-zoom-actual.png','mac-zoom-scrolled.png','mac-zoom-width.png']]
evidence = {'status':'PASS_SCOPED', 'verified_at':datetime.now(timezone.utc).isoformat(),
            'scope':'Mac native import, Retina 100%/200%, scroll, opaque cover, zoom change and undo. Not screen capture or Windows.',
            'ui_sequence':'Imported 800x3200 synthetic image; verified Retina 100% screenshot; 200% top cover then 3-page scroll and lower cover; exported; undo lower cover, fit-width, exported again.',
            'pixel_results':results,
            'sha256':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}}
(root/'artifacts/mac-zoom-validation.json').write_text(json.dumps(evidence,indent=2)+'\n')
print(json.dumps({'status':'PASS_SCOPED', 'pixel_results':results}))
