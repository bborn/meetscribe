# meetscribe

**One-press, 100% local meeting transcription for macOS.** Click 🔴, talk, click again — you get a clean transcript and a mixed audio file. No cloud, no bot joining your call, no bundled multi-gigabyte language model.

It captures system audio via Apple's **ScreenCaptureKit**, so it works with any meeting app (Google Meet, Slack huddles, Zoom, Teams, Discord, FaceTime, even a YouTube video) — and *with* your mic, too, so both sides of the conversation end up in the transcript.

The transcription engine is **pluggable**: bring your own whisper (whisper.cpp, OpenAI whisper, more by contribution). The transcript-cleanup + auto-naming step uses a **pluggable LLM** (Claude CLI, Ollama, etc.) and is optional — skip it and the tool still works.

## What you get

```
~/Desktop/meet-recordings/05-29-26-acme-demo/
├── transcript.txt   # clean, de-duped, speaker-labelled
└── audio.m4a        # mixed system + mic audio
```

## Why this exists

Most "AI meeting recorder" apps for Mac fall into two camps:

1. **Heavy notes suites** (Meetily, Hyprnote, …) that bundle a 2–3 GB local LLM to write summaries you can do in any LLM yourself.
2. **File-based whisper UIs** (WhisperDesk, Buzz, …) that don't capture live system audio — you'd need a separate recorder.

And the older DIY route — loopback drivers like BlackHole/Soundflower plus a virtual output device — is unreliable: it depends on every app routing its audio through your re-routed output, and quietly fails on apps like Slack huddles that pick a specific device.

ScreenCaptureKit (macOS 13+, with microphone capture added in macOS 14) solves this cleanly: a reliable, app-agnostic, per-process tap on system audio + the mic, in one synced capture. meetscribe wraps that in a 200-line Objective-C tool, hands the WAVs to whichever whisper you have, and gets out of your way.

## Requirements

- **macOS 14.0+** (Sonoma or later; ScreenCaptureKit microphone capture)
- **Command Line Tools for Xcode** — just for `clang` (`xcode-select --install`)
- **ffmpeg** — `brew install ffmpeg`
- **One whisper backend** — pick one:
  - **whisper.cpp** (recommended): `brew install whisper-cpp` + grab a model:
    ```bash
    mkdir -p ~/.local/share/meetscribe/models
    curl -L -o ~/.local/share/meetscribe/models/ggml-base.en.bin \
      https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
    ```
  - **OpenAI whisper**: `pip install -U openai-whisper`
- **Optional: an LLM** for transcript de-duplication and auto-naming. Any of:
  - [`claude`](https://docs.claude.com/en/docs/claude-code/overview) (Claude Code's headless mode)
  - [`ollama`](https://ollama.com) with a model you've pulled (e.g. `ollama pull llama3.1:8b`)
  - [`llm`](https://llm.datasette.io/) (Simon Willison's CLI; OpenAI, Anthropic, local, etc.)
  - …or **none** — meetscribe will skip the de-dup pass and name folders by date.
- **Optional launchers** for one-press start/stop:
  - [SwiftBar](https://github.com/swiftbar/SwiftBar) for the menu bar
  - The included Dock app

## Install

```bash
git clone https://github.com/YOUR-USERNAME/meetscribe.git
cd meetscribe
./scripts/build.sh              # compile sccap, bundle as sccap.app, ad-hoc sign
./scripts/install.sh            # copy meetscribe + meetscribe-bg to ~/.local/bin
./scripts/install-launchers.sh  # optional: Dock app + SwiftBar plugin
```

Make sure `~/.local/bin` is on your `PATH` (the install script will warn if not).

## First-run permissions (one time)

ScreenCaptureKit requires permission. The first time you start, meetscribe will tell you so and bail safely — *it won't silently record nothing.*

1. Open **System Settings → Privacy & Security → Screen Recording**.
2. Find **"Meeting Audio Capture"** (or `sccap`) and turn it **on**.
3. Same in **Privacy & Security → Microphone**.

That's it. Because meetscribe launches `sccap.app` via `open` — making it its own TCC-responsible process — that one grant covers every launch path: the menu bar, the Dock app, or `meetscribe start` from a terminal.

## Usage

**Menu bar / Dock app** — click 🔴 (or the Dock icon) → talk → click again to stop. Pause/Resume in the menu when recording.

**CLI:**
```bash
meetscribe start       # start a recording
meetscribe pause       # freeze capture — truly nothing recorded until resume
meetscribe resume      # un-pause
meetscribe stop        # stop, transcribe, de-dup, mix, name the folder
meetscribe toggle      # start if idle, otherwise stop
meetscribe status      # IDLE / RECORDING / PAUSED + which backends are wired
```

## Configuration

Put any of these in your shell rc, or in `~/.config/meetscribe/config` (sourced if present):

| Variable | Default | What it does |
|---|---|---|
| `MEETSCRIBE_OUTDIR` | `~/Desktop/meet-recordings` | Where finished recordings land |
| `MEETSCRIBE_SCCAP_APP` | `~/Applications/sccap.app` | Path to the capture app bundle |
| `MEETSCRIBE_TRANSCRIBER` | (auto-detect) | `whisper-cpp` or `openai-whisper` |
| `MEETSCRIBE_WHISPER_MODEL` | `~/.local/share/meetscribe/models/ggml-base.en.bin` (whisper-cpp) / `base.en` (openai-whisper) | Model path/name |
| `MEETSCRIBE_LLM` | (auto-detect) | `claude`, `ollama`, `llm`, or `none` |
| `MEETSCRIBE_LLM_MODEL` | `llama3.1:8b` (ollama) / `gpt-4o-mini` (llm) | LLM model identifier |

## How it works

```
┌─────────────────┐    open       ┌─────────────────────┐
│   menu bar /    │──── -a ──────▶│      sccap.app      │  ScreenCaptureKit
│   Dock / CLI    │               │  (Objective-C)      │ ──▶ them.wav (system)
└─────────────────┘               │                     │ ──▶ me.wav   (mic)
                                  └─────────────────────┘
                                           ▲
                                           │ SIGINT on stop
                                           │
┌─────────────────────────────────────────────────────────────────────────────┐
│                              meetscribe (zsh)                               │
│                                                                             │
│   transcribe_wav  ──▶  whisper backend  ──▶  [Them]/[Me] interleaved text   │
│   clean_transcript──▶  LLM (optional)   ──▶  echo de-duped dialogue         │
│   combine_audio   ──▶  ffmpeg amix      ──▶  audio.m4a                      │
│   title_folder    ──▶  LLM (optional)   ──▶  MM-DD-YY-<company-type>/       │
└─────────────────────────────────────────────────────────────────────────────┘
```

A few details worth knowing:

- **Two WAVs, not one.** `them.wav` (system audio) is a clean digital tap — never echoes. `me.wav` (your mic) may pick up the meeting through your speakers if you don't wear headphones; the LLM de-dup step strips those repeated phrases out. (No LLM? Wear headphones, or live with some redundancy.)
- **Different sample rates.** ScreenCaptureKit returns system audio at the rate you ask for (16 kHz here) but the mic at its native rate (typically 48 kHz). sccap tags each WAV with its real rate; meetscribe resamples to 16 kHz before whisper.
- **App bundle for stable TCC.** Launching `sccap` as a bare CLI made permission attribution flaky (depends on the GUI ancestor that spawned it). Wrapping it in `sccap.app` and launching via `open` makes it self-responsible — one grant works everywhere.
- **True pause.** `pause` sends `SIGSTOP` to sccap, freezing capture. The paused audio is genuinely not recorded (not "recorded then trimmed"). `resume` sends `SIGCONT`.

## Roadmap

- More transcription backends (WhisperKit, faster-whisper)
- A `--no-llm` mode that still produces a usable folder name from a quick keyword scan
- Live transcript while recording (this version transcribes on stop for reliability)
- Optional: a real-time waveform/level in the menu bar

PRs welcome.

## Acknowledgments

This wouldn't be lean without these prior projects pointing the way:
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — the workhorse transcription engine.
- [tonton-golio/meeting-recorder](https://github.com/tonton-golio/meeting-recorder) — proof that ScreenCaptureKit + WhisperKit is the right architecture (build-from-Swift; this repo is the Objective-C/whisper.cpp cousin).
- [Meetily](https://github.com/Zackriya-Solutions/meetily) and [Hyprnote](https://github.com/fastrepl/hyprnote) — the full notes-suite tools we deliberately *aren't*.
- [SwiftBar](https://github.com/swiftbar/SwiftBar) — the lovely menu-bar host for the included plugin.

## License

[MIT](LICENSE).
