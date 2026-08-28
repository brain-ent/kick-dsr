#!/usr/bin/env python3
import argparse
import csv
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Summarize a DSR proxy/GPU trace")
    parser.add_argument("--proxy", required=True)
    parser.add_argument("--gpu", required=True)
    parser.add_argument("--curl-metrics")
    return parser.parse_args()


def load_jsonl(path):
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip()]


def timestamp(value):
    return datetime.fromisoformat(value).timestamp()


def proxy_summary(events):
    calls = []
    pending = None

    for event in events:
        if event.get("path") != "/v1/completions":
            continue
        if event.get("direction") == "DSR -> QWEN":
            if pending is not None:
                raise ValueError("Found a new request before the previous response")
            pending = event
        elif event.get("direction") == "QWEN -> DSR":
            if pending is None:
                raise ValueError("Found a response without a request")
            usage = event.get("usage") or event.get("body", {}).get("usage", {})
            prompt_chars = pending.get("prompt_chars")
            if prompt_chars is None:
                prompt_chars = len(pending.get("body", {}).get("prompt", ""))
            text = event.get("text")
            if text is None:
                text = event.get("body", {}).get("choices", [{}])[0].get("text")
            calls.append(
                {
                    "index": len(calls) + 1,
                    "request_timestamp": pending["timestamp"],
                    "response_timestamp": event["timestamp"],
                    "latency_s": round(
                        timestamp(event["timestamp"]) - timestamp(pending["timestamp"]),
                        6,
                    ),
                    "prompt_chars": prompt_chars,
                    "prompt_tokens": usage.get("prompt_tokens"),
                    "completion_tokens": usage.get("completion_tokens"),
                    "total_tokens": usage.get("total_tokens"),
                    "text": text,
                    "status": event.get("status"),
                }
            )
            pending = None

    gaps = []
    for previous, current in zip(calls, calls[1:]):
        gaps.append(
            round(
                timestamp(current["request_timestamp"])
                - timestamp(previous["response_timestamp"]),
                6,
            )
        )

    return {
        "qwen_call_count": len(calls),
        "calls": calls,
        "orchestration_gaps_s": gaps,
        "sum_qwen_latency_s": round(sum(call["latency_s"] for call in calls), 6),
        "sum_prompt_chars": sum(call["prompt_chars"] for call in calls),
        "sum_prompt_tokens": sum((call["prompt_tokens"] or 0) for call in calls),
        "sum_completion_tokens": sum((call["completion_tokens"] or 0) for call in calls),
    }


def gpu_summary(path):
    stats = defaultdict(lambda: {"samples": 0, "max_utilization_pct": 0, "max_memory_mib": 0})
    with open(path, encoding="utf-8") as handle:
        for row in csv.reader(handle, skipinitialspace=True):
            if len(row) < 6:
                continue
            index = int(row[1])
            entry = stats[index]
            entry["name"] = row[2]
            if len(row) >= 7:
                entry["uuid"] = row[3]
                memory_index = 4
                utilization_index = 5
            else:
                memory_index = 3
                utilization_index = 4
            entry["samples"] += 1
            entry["max_memory_mib"] = max(
                entry["max_memory_mib"], int(float(row[memory_index]))
            )
            entry["max_utilization_pct"] = max(
                entry["max_utilization_pct"], int(float(row[utilization_index]))
            )
    return {str(index): stats[index] for index in sorted(stats)}


def curl_summary(path):
    if not path:
        return None
    values = {}
    for item in Path(path).read_text(encoding="utf-8").split():
        key, value = item.split("=", 1)
        try:
            values[key] = float(value) if "." in value else int(value)
        except ValueError:
            values[key] = value
    return values


def main():
    args = parse_args()
    result = {
        "proxy": proxy_summary(load_jsonl(args.proxy)),
        "gpu": gpu_summary(args.gpu),
        "curl": curl_summary(args.curl_metrics),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
