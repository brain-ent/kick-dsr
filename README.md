# Kick DSR runtime trace

В репозитории сохранён воспроизводимый trace цепочки:

```text
Etude (Docker :8080) -> logging proxy (:18001) -> native vLLM (:18000)
```

Контрольный набор фактов требует двух последовательных поисков:

```text
Anton -> SIGMA-17 -> BOREALIS-9 -> 73
```

Успешный прогон от 28 августа 2026 года дал ровно три вызова Qwen: два ответа `SEARCH:` и финальный `VALUE=73`. Полный отчёт и санитизированные артефакты находятся в `results/2026-08-28/`.

## Повторный запуск

Требования: работающие Etude, proxy и vLLM, а также `curl`, `jq`, `python3` и `nvidia-smi`.

```bash
export DSR_API_KEY='...'
export PROXY_LOG='/path/to/proxy.jsonl'
export DIAG_LOG='/path/to/diag.jsonl'
./scripts/run_2hop_trace.sh
```

Скрипт не очищает существующие логи: он фиксирует byte-offset перед запросом и сохраняет только добавленные события. Полные prompts, API key, PID, локальные пути и GPU UUID в результаты не записываются.

Для запуска нативного vLLM предусмотрен `scripts/start-vllm-3070.sh`. Пути и три разрешённых UUID RTX 3070 передаются через переменные окружения; скрипт не содержит идентификаторов конкретной машины.

## Competitive acceptance suite

`scripts/run_competitive_suite.py` проверяет Etude как продукт, а не только wiring:
автономный 2/3-hop, distractors, abstention, scope isolation, stored prompt injection,
supersession, число вызовов Qwen, token amplification и latency. Тестовые сценарии лежат
в `benchmarks/competitive_cases.json`, а обязательные release gates описаны в
`docs/competitive-acceptance-gates.md`.

```bash
export DSR_API_KEY='...'
export PROXY_LOG='/home/alex/dsr-qwen-proxy/dsr_qwen.jsonl'
python3 scripts/run_competitive_suite.py --base-url http://127.0.0.1:8080
```

Это smoke-suite из восьми сценариев. Для релизного решения каждый P0 gate должен быть
проверен на полном датасете; security-тесты требуют нулевого числа нарушений.
