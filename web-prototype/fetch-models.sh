#!/usr/bin/env bash
# Downloads local copies of the MediaPipe runtime and models used by index.html.
# Optional: without them the page loads the same files from the CDN.
set -euo pipefail
cd "$(dirname "$0")" && mkdir -p mp
curl -sSL -o mp/face_landmarker.task https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
curl -sSL -o mp/selfie_segmenter.tflite https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite
curl -sSL -o mp/vision_wasm_internal.wasm https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm/vision_wasm_internal.wasm
echo "Models saved to web-prototype/mp/"
