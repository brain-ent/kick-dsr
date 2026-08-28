import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "competitive_suite", ROOT / "scripts/run_competitive_suite.py"
)
SUITE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SUITE)


class CompetitiveSuiteUnitTests(unittest.TestCase):
    def test_proxy_metrics_counts_calls_and_amplification(self):
        events = [
            {"direction": "DSR -> QWEN", "path": "/v1/completions"},
            {
                "direction": "QWEN -> DSR",
                "path": "/v1/completions",
                "usage": {"prompt_tokens": 90, "completion_tokens": 10},
            },
            {"direction": "DSR -> QWEN", "path": "/v1/completions"},
            {
                "direction": "QWEN -> DSR",
                "path": "/v1/completions",
                "usage": {"prompt_tokens": 180, "completion_tokens": 20},
            },
        ]
        metrics = SUITE.proxy_metrics(events)
        self.assertEqual(metrics["qwen_calls"], 2)
        self.assertEqual(metrics["total_qwen_tokens"], 300)
        self.assertEqual(metrics["token_amplification"], 1.5)

    def test_answer_checks_are_anchored_and_case_insensitive_for_leaks(self):
        case = {
            "expected_regex": "^VALUE=73$",
            "forbidden_substrings": ["secret"],
            "max_latency_s": 10,
            "max_qwen_calls": 3,
            "max_token_amplification": 2,
        }
        metrics = {"qwen_calls": 1, "token_amplification": 1.0}
        self.assertTrue(all(SUITE.checks_for(case, "VALUE=73", 1, metrics).values()))
        self.assertFalse(
            SUITE.checks_for(case, "VALUE=73 SECRET", 1, metrics)["answer_format"]
        )
        self.assertFalse(
            SUITE.checks_for(case, "secret", 1, metrics)["no_forbidden_text"]
        )

    def test_every_case_has_core_release_limits(self):
        cases = json.loads(
            (ROOT / "benchmarks/competitive_cases.json").read_text(encoding="utf-8")
        )
        self.assertGreaterEqual(len(cases), 8)
        for case in cases:
            with self.subTest(case=case["id"]):
                self.assertIn("expected_regex", case)
                self.assertIn("max_qwen_calls", case)
                self.assertIn("max_token_amplification", case)
                self.assertIn("max_latency_s", case)


if __name__ == "__main__":
    unittest.main()
