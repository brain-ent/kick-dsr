# Controlled 2-hop DSR runtime trace

Дата: 2026-08-28, Europe/Moscow.

## Конфигурация

- Etude: Docker, healthy, локальный порт 8080.
- Logging proxy: host process, локальный порт 18001.
- vLLM: native Conda environment, локальный порт 18000.
- Runtime: Python 3.12.13, vLLM 0.22.0, PyTorch 2.11.0+cu129, CUDA runtime 12.9, NVIDIA driver 565.57.01.
- Model: `Qwen3_5MoeForConditionalGeneration`, AutoRound/AutoGPTQ INT4, group size 128.
- vLLM: pipeline parallel 3, tensor parallel 1, max model length 1024, one sequence, 2 GiB CPU offload per worker.
- Search loop: enabled, maximum two rounds.

## Проверяемая цепочка

```text
Anton -> SIGMA-17 -> BOREALIS-9 -> 73
```

Исходный retrieval нашёл только первое звено (`shortlist_n=1`). Управляющее system-сообщение использовалось, чтобы детерминированно проверить runtime orchestration отдельно от качества автономного search planning модели.

## Результат

| Qwen call | Ответ | Prompt chars | Prompt tokens | Completion tokens | Latency, s |
|---:|---|---:|---:|---:|---:|
| 1 | `SEARCH: SIGMA-17` | 3,147 | 698 | 8 | 78.981064 |
| 2 | `SEARCH: BOREALIS-9` | 3,189 | 719 | 9 | 88.663643 |
| 3 | `VALUE=73` | 3,224 | 737 | 5 | 77.122472 |

- Qwen calls: 3.
- Sum Qwen latency: 244.767179 s.
- DSR orchestration gaps: 0.001410 s and 0.001413 s.
- End-to-end curl latency: 244.813182 s.
- Total rendered prompt volume: 9,560 characters / 2,154 tokens.
- Total completion tokens: 22.
- Final HTTP status: 200.
- Final answer: `VALUE=73`.

DSR diagnostic summary подтверждает исходный shortlist и финальные usage, но в этой сборке поле `retrieval_queries` осталось `null`; оба внутренних search query подтверждены санитизированными proxy-событиями. Полные prompts, локальные пути, PID и GPU UUID намеренно не опубликованы.

## GPU isolation

В успешном прогоне записано 153 временных среза на каждый GPU.

| Physical GPU | Model | Max utilization | Max memory | Compute process |
|---:|---|---:|---:|---|
| 0 | RTX 3090 | 1% | 91 MiB | none |
| 1 | RTX 3090 | 1% | 15 MiB | none |
| 2 | RTX 3090 | 1% | 15 MiB | none |
| 3 | RTX 3070 | 100% | 5,751 MiB | PP0 |
| 4 | RTX 3070 | 100% | 6,193 MiB | PP1 |
| 5 | RTX 3070 | 100% | 6,713 MiB | PP2 |

На RTX 3090 compute-процессов не было. Небольшое использование памяти/1% activity связано с графической оболочкой, а не с vLLM.

## Пилотные попытки

1. Автономный planner: retrieval корректно дал `Anton -> SIGMA-17`, но Qwen сразу вернул `I do not know` вместо `SEARCH:`. Один вызов, 67.825056 s.
2. Условия переходов внутри user-вопроса загрязнили retrieval: все ключи были найдены сразу, и Qwen вернул `VALUE=73` одним вызовом за 70.841523 s.
3. Перенос условий в system-сообщение оставил user-вопрос чистым и дал требуемые два search hop.

Это показывает, что 2-hop runtime path работает, но автономное решение Qwen начать поиск текущим prompt policy не гарантируется.
