# nvr VM - Frigate NVR with ONNX/YOLOv9 Detection
#
# Services: Frigate (object detection, RTSP restreaming)
# GPU: NVIDIA T400 via PCI passthrough
# Detector: ONNX with YOLOv9-s-320 model (built on first boot)
{ name, config, pkgs, lib, ... }:

let
  # YOLOv9 model configuration
  modelSize = "s";      # t, s, m, c, or e
  imgSize = "320";      # 320, 416, or 640
  modelFile = "yolov9-${modelSize}-${imgSize}.onnx";
  configDir = "/opt/stacks/${name}/config";
in
{
  # ============================================================
  # Docker Stack Overrides
  # ============================================================
  dockerStack.extraPorts = [
    80          # Traefik HTTP
    8080        # Traefik Dashboard
    8971        # Frigate Web UI
    8554        # RTSP
    8555        # WebRTC (TCP + UDP opened below)
    5000        # Frigate API
  ];

  # Open WebRTC UDP port
  networking.firewall.allowedUDPPorts = [ 8555 ];

  # ============================================================
  # YOLOv9 Model Initialization
  # ============================================================
  # Builds the ONNX model on first boot if it doesn't exist.
  # This runs before the Docker stack starts.
  systemd.services.frigate-model-init = {
    description = "Build YOLOv9 ONNX model for Frigate";
    wantedBy = [ "multi-user.target" ];
    before = [ "${name}-stack.service" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];

    # Only run if model doesn't exist
    unitConfig = {
      ConditionPathExists = "!${configDir}/${modelFile}";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "30min";  # Model build can take a while

      ExecStart = pkgs.writeShellScript "build-yolov9-model" ''
        set -euo pipefail

        echo "Building YOLOv9-${modelSize} model at ${imgSize}x${imgSize}..."
        echo "This may take 10-20 minutes on first run."

        mkdir -p ${configDir}
        cd /tmp

        ${pkgs.docker}/bin/docker build \
          --build-arg MODEL_SIZE=${modelSize} \
          --build-arg IMG_SIZE=${imgSize} \
          --output ${configDir} \
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
        ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-''${MODEL_SIZE}-converted.pt yolov9-''${MODEL_SIZE}.pt
        RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py
        RUN python3 export.py --weights ./yolov9-''${MODEL_SIZE}.pt --imgsz ''${IMG_SIZE} --simplify --include onnx
        FROM scratch
        ARG MODEL_SIZE
        ARG IMG_SIZE
        COPY --from=build /yolov9/yolov9-''${MODEL_SIZE}.onnx /yolov9-''${MODEL_SIZE}-''${IMG_SIZE}.onnx
        DOCKERFILE

        if [[ -f "${configDir}/${modelFile}" ]]; then
          echo "Model built successfully: ${configDir}/${modelFile}"
          ls -lh "${configDir}/${modelFile}"
        else
          echo "ERROR: Model build failed!"
          exit 1
        fi
      '';
    };
  };
}
