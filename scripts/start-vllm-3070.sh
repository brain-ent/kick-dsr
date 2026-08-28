#!/usr/bin/env bash
set -euo pipefail

: "${VLLM_ENV:?Set VLLM_ENV to the Conda environment path}"
: "${MODEL_DIR:?Set MODEL_DIR to the model checkpoint path}"
: "${RTX3070_UUIDS:?Set RTX3070_UUIDS to the three comma-separated allowed GPU UUIDs}"

# UUID routing avoids ambiguity from CUDA device ordering on a heterogeneous
# 3090/3070 machine. Verify the supplied UUIDs with nvidia-smi before launch.
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export CUDA_VISIBLE_DEVICES="$RTX3070_UUIDS"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

export CUDA_HOME="$VLLM_ENV"
export CUDACXX="$VLLM_ENV/bin/nvcc"
export CUDA_NVCC_EXECUTABLE="$VLLM_ENV/bin/nvcc"
export CUDA_PATH="$VLLM_ENV"
export CPATH="$VLLM_ENV/targets/x86_64-linux/include:${CPATH:-}"
export LIBRARY_PATH="$VLLM_ENV/lib64:$VLLM_ENV/targets/x86_64-linux/lib:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$VLLM_ENV/lib64:$VLLM_ENV/targets/x86_64-linux/lib:$VLLM_ENV/lib/python3.12/site-packages/nvidia/curand/lib:${LD_LIBRARY_PATH:-}"

exec "$VLLM_ENV/bin/vllm" serve "$MODEL_DIR" \
  --host 127.0.0.1 \
  --port 18000 \
  --served-model-name dsr-etude-engine \
  --tensor-parallel-size 1 \
  --pipeline-parallel-size 3 \
  --distributed-executor-backend mp \
  --language-model-only \
  --max-model-len 1024 \
  --max-num-seqs 1 \
  --gpu-memory-utilization 0.80 \
  --cpu-offload-gb 2 \
  --enforce-eager \
  --no-enable-prefix-caching
