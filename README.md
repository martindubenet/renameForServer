# Rename File for Server —  macOS Automator Quick Action <img width="48px" src="https://static.wikia.nocookie.net/ipod/images/a/ab/Automator.png/revision/latest?cb=20160908152407" alt="Otto the Automator" />

Renames the selected files (any type) **in place** with "server friendly" names, straight from the Finder. When the selection contains images, it can also save an **.avif** copy of each one.

<img width="100%" src="img_renameForServer.avif" alt="Screenshot">

> Related scripts: [`watermarkImg`](https://github.com/martindubenet/watermarkImg) and [`addDateImg`](https://github.com/martindubenet/addDateImg).
>
> Generic macOS setup (Python libraries for Automator, Xcode Command Line Tools, creating a Quick Action, permissions, notifications): see my [wiki › macOS Automator](https://github.com/martindubenet/wed-dev-design/wiki/app-%E2%80%A2-macOS-Automator).

## How it works

- `rename_for_server.py` — the Python script called by the Quick Action. It renames the files and encodes the AVIF copies.
- `RenameForServer.app` — a small native macOS app (source in `RenameForServerApp/`, built locally with `build_app.sh`) that only shows the window and posts the end-of-task notification.

If `RenameForServer.app` is missing or fails, the script automatically falls back to a plain native dialog (see [Fallback](#fallback)).

## Requirements

- Renaming alone needs only Python 3.
- The AVIF option needs **Pillow 11.2+** (native AVIF encoder) and **pillow-heif** (to read HEIC), installed for the `python3` used by the Quick Action. Check: `python3 -c "from PIL import features; print('AVIF:', features.check('avif'))"` must print `AVIF: True`.
- Xcode Command Line Tools, to build the app.

## Setup

1. **Build the app** (once, and after any change to `RenameForServerApp/`), from this folder: `./build_app.sh` — it ends with `Built: …/RenameForServer.app` (git-ignored).
2. **Create the Quick Action** in Automator with:
   - **Workflow receives current** → `files or folders` in `Finder` (so it accepts every file type)
   - **Run Shell Script** action, **Shell** → `/bin/zsh`, **Pass input** → `as arguments`, script (adjust the path to this folder):

     ```bash
     /opt/homebrew/bin/python3 "$HOME/aiScripts/renameForServer/rename_for_server.py" "$@"
     ```

   - Saved as e.g. **Rename File for Server**.

## Usage

> ⚠ The selected files are renamed directly. Try it on copies first.

1. In the Finder, select one or more files. Folders and hidden files (`.DS_Store`…) are ignored.
2. Right-click → **Quick Actions** → **Rename File for Server**.
3. In the window:
   - **Change file name nomenclature** shows how many files are selected.
   - **Duplicate selected image(s) as .AVIF file format** (switch, only shown when the selection contains images; its last state is remembered):
     - **Off:** every file is renamed.
     - **On:** the original images are **not** renamed; each one gets an `.avif` copy next to it, under the cleaned name. The other files (PDF, text…) are renamed normally.
   - With the switch on, counts appear below: **Renamed existing files** (the files that are not images), **New AVIF image files added**, **Total**.
   - **Execute** (or **Return**) runs it; **Cancel** (or **Esc**, or the red button) stops without any message. With keyboard navigation on, **Tab** goes Execute → AVIF switch → Cancel.
4. A **notification** confirms the result (e.g. "3 file(s) renamed, 1 already clean."). If some files failed, a dialog lists the errors instead.

Example with the AVIF switch on, selection `Photo d'été.JPG` + `Notes réunion.TXT`:

- `Photo d'été.JPG` → unchanged
- `Photo-dete.avif` → new copy
- `Notes réunion.TXT` → `Notes-reunion.txt`

### Name rules

Applied in this order (the letter case is otherwise kept):

1. Ligatures and special letters → basic letters: `œ`→`oe`, `æ`→`ae`, `ß`→`ss`, `ø`→`o`, `đ`→`d`, `ł`→`l`, `þ`→`th`.
2. Accented Latin letters → their basic letter: `é`→`e`, `Ç`→`C`…
3. ` - ` (spaces + hyphen, en dash or em dash + spaces) → `_`.
4. Apostrophes and quotes are removed: `l'été` → `lete`.
5. Spaces → `-`.
6. Any other character that is not `a-z`, `A-Z`, `0-9`, `.`, `-` or `_` (`&`, `,`, `(`, `)`, `!`, `?`, `#`, `%`, `+`…) → `-`.
7. Runs of `-` or `_` collapse into one; a `-` touching a `_` is absorbed by the `_`; leading/trailing `-`, `_` and `.` are trimmed.
8. Extension in lowercase, with common aliases unified: `.jpeg`→`.jpg`, `.tiff`→`.tif`, `.htm`→`.html`, `.yml`→`.yaml`.

| Before | After |
| --- | --- |
| `Photo d'été (v2) - Final & co.JPEG` | `Photo-dete-v2_Final-co.jpg` |
| `Œuvre  Ça_-_marche!!.TIFF` | `OEuvre-Ca_marche.tif` |
| `l’hiver – 2026 “best”.png` | `lhiver_2026-best.png` |
| `Rapport final.PDF` | `Rapport-final.pdf` |

- If nothing is left of the name once cleaned up, `file` is used.
- If the new name is already taken, `-1`, `-2`… is added (instead of macOS' ` (1)`, which isn't server friendly). A change of letter case only is not a conflict.

### AVIF copies

- Image formats: jpg, jpeg, png, webp, heic, heif, tif, tiff, bmp, gif.
- Quality 80 (`AVIF_QUALITY`, visually lossless for photos at a fraction of the JPEG size), speed 6 (`AVIF_SPEED`), full-resolution 4:4:4 colors (`AVIF_SUBSAMPLING`).
- EXIF, ICC color profile and XMP are kept; a portrait photo is rotated upright (EXIF orientation reset).
- Transparency is kept.

## Fallback

If the window ever becomes unstable, delete or rename `RenameForServer.app`: the script then shows a plain native dialog (**Cancel** / **Rename** / **Rename + AVIF copy**, the last button only when images are selected). To force it for a test, from this folder:

```bash
AI_FORCE_DIALOG=1 /opt/homebrew/bin/python3 rename_for_server.py ~/Desktop/a-file.txt
```

## Troubleshooting

- **The plain dialog shows up instead of the window** → `RenameForServer.app` is missing or failed: rebuild it. Running the script from the Terminal (command above, without `AI_FORCE_DIALOG=1`) prints the reason (`RenameForServer.app gave no answer…`).
- **"this Pillow can't write AVIF"** → update Pillow for the right Python (see Requirements).
- **No notification at the end** → allow notifications for **Rename file for server** (the app name) the first time macOS asks. If macOS refuses them, a dialog that closes itself after 3 seconds is shown instead.
- **Files inside a selected folder aren't renamed** → by design, folders are ignored: open the folder and select its files.
