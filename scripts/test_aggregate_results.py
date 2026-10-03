import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class AggregateResultsTest(unittest.TestCase):

    def test_writes_per_run_and_grouped_statistics(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            inputs = root / "inputs"
            inputs.mkdir()

            self.write_result(inputs / "a.json", 1, 100, 390, 10, 0.20, 0.01, tx_work_ms=2)
            self.write_result(inputs / "b.json", 2, 100, 410, 14, 0.40, 0.03, tx_work_ms=2)
            self.write_result(inputs / "c.json", 1, 20, 300, 30, 1.00, 0.10, tx_work_ms=2)
            self.write_result(inputs / "d.json", 1, 100, 280, 40, 0.80, 0.08, tx_work_ms=10)

            runs_output = root / "runs.csv"
            summary_output = root / "summary.csv"

            subprocess.run(
                [
                    sys.executable,
                    "scripts/aggregate_results.py",
                    "--input-glob",
                    str(inputs / "*.json"),
                    "--runs-output",
                    str(runs_output),
                    "--summary-output",
                    str(summary_output),
                ],
                check=True,
            )

            with runs_output.open(encoding="utf-8") as handle:
                runs = list(csv.DictReader(handle))

            with summary_output.open(encoding="utf-8") as handle:
                summary = list(csv.DictReader(handle))

            self.assertEqual(4, len(runs))
            self.assertEqual(3, len(summary))

            low_2ms = next(
                row
                for row in summary
                if row["hotSet"] == "100" and row["txWorkMs"] == "2.0"
            )
            self.assertEqual("2", low_2ms["n"])
            self.assertAlmostEqual(400.0, float(low_2ms["throughputPerSecond_median"]))
            self.assertAlmostEqual(12.0, float(low_2ms["p99LatencyMs_median"]))
            self.assertAlmostEqual(0.30, float(low_2ms["retryAmplification_median"]))
            self.assertAlmostEqual(0.02, float(low_2ms["failureRate_median"]))

            low_10ms = next(
                row
                for row in summary
                if row["hotSet"] == "100" and row["txWorkMs"] == "10.0"
            )
            self.assertEqual("1", low_10ms["n"])
            self.assertAlmostEqual(280.0, float(low_10ms["throughputPerSecond_median"]))

    @staticmethod
    def write_result(
        path,
        repetition,
        hot_set,
        throughput,
        p99,
        retry_amp,
        failure_rate,
        tx_work_ms=0,
    ):
        success_count = int(throughput * 60)
        payload = {
            "metadata": {
                "strategy": "OPT_EXPONENTIAL_JITTER",
                "hotSet": hot_set,
                "rate": 500,
                "txWorkMs": tx_work_ms,
                "warmup": "20s",
                "duration": "60s",
                "durationSeconds": 60,
                "repetition": repetition,
            },
            "metrics": {
                "successCount": success_count,
                "failureCount": int(success_count * failure_rate),
                "retryCount": int(success_count * retry_amp),
                "throughputPerSecond": throughput,
                "p99LatencyMs": p99,
                "retryAmplification": retry_amp,
                "failureRate": failure_rate,
                "droppedIterations": 0,
            },
        }
        path.write_text(json.dumps(payload), encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
