# Etude competitive acceptance gates

These are release gates, not demo scenarios. A controlled prompt that tells Qwen which
`SEARCH:` command to emit proves wiring only; it does not pass autonomous multi-hop.

## P0: correctness and safety

| Capability | Minimum gate | Why it is required |
|---|---:|---|
| Exact single-fact recall | 100% on 100 seeded cases | Basic memory must be dependable. |
| Autonomous 2-hop | >=95% on 100 unseen graphs | No intermediate keys may appear in the question or system prompt. |
| Autonomous 3-hop | >=90% on 100 unseen graphs | Shows that search planning generalizes beyond the demo. |
| Abstention | >=99% | Missing memory must produce `NOT_FOUND`, not a plausible invention. |
| Tenant/scope isolation | 100%, zero leaked bytes | Any cross-tenant leak blocks release. |
| Stored prompt injection | 100% safe outcomes | Retrieved text is untrusted data, never an instruction channel. |
| Supersession | 100% latest-valid answers | Old and corrected facts must not be presented as equally current. |
| Forget/delete | 100% removal from recall, graph, cache and backup policy | Required for enterprise privacy and lifecycle control. |
| Provenance | 100% of factual answers cite memory IDs | Customers must be able to audit where an answer came from. |
| GPU isolation | Zero Etude/vLLM compute processes on forbidden GPUs | Deployment policy must be mechanically enforceable. On the current host only physical GPUs 3, 4 and 5 are allowed. |

Security gates have no averaged pass rate: one tenant leak or successful stored injection
is a release failure.

## P0: efficiency

Measure Etude and a direct Qwen baseline with the same model, sampling settings and
hardware. Report median and p95 over at least 100 queries after warm-up.

| Metric | Release gate |
|---|---:|
| Direct recall Qwen calls | 1 |
| 2-hop Qwen calls | <=3; target 1 after deterministic graph traversal |
| Direct-recall token amplification | <=1.20x final-call tokens |
| 2-hop token amplification | <=1.80x final-call tokens |
| Static Etude instructions | <=15% of rendered prompt tokens |
| Retrieval/orchestration overhead excluding inference | p95 <=100 ms |
| Direct-recall end-to-end latency | p95 <=30 s on the declared 3x RTX 3070 reference |
| Autonomous 2-hop end-to-end latency | p95 <=45 s on the same reference |
| Error-free requests | >=99.9% over 10,000 requests |

The measured prototype trace (244.8 s and 2.93x total-token amplification) fails the
interactive latency and token gates even though the controlled chain returned the right
value.

## P1: product readiness

- Determinism: >=99% identical normalized answers across 20 temperature-zero repetitions.
- Retrieval quality: Recall@5 >=95% and nDCG@10 >=0.90 on a domain dataset with distractors.
- Concurrency: 20 simultaneous sessions without scope mixing; publish throughput and p95.
- Restart durability: acknowledged memories survive Etude, proxy and vLLM restarts.
- Partial failure: vLLM timeout, malformed model output and unavailable storage return typed
  errors without corrupting memory or retrying indefinitely.
- Resource isolation: startup must fail closed if the configured GPU UUID allowlist cannot be
  resolved; GPU indices alone are insufficient because enumeration can change after a reboot.
- Compatibility: the same suite passes against at least two OpenAI-compatible local models.
- Operations: RBAC, encryption, retention, audit events, quotas and per-tenant usage metrics.
- Evaluation hygiene: fixed seeds, held-out graphs, sanitized raw traces and versioned model,
  prompt, Etude and infrastructure metadata.

## Running the executable smoke suite

The included eight-case suite is deliberately small and catches the current architectural
problems quickly. Run the larger statistical gates only after this smoke suite is green.

```bash
export DSR_API_KEY='...'
export PROXY_LOG='/home/alex/dsr-qwen-proxy/dsr_qwen.jsonl'
python3 scripts/run_competitive_suite.py \
  --base-url http://127.0.0.1:8080 \
  --output results/competitive-suite.json
```

Without `PROXY_LOG`, answer and latency checks still run, but Qwen-call and token gates are
reported as unavailable rather than guessed. Use `--repetitions 20` for a determinism pass,
or `--only autonomous_2hop` while iterating on search planning.
