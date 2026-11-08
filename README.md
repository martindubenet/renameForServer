# Rename File for Server —  macOS Automator Quick Action <img width="48px" src="https://static.wikia.nocookie.net/ipod/images/a/ab/Automator.png/revision/latest?cb=20160908152407" alt="Otto the Automator" />

Renames the selected files (any type) **in place** with "server friendly" names, straight from the Finder. When the selection contains images, it can also save an **.avif** copy of each one.

<img width="100%" src="img_renameForServer.avif" alt="Screenshot">

> Part of `aiScripts/`. Steps shared by all the scripts (Python libraries, `~/aiScripts` symbolic link, Xcode Command Line Tools) are detailed in [`watermarkImg/README.md`](../watermarkImg/README.md#1-install-the-dependencies-once).

## How it works

- `rename_for_server.py` — the Python script called by the Quick Action. It renames the files and encodes the AVIF copies.
- `RenameForServer.app` — a small native macOS app (source in `RenameForServerApp/`, built on your Mac with `build_app.sh`) that only shows the window and posts the end-of-task notification.

If `RenameForServer.app` is missing or fails, the script automatically falls back to a plain native dialog (see [Fallback](#fallback)).

## 1. Requirements (once)

- Renaming alone needs only Python 3.
- The AVIF option needs **Pillow 11.2+** (native AVIF encoder) and **pillow-heif** (to read HEIC) for `/opt/homebrew/bin/python3`: `/opt/homebrew/bin/python3 -m pip install -U Pillow pillow-heif`. To check: `/opt/homebrew/bin/python3 -c "from PIL import features; print('AVIF:', features.check('avif'))"` must print `AVIF: True`.
- The `~/aiScripts` symbolic link (see the watermark README, step 2).
- Xcode Command Line Tools, to build the app (`xcode-select -p` to check).

## 2. Build the app (once, and after any change to `RenameForServerApp/`)

In your Terminal app:

```bash
~/aiScripts/renameForServer/build_app.sh
```

It ends with `Built: …/RenameForServer.app`.

## 3. Create the Quick Action in Automator

1. Open **Automator**, **File > New**, choose `Quick Action`.
2. At the top of the document, set:
   - **Workflow receives current** → `files or folders` (so it accepts every file type)
   - **in** → `Finder`
   - **Image** (*optional*) → an icon of your choice
3. Add the **Run Shell Script** action, with **Shell** → `/bin/zsh` and **Pass input** → `as arguments`.
4. Replace the content of the script box with:

   ```bash
   /opt/homebrew/bin/python3 "$HOME/aiScripts/renameForServer/rename_for_server.py" "$@"
   ```

5. **File > Save**, e.g. **Rename File for Server**.

## 4. Usage

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

If the window ever becomes unstable, delete or rename `RenameForServer.app` in the Finder: the script then shows a plain native dialog (**Cancel** / **Rename** / **Rename + AVIF copy**, the last button only when images are selected). To force it for a test, in your Terminal app:

```bash
AI_FORCE_DIALOG=1 /opt/homebrew/bin/python3 ~/aiScripts/renameForServer/rename_for_server.py ~/Desktop/a-file.txt
```

## Troubleshooting

- **The plain dialog shows up instead of the window** → `RenameForServer.app` is missing or failed: rebuild it. Running the script from the Terminal (command above, without `AI_FORCE_DIALOG=1`) prints the reason (`RenameForServer.app gave no answer…`).
- **"this Pillow can't write AVIF"** → update Pillow for the right Python (see Requirements).
- **No notification at the end** → the first time, macOS asks whether the app may send notifications: click **Allow**. Check **System Settings › Notifications** and Focus modes. If notifications are refused, a dialog that closes itself after 3 seconds is shown instead.
- **Permission alert "… wants access to control Finder"** → click **Allow** (dialogs are shown by the Finder so they get the focus).
- **Files inside a selected folder aren't renamed** → by design, folders are ignored: open the folder and select its files.
