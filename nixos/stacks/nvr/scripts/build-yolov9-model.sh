#!/usr/bin/env bash
# Build YOLOv9 ONNX model for Frigate NVR
#
# This script builds a YOLOv9 model in ONNX format using Docker.
# The model is optimized for use with Frigate's ONNX detector.
#
# Usage: ./build-yolov9-model.sh [MODEL_SIZE] [IMG_SIZE]
#   MODEL_SIZE: t, s, m, c, or e (default: s)
#   IMG_SIZE: 320 or 640 (default: 320)
#
# Output: yolov9-{MODEL_SIZE}-{IMG_SIZE}.onnx in current directory

set -euo pipefail

MODEL_SIZE="${1:-s}"
IMG_SIZE="${2:-320}"
OUTPUT_DIR="${3:-.}"

# Validate inputs
case "$MODEL_SIZE" in
  t|s|m|c|e) ;;
  *) echo "Error: MODEL_SIZE must be t, s, m, c, or e"; exit 1 ;;
esac

case "$IMG_SIZE" in
  320|416|640) ;;
  *) echo "Error: IMG_SIZE must be 320, 416, or 640"; exit 1 ;;
esac

OUTPUT_FILE="${OUTPUT_DIR}/yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx"

echo "=== Building YOLOv9 ONNX Model ==="
echo "Model size: ${MODEL_SIZE}"
echo "Image size: ${IMG_SIZE}x${IMG_SIZE}"
echo "Output: ${OUTPUT_FILE}"
echo ""

# Check if model already exists
if [[ -f "$OUTPUT_FILE" ]]; then
  echo "Model already exists at ${OUTPUT_FILE}"
  echo "Delete it first if you want to rebuild."
  exit 0
fi

# Build the model using Docker
# Based on: https://docs.frigate.video/configuration/object_detectors/
echo "Building model with Docker (this may take a few minutes)..."

docker build \
  --build-arg MODEL_SIZE="${MODEL_SIZE}" \
  --build-arg IMG_SIZE="${IMG_SIZE}" \
  --output "${OUTPUT_DIR}" \
  -f- . <<'DOCKERFILE'
FROM python:3.11 AS build

# Install system dependencies
RUN apt-get update && apt-get install --no-install-recommends -y libgl1

# Install uv for faster package installation
COPY --from=ghcr.io/astral-sh/uv:0.8.0 /uv /bin/

WORKDIR /yolov9

# Clone YOLOv9 repository
ADD https://github.com/WongKinYiu/yolov9.git .

# Install Python dependencies
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnx-simplifier>=0.4.1 onnxscript

# Build arguments
ARG MODEL_SIZE
ARG IMG_SIZE

# Download pre-trained weights
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt

# Fix torch.load deprecation warning
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py

# Export to ONNX format
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx

# Output stage - copy only the model file
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
DOCKERFILE

echo ""
echo "=== Build Complete ==="
echo "Model saved to: ${OUTPUT_FILE}"
echo ""
echo "To use this model in Frigate, add to your config.yml:"
echo ""
echo "detectors:"
echo "  onnx:"
echo "    type: onnx"
echo ""
echo "model:"
echo "  model_type: yolo-generic"
echo "  width: ${IMG_SIZE}"
echo "  height: ${IMG_SIZE}"
echo "  input_tensor: nchw"
echo "  input_pixel_format: rgb"
echo "  input_dtype: float"
echo "  path: /config/yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx"
echo "  labelmap_path: /labelmap/coco-80.txt"
