#!/usr/bin/env bash
# Initialize Frigate YOLO model on first boot
#
# This script checks if the YOLOv9 model exists and builds it if not.
# It should be run before the Frigate Docker stack starts.

set -euo pipefail

MODEL_SIZE="${MODEL_SIZE:-s}"
IMG_SIZE="${IMG_SIZE:-320}"
CONFIG_DIR="/opt/stacks/nvr/config"
MODEL_FILE="${CONFIG_DIR}/yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx"

echo "[frigate-model-init] Checking for YOLOv9 model..."

# Check if model already exists
if [[ -f "$MODEL_FILE" ]]; then
  echo "[frigate-model-init] Model already exists: ${MODEL_FILE}"
  exit 0
fi

echo "[frigate-model-init] Model not found, building YOLOv9-${MODEL_SIZE} at ${IMG_SIZE}x${IMG_SIZE}..."
echo "[frigate-model-init] This may take several minutes on first run..."

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Build the model using Docker
# Based on: https://docs.frigate.video/configuration/object_detectors/
cd /tmp

docker build \
  --build-arg MODEL_SIZE="${MODEL_SIZE}" \
  --build-arg IMG_SIZE="${IMG_SIZE}" \
  --output "${CONFIG_DIR}" \
  -f- . <<'DOCKERFILE'
FROM python:3.11 AS build

RUN apt-get update && apt-get install --no-install-recommends -y libgl1
COPY --from=ghcr.io/astral-sh/uv:0.8.0 /uv /bin/

WORKDIR /yolov9
ADD https://github.com/WongKinYiu/yolov9.git .

RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnx-simplifier>=0.4.1 onnxscript

ARG MODEL_SIZE
ARG IMG_SIZE

ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt

RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py

RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx

FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
DOCKERFILE

if [[ -f "$MODEL_FILE" ]]; then
  echo "[frigate-model-init] Model built successfully: ${MODEL_FILE}"
  ls -lh "$MODEL_FILE"
else
  echo "[frigate-model-init] ERROR: Model build failed!"
  exit 1
fi
