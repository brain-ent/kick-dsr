#!/usr/bin/env bash
set -euo pipefail

: "${DSR_API_KEY:?Set DSR_API_KEY before running the trace}"
: "${PROXY_LOG:?Set PROXY_LOG to the proxy JSONL path}"
: "${DIAG_LOG:?Set DIAG_LOG to the DSR diag JSONL path}"

DSR_URL=${DSR_URL:-http://127.0.0.1:8080}
RESULTS_ROOT=${RESULTS_ROOT:-results}
RUN_STAMP=$(date +%Y%m%d-%H%M%S)
TRACE_SCOPE=${TRACE_SCOPE:-dsr-2hop-$RUN_STAMP}
TRACE_SESSION=${TRACE_SESSION:-dsr-2hop-system-$RUN_STAMP}
RUN_DIR="$RESULTS_ROOT/$RUN_STAMP"

mkdir -p "$RUN_DIR"

INGEST_BODY=$(jq -n \
  --arg session "$TRACE_SCOPE" \
  --arg scope "$TRACE_SCOPE" \
  '{session_id:$session,scope:$scope,facts:[
    {text:"Anton is linked to SIGMA-17."},
    {text:"SIGMA-17 is linked to BOREALIS-9."},
    {text:"BOREALIS-9 resolves to 73."}
  ]}')

curl -fsS "$DSR_URL/v1/dsr/ingest" \
  -H "Authorization: Bearer $DSR_API_KEY" \
  -H 'Content-Type: application/json' \
  -H "X-Session-Id: $TRACE_SCOPE" \
  -H "X-Scope-Id: $TRACE_SCOPE" \
  -d "$INGEST_BODY" > "$RUN_DIR/ingest-response.json"

PROXY_OFFSET=$(stat -c %s "$PROXY_LOG")
DIAG_OFFSET=$(stat -c %s "$DIAG_LOG")

SYSTEM_MESSAGE='Execute a controlled memory-chain trace. Inspect only the <facts> block. If it has no BOREALIS-9, output exactly SEARCH: SIGMA-17. If it has BOREALIS-9 but no numeric resolves-to fact, output exactly SEARCH: BOREALIS-9. If it has a numeric resolves-to fact, output exactly VALUE=<that integer>.'

CHAT_BODY=$(jq -n \
  --arg system "$SYSTEM_MESSAGE" \
  '{model:"dsr-etude-35b",messages:[
    {role:"system",content:$system},
    {role:"user",content:"Find Anton terminal value."}
  ],temperature:0,max_tokens:32,stream:false,memory_mode:"private"}')

nvidia-smi \
  --query-gpu=timestamp,index,name,memory.used,utilization.gpu,power.draw \
  --format=csv,noheader,nounits -l 1 > "$RUN_DIR/gpu.csv" &
SAMPLER_PID=$!

cleanup_sampler() {
  kill "$SAMPLER_PID" 2>/dev/null || true
  wait "$SAMPLER_PID" 2>/dev/null || true
}
trap cleanup_sampler EXIT

set +e
curl -fsS --max-time 360 \
  -D "$RUN_DIR/response-headers.txt" \
  -o "$RUN_DIR/response.json" \
  -w 'http=%{http_code} starttransfer_s=%{time_starttransfer} total_s=%{time_total} bytes=%{size_download}\n' \
  "$DSR_URL/v1/chat/completions" \
  -H "Authorization: Bearer $DSR_API_KEY" \
  -H 'Content-Type: application/json' \
  -H "X-Session-Id: $TRACE_SESSION" \
  -H "X-Scope-Id: $TRACE_SCOPE" \
  -d "$CHAT_BODY" > "$RUN_DIR/curl-metrics.txt"
CURL_RC=$?
set -e

cleanup_sampler
trap - EXIT

tail -c "+$((PROXY_OFFSET + 1))" "$PROXY_LOG" | jq -c '
  if .direction == "DSR -> QWEN" then
    {timestamp,direction,method,path,prompt_chars:(.body.prompt|length)}
  else
    {timestamp,direction,method,path,status,
     text:(.body.choices[0].text // null),usage:(.body.usage // null)}
  end
' > "$RUN_DIR/events.jsonl"

tail -c "+$((DIAG_OFFSET + 1))" "$DIAG_LOG" | jq -s '
  map({kind,question_len,retrieval_queries,stack_mode,shortlist_n,shortlist,
       history_chars,prompt_chars,answer_head,prompt_tokens,completion_tokens,
       finish,ts})
' > "$RUN_DIR/diag-summary.json"

nvidia-smi \
  --query-compute-apps=process_name,used_gpu_memory \
  --format=csv,noheader > "$RUN_DIR/compute-apps.txt"

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 "$SCRIPT_DIR/analyze_trace.py" \
  --proxy "$RUN_DIR/events.jsonl" \
  --gpu "$RUN_DIR/gpu.csv" \
  --curl-metrics "$RUN_DIR/curl-metrics.txt" \
  > "$RUN_DIR/summary.json"

printf 'Trace saved to %s\n' "$RUN_DIR"
exit "$CURL_RC"
