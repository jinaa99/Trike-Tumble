import sys, os
import numpy as np
from PIL import Image, ImageFilter
raw, dst = sys.argv[1], sys.argv[2]
# id -> (folder, name, chroma kept, contrast, blur radius)
SETS = {
 "dirt": ("terrain", "dirt", 0.35, 0.8, 0.6),
 "leafy_grass": ("terrain", "grass", 0.3, 0.7, 0.8),
 "brown_mud_02": ("terrain", "mud", 0.3, 0.45, 0.5),
 "rock_face": ("stone", "rock_face", 0.25, 0.9, 0.5),
 "sandstone_cracks": ("stone", "sandstone", 0.3, 0.9, 0.5),
 "rock_boulder_dry": ("stone", "boulder", 0.25, 0.85, 0.5),
 "snow_02": ("snow", "snow_packed", 0.5, 1.0, 0.4),
 "weathered_planks": ("wood", "planks", 0.35, 0.85, 0.4),
 "bark_brown_02": ("wood", "bark", 0.35, 0.85, 0.5),
}
thumbs = []
for sid, (folder, name, chroma, contrast, blur) in SETS.items():
    d = os.path.join(dst, folder); os.makedirs(d, exist_ok=True)
    img = Image.open(os.path.join(raw, sid + "_diff.jpg")).convert("RGB")
    if blur > 0: img = img.filter(ImageFilter.GaussianBlur(blur))
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = a.mean(axis=2, keepdims=True)
    a = lum + (a - lum) * chroma                     # mostly neutral: vertex colour supplies the hue
    mean = a.mean(axis=(0, 1), keepdims=True)
    a = (a - mean) * contrast + mean
    a = a / a.mean() * 0.80                          # mean brightness 0.8 so the paint keeps its value
    a = np.clip(a, 0, 1)
    out = Image.fromarray((a * 255).astype(np.uint8))
    out.save(os.path.join(d, name + "_albedo.jpg"), quality=90)
    Image.open(os.path.join(raw, sid + "_nor.jpg")).convert("RGB").save(os.path.join(d, name + "_normal.jpg"), quality=92)
    Image.open(os.path.join(raw, sid + "_rough.jpg")).convert("L").save(os.path.join(d, name + "_rough.jpg"), quality=88)
    thumbs.append((name, out.resize((256, 256)), Image.open(os.path.join(raw, sid + "_diff.jpg")).resize((256, 256))))
sheet = Image.new("RGB", (256 * 6, 256 * 4))
thumbs = thumbs[:12]
for k, (name, proc, orig) in enumerate(thumbs):
    x, y = (k % 6) * 256, (k // 6) * 512
    sheet.paste(orig, (x, y)); sheet.paste(proc, (x, y + 256))
sheet.save("tex_sheet.jpg", quality=85)
