# The viewer's frames in CI

CI walks through the app and takes a screenshot of every page. Those screenshots are made by asking each
view to draw itself, and the viewer's picture is not drawn by a view: the player draws it. So in every
capture the viewer used to be a black box, and a release could go out with a viewer that rendered nothing
without any screenshot showing it.

Since 1.8.0 the walk-through also renders the viewer's frame itself, with the same composition and
compositor the viewer and the export use, and does three things with it:

1. **Judges it.** A frame that is black, one flat colour, or not the shape of the edit fails the run.
2. **Compares it** with the frame kept in [`.github/viewer-frames.json`](../.github/viewer-frames.json).
   Each frame is reduced to a 16 × 16 grid of mean colours. The same commit rendered on CI ten times gave
   identical grids, so any difference is a real one:
   - up to 0.004 over the frame and 0.06 in any one cell: the same picture;
   - more than that: **changed**. The run passes with a warning on its summary page. A caption that
     vanished or a colour that shifted lands here;
   - more than 0.05 over the frame: **not the same picture**. The run fails. A missing facecam, a moved
     layout, swapped colour channels or a black frame land here.
3. **Shows it.** The frame is drawn into the window's screenshot where the player shows it, so the
   captures look like the app does. Guides, handles and labels the views draw over the picture are kept.

The log lines are `UI-FRAME` (fine), `UI-FRAME-CHANGED`, `UI-FRAME-FAIL`, `UI-FRAME-SHOWN` (drawn into a
screenshot) and `UI-FRAMES` (the count).

## When the picture changes on purpose

A change to how shorts are built, to the caption look or to the sample project changes these frames, and
that is not a regression. To accept the new picture:

1. Look at the frame in the run's screenshots and make sure it is what you meant.
2. Find the `UI-FRAME-REFERENCE` line in the "UI snapshots" step of the macos-26 job (or the
   `viewer-frames.json` file in the run's `ci-output-macos-26` artifact).
3. Copy the entries for the frames that changed into `.github/viewer-frames.json` and commit it.

Only frames listed in that file are compared; the rest are still judged for being a picture of the right
shape. The long edit made by Edit My VOD is left out on purpose: tuning the auto-editor moves its opening
frame, and that would fail runs that have nothing wrong with them.

## What this does not cover

- One frame per capture, at one moment. A fault that only shows during playback, or later in the edit, is
  not seen.
- The Intel runner has no GPU and stops before the editor, so frames are judged on Apple silicon only.
- The grid is coarse. A change smaller than about a sixteenth of the frame's width that also keeps its
  average colour (a font weight, a one-pixel offset) passes as the same picture.
