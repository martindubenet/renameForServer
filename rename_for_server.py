#!/usr/bin/env python3
from __future__ import annotations

"""
rename_for_server.py

Renames the Finder-selected files (any type) in place so their names are
"server friendly", and optionally saves an .avif copy of the images.
Meant to be called from an Automator "Run Shell Script" Quick Action that
passes the selected files as command-line arguments.

Name rules (see clean_stem / clean_ext), in this order:
    1. Ligatures and special letters -> basic letters: oe, ae, ss, o, d, l, th.
    2. Accented Latin letters -> their basic letter (e -> e, C-cedilla -> C...).
    3. " - " (spaces + hyphen/en dash/em dash + spaces) -> "_".
    4. Apostrophes and quotes are removed ("l'ete" -> "lete").
    5. Spaces -> "-".
    6. Any other character that is not a-z, A-Z, 0-9, ".", "-" or "_"
       (& , ( ) ! ? # % + ...) -> "-".
    7. Runs of "-" or "_" collapse into one; a "-" touching a "_" is absorbed
       by the "_"; leading/trailing "-", "_" and "." are trimmed.
    8. Extension in lowercase, with common aliases unified (.jpeg -> .jpg, .tiff -> .tif).
    Letter case is otherwise kept.

    "Photo d'été (v2) - Final & co.JPEG" -> "Photo-dete-v2_Final-co.jpg"

Only when the selection contains images, the window offers to save an .avif
copy of each image next to it, under the cleaned name. With this option on, the
original images are NOT renamed (only the other files are).
The window is RenameForServer.app (built from RenameForServerApp/ with
build_app.sh); a plain dialog is used if the app is missing.
Originals are never deleted.

Requires on the Mac running this:
    - Python 3.9+ (renaming alone needs nothing else)
    - For the .avif option: Pillow 11.2+ (pip3 install -U Pillow), which encodes AVIF natively,
      plus pillow-heif to read HEIC/HEIF photos (pip3 install pillow-heif)
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
from pathlib import Path
from typing import Optional

# --- Tunables -------------------------------------------------------------
# Native window (RenameForServerApp/, built with build_app.sh). When the app is
# missing, fails, or AI_FORCE_DIALOG=1 is set, a plain dialog is used instead.
SCRIPT_DIR = Path(__file__).resolve().parent
APP_PATH = SCRIPT_DIR / "RenameForServer.app"
LAST_CHOICE_FILE = SCRIPT_DIR / ".last_choice.json"

AVIF_QUALITY = 80       # 0-100; 80 is visually lossless for photos at a fraction of the JPEG size
AVIF_SPEED = 6          # 0 (slowest, smallest) - 10 (fastest)
AVIF_SUBSAMPLING = "4:4:4"  # full-resolution color, like the watermark script's JPEGs
FALLBACK_STEM = "file"  # used when nothing is left of the name once cleaned up

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".tif", ".tiff", ".bmp", ".gif"}

# Extension aliases unified to one spelling
EXT_ALIASES = {".jpeg": ".jpg", ".jpe": ".jpg", ".tiff": ".tif", ".htm": ".html", ".yml": ".yaml"}

# Letters that Unicode decomposition doesn't reduce to a basic letter
SPECIAL_LETTERS = {
    "œ": "oe", "Œ": "OE", "æ": "ae", "Æ": "AE", "ß": "ss",
    "ø": "o", "Ø": "O", "đ": "d", "Đ": "D", "ð": "d", "Ð": "D",
    "ł": "l", "Ł": "L", "þ": "th", "Þ": "TH", "ı": "i",
}
QUOTES = "'’‘‛`´\"“”„«»‹›"

EXIF_ORIENTATION = 0x0112


def _as_literal(text: str) -> str:
    """Escape a Python string for safe interpolation into an AppleScript string literal."""
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run_dialog(body: str) -> tuple[Optional[str], bool]:
    """Run an AppleScript dialog owned by the frontmost app (Finder, for a Quick Action).

    A dialog shown by a background osascript process may not get the keyboard/mouse
    focus when launched from the Finder (lost clicks since macOS 27.2). Asking the
    frontmost app to show it avoids that. If macOS refuses the Apple Event (Automation
    permission denied), the dialog is shown by osascript itself as a fallback.

    Returns (stdout, cancelled).
    """
    wrapped = ("tell application (path to frontmost application as text)\n"
               "activate\n" + body + "\nend tell")
    for script in (wrapped, body):
        result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.strip(), False
        if "-128" in result.stderr:  # user clicked Cancel
            return None, True
        print(f"Dialog failed: {result.stderr.strip()}", file=sys.stderr)
    return None, True


def notify(message: str, title: str = "Rename File for Server") -> None:
    """Show a native macOS alert dialog (visible even though this runs headless from Automator)."""
    script = (f"display dialog {_as_literal(message)} with title {_as_literal(title)} "
              "buttons {\"OK\"} default button \"OK\"")
    run_dialog(script)

def announce(message: str, title: str) -> None:
    """Success summary as a macOS notification posted by this script's own app.

    (An AppleScript "display notification" would come from Script Editor, and
    clicking it would open Script Editor.) If the app can't post it (missing,
    or notifications refused), a dialog that closes itself after a few seconds
    is shown instead. Errors still get a regular dialog (notify).
    """
    data = run_app(["--notify-title", title, "--notify-body", message])
    if data is not None and data.get("posted"):
        return
    run_dialog(f"display dialog {_as_literal(message)} with title {_as_literal(title)} "
               "buttons {\"OK\"} default button \"OK\" giving up after 3")



def read_last_choice() -> dict:
    """Choices made last time in the window (per machine, git-ignored)."""
    try:
        data = json.loads(LAST_CHOICE_FILE.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_last_choice(data: dict) -> None:
    try:
        LAST_CHOICE_FILE.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass  # not critical: the defaults are used next time


def run_app(extra_args: list[str]) -> Optional[dict]:
    """Show the native window and return its JSON answer; None if it could not run.

    "open -W" launches it as a regular app (so it gets the focus) and waits until it quits.
    """
    if not APP_PATH.is_dir() or os.environ.get("AI_FORCE_DIALOG") == "1":
        return None
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "result.json"
        cmd = ["open", "-W", "-n", str(APP_PATH), "--args", *extra_args, "--out", str(out)]
        result = subprocess.run(cmd, capture_output=True, text=True)
        try:
            data = json.loads(out.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            print(f"{APP_PATH.name} gave no answer (exit {result.returncode}): "
                  f"{result.stderr.strip()}", file=sys.stderr)
            return None
    return data if isinstance(data, dict) else None


def ask(file_count: int, image_count: int) -> Optional[bool]:
    """False = rename only, True = rename + AVIF copies, None = cancelled.

    Native window when available, otherwise the plain dialog (ask_dialog).
    """
    last = read_last_choice()
    data = run_app(["--files", str(file_count), "--images", str(image_count),
                    "--avif", "1" if last.get("avif", False) else "0"])
    if data is None:
        return ask_dialog(file_count, image_count)
    if data.get("cancelled"):
        return None
    avif = bool(data.get("avif", False)) and image_count > 0
    if image_count:  # only remember the switch when it was shown
        save_last_choice({"avif": avif})
    return avif


def ask_dialog(file_count: int, image_count: int) -> Optional[bool]:
    """Fallback: one native dialog. Returns False = rename only, True = rename + AVIF copies, None = cancelled.

    The AVIF button only appears when the selection contains images.
    """
    message = f"Rename {file_count} file(s) with server-friendly names?"
    buttons = ["Cancel", "Rename"]
    default = "Rename"
    if image_count:
        message += f"\n\n{image_count} image(s) in the selection can also be saved as an .avif copy."
        buttons.append("Rename + AVIF copy")
    script = (
        f"button returned of (display dialog {_as_literal(message)} "
        f"with title \"Rename File for Server\" "
        "buttons {" + ", ".join(_as_literal(b) for b in buttons) + "} "
        f"default button {_as_literal(default)} cancel button \"Cancel\")"
    )
    answer, cancelled = run_dialog(script)
    if cancelled or answer is None:
        return None  # Cancel, or dialog failure
    return answer == "Rename + AVIF copy"


def clean_stem(stem: str) -> str:
    """Apply the name rules listed in the module docstring to a file name without extension."""
    s = unicodedata.normalize("NFC", stem)  # macOS may hand over decomposed accents
    s = "".join(SPECIAL_LETTERS.get(ch, ch) for ch in s)
    s = unicodedata.normalize("NFD", s)
    s = "".join(ch for ch in s if unicodedata.category(ch) != "Mn")  # drop the accents
    s = re.sub(r"\s+[-‐‑‒–—]+\s+", "_", s)   # " - " -> "_"
    s = "".join(ch for ch in s if ch not in QUOTES)
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"[^A-Za-z0-9._-]", "-", s)   # & and every other symbol -> "-"
    s = re.sub(r"\.{2,}", ".", s)
    s = re.sub(r"-{2,}", "-", s)
    s = re.sub(r"[-_]*_[-_]*", "_", s)       # "_", "-_", "_-", "__" -> "_"
    s = s.strip("-_.")
    return s or FALLBACK_STEM


def clean_ext(ext: str) -> str:
    """Lowercase the extension, unify common aliases, keep only safe characters."""
    e = ext.lower()
    e = EXT_ALIASES.get(e, e)
    return "." + re.sub(r"[^a-z0-9]", "", e[1:]) if len(e) > 1 else ""


def unique_target(src: Optional[Path], target: Path) -> Path:
    """Return target, or 'name-1.ext', 'name-2.ext'... if another file already uses it.

    src is the file being renamed: on the case-insensitive macOS disk, a name that
    only changes case points to the same file and is not a conflict.
    """
    candidate, index = target, 1
    while candidate.exists() and not (src is not None and os.path.samefile(candidate, src)):
        candidate = target.with_name(f"{target.stem}-{index}{target.suffix}")
        index += 1
    return candidate


def rename(path: Path) -> Path:
    """Rename one file in place; return its (possibly unchanged) new path."""
    new_name = clean_stem(path.stem) + clean_ext(path.suffix)
    if new_name == path.name:
        return path
    target = unique_target(path, path.with_name(new_name))
    path.rename(target)
    return target


def save_avif(path: Path) -> Path:
    """Save an .avif copy next to the image, under the cleaned name, keeping EXIF, ICC and XMP.

    The original image itself is left untouched (not renamed).
    """
    from PIL import Image, ImageOps, features
    try:
        import pillow_heif
        pillow_heif.register_heif_opener()
    except ImportError:
        pass
    if not features.check("avif"):
        raise RuntimeError("this Pillow can't write AVIF -- run: pip3 install -U Pillow")

    with Image.open(path) as source:
        # Rotate the pixels upright, then reset the EXIF Orientation to match.
        img = ImageOps.exif_transpose(source)
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGBA" if "A" in img.getbands() or "transparency" in source.info else "RGB")
        kwargs = dict(quality=AVIF_QUALITY, speed=AVIF_SPEED, subsampling=AVIF_SUBSAMPLING)
        exif = source.getexif()
        if exif:
            exif[EXIF_ORIENTATION] = 1
            kwargs["exif"] = exif.tobytes()
        if source.info.get("icc_profile"):
            kwargs["icc_profile"] = source.info["icc_profile"]
        if source.info.get("xmp"):
            kwargs["xmp"] = source.info["xmp"]
        out = unique_target(None, path.with_name(clean_stem(path.stem) + ".avif"))
        img.save(out, format="AVIF", **kwargs)
    return out


def main() -> int:
    # Any file type; folders and hidden files (".DS_Store"...) are left alone.
    paths = [Path(p) for p in sys.argv[1:]
             if Path(p).is_file() and not Path(p).name.startswith(".")]
    if not paths:
        notify("No file was received (folders and hidden files are ignored).")
        return 0

    image_count = sum(1 for p in paths if p.suffix.lower() in IMAGE_EXT)
    want_avif = ask(len(paths), image_count)
    if want_avif is None:
        return 0  # Cancel: exit quietly

    renamed, unchanged, avifs, errors = 0, 0, 0, []
    for path in paths:
        if want_avif and path.suffix.lower() in IMAGE_EXT:
            # AVIF on: the original image keeps its name; only the AVIF copy gets the clean one.
            try:
                save_avif(path)
                avifs += 1
            except Exception as exc:  # noqa: BLE001 -- listed in the summary dialog
                errors.append(f"{path.name} (AVIF): {exc}")
            continue
        try:
            new_path = rename(path)
            if new_path == path:
                unchanged += 1
            else:
                renamed += 1
        except Exception as exc:  # noqa: BLE001 -- listed in the summary dialog
            errors.append(f"{path.name}: {exc}")

    summary = f"{renamed} file(s) renamed, {unchanged} already clean."
    if want_avif:
        summary += f" {avifs} AVIF copy(ies) created, original image(s) left as is."
    if errors:
        notify(summary + "\n\nErrors:\n" + "\n".join(errors))
    else:
        announce(summary, "Rename File for Server")
    return 0


if __name__ == "__main__":
    sys.exit(main())
