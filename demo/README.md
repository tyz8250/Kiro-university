# Network Fault Observation demo

Submission-ready 120-second demo for the Kiro University Challenge.

## Outputs

- `network-fault-observation-demo.mp4` — 1280x720, H.264, AAC narration, embedded `mov_text` English subtitle track
- `demo-script.txt` — timed English narration script
- `demo-subtitles.srt` — English subtitle source
- `assets/scene-*.svg` — editable 16:9 scene artwork on a square render canvas
- `assets/scene-*.png` — rendered 1280x720 scene images

Important narration is duplicated in the scene artwork, so the video remains understandable when muted. The MP4 also includes a selectable English subtitle track.

## Rebuild on macOS

Requirements: `python3`, macOS `say`, `qlmanage`, `ffmpeg`, and `ffprobe`.

```bash
./demo/build-demo.sh
```

The build reads no cloud credentials, makes no AWS calls, and does not run Terraform, Docker, or project tests. It only writes under `demo/`.

## Source and safety

The visuals summarize `README.md`, `results/baseline.json`, `results/fault.json`, `results/report.md`, and the project `.kiro` configuration. Public placeholders are used instead of personal addresses. No credentials, local absolute paths, or packet-capture files are included.
