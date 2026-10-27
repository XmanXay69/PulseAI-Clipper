# PULSE plugins

Roadmap #495. A plugin is a folder inside **~/Library/Application Support/PULSE/Plugins** holding a
`plugin.json`. Settings → Plugins lists what's there, says why one doesn't load, and can write two examples
to copy. Plugins never run code inside PULSE: effects are declared, signals run as separate processes.

## Effect plugins

```json
{
  "id": "example.warm-glow",
  "name": "Warm Glow",
  "version": "1.0",
  "kind": "effect",
  "author": "PULSE",
  "description": "A soft bloom with a warm tint.",
  "symbol": "sun.haze",
  "parameters": [
    { "key": "glow", "name": "Glow", "min": 0, "max": 1, "default": 0.4 },
    { "key": "warmth", "name": "Warmth", "min": 5500, "max": 8500, "default": 7000 }
  ],
  "filters": [
    { "filter": "CIBloom", "inputs": { "inputRadius": "14", "inputIntensity": "$glow" } },
    { "filter": "CITemperatureAndTint", "inputs": { "inputTargetNeutral": "$warmth" } }
  ]
}
```

- `filters` run in order on the clip's picture. Only filters on the allowed list load (colour, blur,
  stylize and distortion filters — see `PluginLoader.allowedFilters`); nothing that reads files or the network.
- An input is a number as text, or `$key` to read a slider declared in `parameters`. Sliders show in the
  Inspector's Effects section with the name and range you declare, and animate like any effect parameter.
- The effect appears in the Effects menu (Inspector and Editor tab) under the built-ins. A clip keeps the
  plugin's id and name, so a project opened on a Mac without the plugin still lists it ("plugin missing")
  and renders without it.

## Signal plugins

```json
{
  "id": "example.every-five-minutes",
  "name": "Every Five Minutes",
  "version": "1.0",
  "kind": "signal",
  "command": ["run.sh"]
}
```

- `command` is the executable and its arguments; a relative path runs from the plugin's folder (make it
  executable: `chmod +x run.sh`).
- Standard input is one JSON object:
  `{"mediaPath": "...", "assetName": "...", "duration": 5400.0, "transcript": [{"text": "...", "start": 1.2, "end": 1.6}, ...]}`
  (the transcript is empty until the recording is analyzed).
- Standard output is a JSON list of events — `[{"time": 312.4, "kind": "kill", "text": "Headshot"}]` — with
  `kind` one of `kill, multiKill, death, objective, win, loss, clutch, achievement, levelUp` (a CSV of
  `time,kind,text` lines or Riot's event JSON work too). Times are seconds into the recording.
- Run it from a recording's menu on the Import page (Run Signal Plugin ▸ name). The events merge with what
  the screen reader saw and score like banners; a plugin has two minutes, and a non-zero exit shows its stderr.

## Ideas
A signal plugin can call a game's API (Riot, Steam, OBS logs), read a stream deck's marker log, or run your
own model; an effect plugin can package a look you keep reusing.
