## PULSE 1.6.2

Batch 23 from the 500-item roadmap (`docs/ROADMAP-500.md`), on top of [1.6.1](../1.6.1/NOTES.md):

### Delivery
- **Chapter art** (#493) — Timeline → Export Chapter Art… saves a 1280×720 picture per chapter marker: the
  frame at that moment with the chapter's name set over it, for the description and the end screen.

### Media
- **List view** (#18) — the media panel can show a table with Name, Length, Size, Imported and Role columns;
  click a column to sort, double-click a row to add it to the timeline.

### Everywhere
- **GPU self-test** (#392) — at launch PULSE renders one frame through the GPU; when that fails it switches to
  safe mode (CPU rendering) on its own and says so.
- **Shuttle speed** (#420) — the transport bar shows the J/K/L speed while you shuttle.

#### Already there, now on the list
- Chat bursts count toward every moment's score once a chat replay is attached (#26); the media grid and the
  timeline are virtualized (#386); when whisper.cpp isn't there, Apple's on-device speech takes over (#400);
  the viewer's strip shows the format, resolution and frame rate (#419).

### Under the hood
- `ChapterArt` (engine) draws with AppKit on the source frame, so a marker over a cutaway or gap is skipped.
