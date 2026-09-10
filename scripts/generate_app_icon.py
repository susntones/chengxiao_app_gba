"""Generate the original, opaque 1024px iOS app icon. Requires Pillow."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 3
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "GBAEmulator/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def rect(draw, box, radius, fill):
    draw.rounded_rectangle(tuple(round(v * SCALE) for v in box), radius=radius * SCALE, fill=fill)


def ellipse(draw, box, fill):
    draw.ellipse(tuple(round(v * SCALE) for v in box), fill=fill)


def line(draw, points, fill, width):
    draw.line([(int(x * SCALE), int(y * SCALE)) for x, y in points], fill=fill, width=width * SCALE)


def main():
    background = Image.new("RGB", (SIZE, SIZE))
    pixels = background.load()
    for y in range(SIZE):
        for x in range(SIZE):
            glow = math.exp(-(((x - 480) / 620) ** 2 + ((y - 330) / 620) ** 2) * 2)
            pixels[x, y] = (int(13 + 23 * glow), int(19 + 24 * glow), int(38 + 42 * glow))
    image = background.resize((SIZE * SCALE, SIZE * SCALE))
    shadow = Image.new("RGBA", image.size)
    draw = ImageDraw.Draw(shadow)
    rect(draw, (117, 330, 907, 780), 152, (2, 4, 16, 180))
    image = Image.alpha_composite(image.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(27 * SCALE)))
    draw = ImageDraw.Draw(image)

    # Wide handheld silhouette with a dimensional lavender shell.
    rect(draw, (112, 287, 912, 756), 144, "#5140A0")
    rect(draw, (112, 268, 912, 733), 144, "#AD9CF6")
    rect(draw, (121, 279, 903, 724), 136, "#8E78DF")
    rect(draw, (135, 290, 889, 706), 124, "#927CE5")
    line(draw, [(253, 282), (772, 282)], "#C9BDFF", 5)

    # Deep screen bezel and mint LCD: original pixel-art horizon.
    rect(draw, (296, 317, 731, 650), 42, "#B4A1F7")
    rect(draw, (296, 309, 731, 638), 42, "#302D51")
    rect(draw, (316, 330, 711, 617), 27, "#151F32")
    rect(draw, (333, 347, 694, 599), 15, "#94EBC8")
    rect(draw, (343, 357, 684, 480), 8, "#A4F4D6")
    # Pixel sun and stepped mountain silhouettes, clipped within the LCD.
    rect(draw, (592, 379, 630, 417), 0, "#E8FFE5")
    mountains = [(333, 554), (365, 554), (365, 520), (397, 520), (397, 489), (429, 489), (429, 458), (461, 458), (461, 489), (493, 489), (493, 520), (525, 520), (525, 542), (557, 542), (557, 510), (589, 510), (589, 477), (621, 477), (621, 510), (653, 510), (653, 542), (694, 542), (694, 580), (333, 580)]
    draw.polygon([(x * SCALE, y * SCALE) for x, y in mountains], fill="#45B89C")
    rect(draw, (333, 569, 694, 590), 0, "#237D76")
    rect(draw, (344, 582, 684, 599), 0, "#237D76")
    # Small bright pixel player.
    rect(draw, (467, 515, 487, 535), 0, "#F5FFE7")
    rect(draw, (457, 535, 497, 555), 0, "#F5FFE7")
    rect(draw, (457, 555, 471, 569), 0, "#F5FFE7")
    rect(draw, (483, 555, 497, 569), 0, "#F5FFE7")

    # Tactile D-pad.
    ellipse(draw, (145, 423, 289, 567), "#806ACA")
    rect(draw, (191, 430, 240, 574), 11, "#65519F")
    rect(draw, (146, 477, 285, 526), 11, "#65519F")
    rect(draw, (191, 420, 240, 559), 10, "#282B49")
    rect(draw, (146, 465, 285, 514), 10, "#282B49")
    line(draw, [(201, 428), (229, 428)], "#515573", 4)
    ellipse(draw, (201, 475, 230, 504), "#20253E")

    # Offset action buttons, no branding or lettering.
    for x, y in [(787, 516), (846, 452)]:
        ellipse(draw, (x - 33, y - 27, x + 33, y + 39), "#6950B0")
        ellipse(draw, (x - 30, y - 30, x + 30, y + 30), "#E7ABDD")
        ellipse(draw, (x - 25, y - 27, x + 25, y + 19), "#F4C4E7")
    ellipse(draw, (771, 352, 783, 364), "#B7FFD4")
    for x in (459, 528):
        rect(draw, (x, 668, x + 45, 682), 7, "#62529C")
        line(draw, [(x + 8, 670), (x + 36, 670)], "#7864B8", 2)
    for x in (758, 777, 796):
        rect(draw, (x, 618, x + 7, 656), 3, "#6755AA")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.convert("RGB").resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(OUTPUT, optimize=True)
    print(OUTPUT)


if __name__ == "__main__":
    main()
