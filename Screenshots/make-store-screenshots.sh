#!/bin/bash
#
# Builds App Store screenshots from the raw simulator captures.
#
#   ./make-store-screenshots.sh
#
# Sources: Screenshots/0*.png (1320x2868, 6.9" iPhone)
# Outputs: Screenshots/store/  — 1320x2868 App Store uploads
#          Screenshots/web/    — 420px wide versions for cttech.io
#
# Captions come from the "App Store Product Page Copy" note. Edit CAPTIONS
# below to A/B test wording; nothing else needs to change.
#
# Deliberately no price figures in any image — a price change would otherwise
# mean regenerating and re-uploading the whole set.

set -euo pipefail

cd "$(dirname "$0")"
SRC="."
OUT="store"        # 6.9" — the primary App Store Connect slot
OUT65="store-6.5"  # 6.5" — a separate slot, with its own accepted sizes
WEB="web"
mkdir -p "$OUT" "$OUT65" "$WEB"

# Canvas — 6.9" iPhone (iPhone 16/17 Pro Max)
W=1320
H=2868

# 6.5" slot accepts 1242x2688 or 1284x2778; the taller one wastes less.
W65=1284
H65=2778

# Brand palette, sampled from the app icon and the app's own UI
NAVY_TOP="#0F1B3D"
NAVY_BOT="#070C1E"
GREEN="#30D158"
WHITE="#FFFFFF"
MUTED="#8E99B4"

FONT="/System/Library/Fonts/SFNS.ttf"
# SFNS is a variable font and ImageMagick renders its default (regular)
# instance, so a matched stroke fakes the semibold weight the layout wants.
STROKE=2.4

# Device plate geometry
DEV_W=980
DEV_R=52          # corner radius
DEV_TOP=700       # y of the device top edge
CAP_SIZE=92       # caption point size
CAP_TOP=210       # y of the first caption line

# Each entry: source|caption (\n forces the line break, so wrapping never
# lands somewhere ugly)
CAPTIONS=(
  "01-spirit-level.png|Hang shelves & frames\nperfectly level"
  "02-wall-scanner.png|Scan for studs, metal & wiring\nbefore you drill"
  "03-torch.png|A bright, steady\ninspection torch"
  "04-noise-meter.png|Check how loud\nit really is"
  "05-ruler.png|A handy on-screen ruler\nfor quick measurements"
)

# Per-screenshot vertical crop of the SOURCE, as "height:yoffset", applied
# before scaling. The app's screens have generous dead space that reads as
# empty at thumbnail size; this pulls the content up to fill the plate.
# (A function rather than an associative array — macOS still ships bash 3.2.)
crop_for() {
  case "$1" in
    # Run to the bottom edge so the tab bar stays whole — it doubles as
    # proof that all five tools are in there. Start below the gear icon.
    01-spirit-level.png) echo "2548:320" ;;
    *)                   echo "2548:320" ;;
  esac
}

background() {
  magick -size "${W}x${H}" \
    gradient:"${NAVY_TOP}-${NAVY_BOT}" \
    "$1"
}

# Rounds the corners of an image and adds a soft shadow.
plate() {
  local in="$1" out="$2"
  local w h
  w=$(magick identify -format "%w" "$in")
  h=$(magick identify -format "%h" "$in")

  magick "$in" \
    \( -size "${w}x${h}" xc:black \
       -draw "fill white roundrectangle 0,0 $((w - 1)),$((h - 1)) ${DEV_R},${DEV_R}" \) \
    -alpha off -compose CopyOpacity -composite \
    PNG32:"$out"
}

caption_onto() {
  local canvas="$1" text="$2"
  magick "$canvas" \
    -font "$FONT" -pointsize "$CAP_SIZE" \
    -fill "$WHITE" -stroke "$WHITE" -strokewidth "$STROKE" \
    -interline-spacing 18 \
    -gravity north -annotate "+0+${CAP_TOP}" "$text" \
    "$canvas"
}

echo "Building tool screenshots..."
i=0
for entry in "${CAPTIONS[@]}"; do
  i=$((i + 1))
  src="${entry%%|*}"
  cap="${entry#*|}"
  n=$(printf "%02d" "$i")
  work="/tmp/diy-shot-$$.png"

  # crop -> scale -> round + shadow -> composite under the caption.
  # The offset must be spelled +0+Y: "1320x2300+380" would be read as an
  # x-offset and slice the screen sideways.
  spec=$(crop_for "$src")
  magick "${SRC}/${src}" \
    -crop "${W}x${spec%%:*}+0+${spec##*:}" +repage \
    -resize "${DEV_W}x" "$work"
  plate "$work" "$work"

  background "${OUT}/${n}.png"
  magick "${OUT}/${n}.png" \
    \( "$work" \( +clone -background black -shadow 55x28+0+14 \) \
       +swap -background none -layers merge +repage \) \
    -gravity north -geometry "+0+$((DEV_TOP - 28))" -composite \
    "${OUT}/${n}.png"
  caption_onto "${OUT}/${n}.png" "$cap"

  rm -f "$work"
  echo "  ${n}.png  ${cap%%\\n*}..."
done

# ---------------------------------------------------------------------------
# 06 — the trust shot. No source screenshot: the app icon plus the three
# promises that justify a paid app.
# ---------------------------------------------------------------------------
echo "Building value shots..."
ICON="../DIYCompanion/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
ICON_W=460

# App Store icons ship square and fully opaque — the corners are white, and
# iOS rounds them at runtime. So mask them here, at iOS's own corner radius
# (~22.4% of the width) rather than the much tighter device-plate radius.
ICON_R=$((ICON_W * 224 / 1000))
magick "$ICON" -resize "${ICON_W}x" \
  \( -size "${ICON_W}x${ICON_W}" xc:black \
     -draw "fill white roundrectangle 0,0 $((ICON_W - 1)),$((ICON_W - 1)) ${ICON_R},${ICON_R}" \) \
  -alpha off -compose CopyOpacity -composite \
  PNG32:/tmp/diy-icon-$$.png

background "${OUT}/06.png"
# Composited flat: a -shadow layer bleeds a pale rim around the icon's
# soft alpha edge, which is very visible against the dark background.
magick "${OUT}/06.png" /tmp/diy-icon-$$.png \
  -gravity north -geometry "+0+500" -composite \
  "${OUT}/06.png"

magick "${OUT}/06.png" \
  -font "$FONT" -pointsize "$CAP_SIZE" -fill "$WHITE" \
  -stroke "$WHITE" -strokewidth "$STROKE" -interline-spacing 18 \
  -gravity north -annotate "+0+${CAP_TOP}" "No ads. No tracking.\nNo subscriptions." \
  "${OUT}/06.png"

# Points that don't simply restate the headline.
y=1240
for line in "Buy once, own it forever" "No account to create" "Works completely offline" "Nothing leaves your phone" "Every tool included" "Made by an indie developer"; do
  magick "${OUT}/06.png" \
    -font "$FONT" -pointsize 62 -stroke none \
    -fill "$GREEN" -gravity northwest -annotate "+230+${y}" "✓" \
    -fill "$WHITE" -gravity northwest -annotate "+350+${y}" "$line" \
    "${OUT}/06.png"
  y=$((y + 196))
done
echo "  06.png  No ads. No tracking. No subscriptions."

# ---------------------------------------------------------------------------
# 07 — the value shot: all five tools together, so "5 tools, one price" is
# something you can see rather than just read.
# ---------------------------------------------------------------------------
THUMB_W=360
THUMB_R=26
row1=""
row2=""
n=0
for f in 01-spirit-level.png 02-wall-scanner.png 03-torch.png 04-noise-meter.png 05-ruler.png; do
  n=$((n + 1))
  t="/tmp/diy-thumb-$$-$n.png"
  spec=$(crop_for "$f")
  magick "${SRC}/${f}" \
    -crop "${W}x${spec%%:*}+0+${spec##*:}" +repage \
    -resize "${THUMB_W}x" "$t"
  tw=$(magick identify -format "%w" "$t")
  th=$(magick identify -format "%h" "$t")
  magick "$t" \
    \( -size "${tw}x${th}" xc:black \
       -draw "fill white roundrectangle 0,0 $((tw - 1)),$((th - 1)) ${THUMB_R},${THUMB_R}" \) \
    -alpha off -compose CopyOpacity -composite PNG32:"$t"
  if [ "$n" -le 3 ]; then row1="$row1 $t"; else row2="$row2 $t"; fi
done

# -background none must precede +smush, or the gutters come out white.
# shellcheck disable=SC2086
magick -background none $row1 +smush 40 PNG32:/tmp/diy-row1-$$.png
# shellcheck disable=SC2086
magick -background none $row2 +smush 40 PNG32:/tmp/diy-row2-$$.png

background "${OUT}/07.png"
magick "${OUT}/07.png" \
  \( /tmp/diy-row1-$$.png \) -gravity north -geometry "+0+680" -composite \
  \( /tmp/diy-row2-$$.png \) -gravity north -geometry "+0+1460" -composite \
  -font "$FONT" -pointsize "$CAP_SIZE" -fill "$WHITE" \
  -stroke "$WHITE" -strokewidth "$STROKE" -interline-spacing 18 \
  -gravity north -annotate "+0+${CAP_TOP}" "Five essential tools.\nOne app. One price." \
  -font "$FONT" -pointsize 54 -stroke none -fill "$MUTED" \
  -gravity north -annotate "+0+2330" "Level · Scanner · Torch · Noise Meter · Ruler" \
  "${OUT}/07.png"
echo "  07.png  Five essential tools."

rm -f /tmp/diy-icon-$$.png /tmp/diy-thumb-$$-*.png /tmp/diy-row1-$$.png /tmp/diy-row2-$$.png

# ---------------------------------------------------------------------------
# 6.5" set — App Store Connect has a separate upload slot for it, which accepts
# 1242x2688 or 1284x2778 and rejects the 6.9" size with a "dimensions are wrong"
# error. Derived from the finished 6.9" images rather than re-composited, so the
# two sets stay identical in layout and captions.
#
# The aspect ratios differ very slightly (0.4603 vs 0.4622), so resize to cover
# and centre-crop instead of forcing the size — squashing type by 0.4% is
# subtle but it does show on the caption.
# ---------------------------------------------------------------------------
echo "Building 6.5\" set..."
mkdir -p "$OUT65"
for f in "${OUT}"/*.png; do
  magick "$f" -resize "${W65}x${H65}^" -gravity center -extent "${W65}x${H65}" \
    "${OUT65}/$(basename "$f")"
done

# ---------------------------------------------------------------------------
# Web versions for cttech.io
# ---------------------------------------------------------------------------
echo "Building web versions..."
# WebP, not PNG: these are ~17x smaller for identical-looking output, and a
# page carrying seven of them would otherwise be a 1.6 MB download.
for f in "${OUT}"/*.png; do
  magick "$f" -resize 420x -strip -quality 82 \
    "${WEB}/$(basename "$f" .png).webp"
done

echo
echo "Done. $(ls -1 "$OUT" | wc -l | tr -d ' ') store images in ${OUT}/, web copies in ${WEB}/"
magick identify -format "  %f  %wx%h\n" "${OUT}"/*.png
