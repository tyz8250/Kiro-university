#!/usr/bin/env bash
set -euo pipefail

demo_dir="$(cd "$(dirname "$0")" && pwd)"
assets_dir="$demo_dir/assets"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-fault-demo.XXXXXX")"
render_dir="$work_dir/rendered"
output="$demo_dir/network-fault-observation-demo.mp4"
trap 'rm -rf "$work_dir"' EXIT

command -v python3 >/dev/null
command -v qlmanage >/dev/null
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null
command -v say >/dev/null

python3 "$demo_dir/generate_assets.py"
mkdir -p "$render_dir" "$work_dir"

for svg in "$assets_dir"/scene-*.svg; do
  qlmanage -t -s 1280 -o "$render_dir" "$svg" >/dev/null
  name="$(basename "$svg" .svg)"
  ffmpeg -v error -y -i "$render_dir/$(basename "$svg").png" \
    -vf 'crop=1280:720:0:280,format=rgb24' \
    "$assets_dir/$name.png"
done

durations=(12 15 13 15 12 13 12 20 8)
narration=(
  "Network Fault Observation is an AWS, Docker, and Go experiment that asks one question: where does communication stop?"
  "The request crosses six boundaries, from a Mac through the internet and an AWS VPC, into E C 2, Docker, and the Go server. We test by hypothesis, break, observation, explanation, and restore."
  "Before the fault, all five observation points were healthy: external curl, packet capture, Docker, host curl, and Go server logs."
  "Experiment one removed only the default route from the public route table: zero dot zero dot zero dot zero slash zero to the Internet Gateway."
  "The external curl timed out. But packet capture showed five sin packets reaching E C 2, and ten sin ack responses, including retransmissions. No final ack returned."
  "Meanwhile, internal health stayed at twenty-two out of twenty-two HTTP 200 responses, and Docker stayed up for twenty-two out of twenty-two checks. The original hypothesis was only partially correct."
  "After restoring the route, HTTP 200 returned immediately, and Terraform reported no changes. The experiment ended in its original infrastructure state."
  "Kiro organized the work with Specs, Steering, property-based tests, a Power connected to AWS documentation, a read-only custom agent, an Agent Stop validation hook, and project M C P settings."
  "A failed curl does not necessarily mean the application failed. Observe each boundary separately."
)

: > "$work_dir/video-list.txt"
: > "$work_dir/audio-list.txt"

for i in "${!durations[@]}"; do
  number="$(printf '%02d' "$((i + 1))")"
  duration="${durations[$i]}"
  png="$assets_dir/scene-$number.png"
  aiff="$work_dir/narration-$number.aiff"
  wav="$work_dir/narration-$number.wav"
  mp4="$work_dir/scene-$number.mp4"

  say -v Samantha -r 170 -o "$aiff" "${narration[$i]}"
  ffmpeg -v error -y -i "$aiff" -af "apad,atrim=0:$duration" -ar 48000 -ac 2 -c:a pcm_s16le "$wav"
  ffmpeg -v error -y -loop 1 -framerate 30 -i "$png" -t "$duration" \
    -vf "fade=t=in:st=0:d=0.35,fade=t=out:st=$(python3 -c "print(max(0, $duration - 0.35))"):d=0.35,format=yuv420p" \
    -r 30 -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p -an "$mp4"

  printf "file '%s'\n" "$mp4" >> "$work_dir/video-list.txt"
  printf "file '%s'\n" "$wav" >> "$work_dir/audio-list.txt"
done

ffmpeg -v error -y -f concat -safe 0 -i "$work_dir/video-list.txt" -c copy "$work_dir/visuals.mp4"
ffmpeg -v error -y -f concat -safe 0 -i "$work_dir/audio-list.txt" -c copy "$work_dir/narration.wav"

ffmpeg -v error -y \
  -i "$work_dir/visuals.mp4" \
  -i "$work_dir/narration.wav" \
  -i "$demo_dir/demo-subtitles.srt" \
  -map 0:v:0 -map 1:a:0 -map 2:0 \
  -c:v libx264 -preset slow -crf 20 -profile:v high -level 4.0 -pix_fmt yuv420p \
  -c:a aac -b:a 160k -ar 48000 \
  -c:s mov_text -metadata:s:s:0 language=eng -metadata:s:s:0 title="English" \
  -movflags +faststart -t 120 "$output"

ffprobe -v error -show_entries format=duration,size -show_entries stream=index,codec_name,codec_type,width,height:stream_tags=language,title -of json "$output"
