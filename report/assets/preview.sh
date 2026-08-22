#!/usr/bin/env bash
# Check a generated .docx and render every page to PNG so the layout can be looked at.
#   preview.sh <file.docx> [outdir]
# One call replaces: structure check + soffice resolution + docx->pdf + pdf->png.
set -uo pipefail
DOCX="${1:?usage: preview.sh <file.docx> [outdir]}"
[ -f "$DOCX" ] || { echo "error: no such file: $DOCX" >&2; exit 2; }
OUTDIR="${2:-$(dirname "$DOCX")/preview}"
BASE="$(basename "${DOCX%.docx}")"

# Structure check. (This is a zip/XML well-formedness check, not full OOXML schema validation:
# the docx skill's validate.py is a plugin file and is not present on disk here.)
python3 - "$DOCX" <<'PY' || exit 2
import sys, zipfile, xml.etree.ElementTree as ET
p = sys.argv[1]
try:
    z = zipfile.ZipFile(p)
except zipfile.BadZipFile as e:
    print(f"error: not a valid .docx (bad zip): {e}", file=sys.stderr); sys.exit(1)
if z.testzip() is not None:
    print(f"error: corrupt entry in {p}", file=sys.stderr); sys.exit(1)
names = z.namelist()
for req in ("[Content_Types].xml", "word/document.xml"):
    if req not in names:
        print(f"error: missing {req}", file=sys.stderr); sys.exit(1)
bad = []
for n in names:
    if n.endswith((".xml", ".rels")):
        try:
            ET.fromstring(z.read(n))
        except ET.ParseError as e:
            bad.append(f"{n}: {e}")
if bad:
    print("error: malformed XML part(s):\n  " + "\n  ".join(bad), file=sys.stderr); sys.exit(1)
media = [n for n in names if n.startswith("word/media/")]
print(f"structure ok: {len(names)} parts, {len(media)} embedded image(s)")
PY

SOFFICE="$(command -v soffice || command -v libreoffice || true)"
[ -z "$SOFFICE" ] && [ -x "/Applications/LibreOffice.app/Contents/MacOS/soffice" ] && SOFFICE="/Applications/LibreOffice.app/Contents/MacOS/soffice"
[ -n "$SOFFICE" ] || { echo "error: LibreOffice not found. brew install --cask libreoffice (mac) | sudo apt-get install -y libreoffice (linux)" >&2; exit 2; }
command -v pdftoppm >/dev/null || { echo "error: pdftoppm not found. brew install poppler (mac) | sudo apt-get install -y poppler-utils (linux)" >&2; exit 2; }

mkdir -p "$OUTDIR"; rm -f "$OUTDIR/$BASE"-page-*.png "$OUTDIR/$BASE.pdf"
"$SOFFICE" --headless -env:UserInstallation=file:///tmp/loprofile_report_preview \
  --convert-to pdf --outdir "$OUTDIR" "$DOCX" >/dev/null 2>&1
[ -f "$OUTDIR/$BASE.pdf" ] || { echo "error: LibreOffice could not convert the .docx" >&2; exit 2; }
pdftoppm -png -r 120 "$OUTDIR/$BASE.pdf" "$OUTDIR/$BASE-page"

echo "pages:"
ls "$OUTDIR/$BASE"-page-*.png 2>/dev/null || { echo "error: no pages rendered" >&2; exit 2; }
