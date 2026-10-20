import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from probe_sources import analyze, auth_headers, extract_records, render_markdown  # noqa: E402


class ExtractRecordsTest(unittest.TestCase):
    def test_plain_list(self):
        self.assertEqual(extract_records([{"id": 1}]), [{"id": 1}])

    def test_wrapped_list(self):
        self.assertEqual(extract_records({"data": [{"id": 1}], "total": 1}), [{"id": 1}])

    def test_unknown_shape(self):
        self.assertIsNone(extract_records({"message": "unauthorized"}))


class AnalyzeTest(unittest.TestCase):
    def test_counts_duplicates_missing_ids_and_status(self):
        payload = {"results": [
            {"id": 10, "name": "A", "status": "verified"},
            {"id": 10, "name": "A bis", "status": "classic"},
            {"id": 11, "status": "verified"},
            {"name": "sin id"},
        ]}
        summary = analyze(payload)
        self.assertTrue(summary["recognized"])
        self.assertEqual(summary["records"], 4)
        self.assertEqual(summary["id_key"], "id")
        self.assertEqual(summary["duplicate_ids"], [10])
        self.assertEqual(summary["missing_id"], 1)
        self.assertEqual(summary["field_fill"]["name"], 0.75)
        self.assertEqual(summary["status_values"]["status"], {'"verified"': 2, '"classic"': 1})

    def test_unrecognized_payload_reports_keys(self):
        summary = analyze({"error": "x", "code": 401})
        self.assertFalse(summary["recognized"])
        self.assertEqual(summary["top_level_keys"], ["code", "error"])

    def test_empty_list(self):
        summary = analyze([])
        self.assertEqual(summary["records"], 0)
        self.assertIsNone(summary["id_key"])


class AuthHeadersTest(unittest.TestCase):
    def test_no_auth(self):
        self.assertEqual(auth_headers({"auth": "none"}), ({}, None))

    def test_missing_key_is_reported_not_raised(self):
        headers, error = auth_headers({"auth": "api_key", "api_key_env": "WFG_TEST_KEY_THAT_IS_UNSET"})
        self.assertIsNone(headers)
        self.assertIn("WFG_TEST_KEY_THAT_IS_UNSET", error)


class RenderTest(unittest.TestCase):
    def test_unprobed_source_is_listed(self):
        report = render_markdown([{"id": "x", "name": "X", "endpoints": {}, "error": "sin endpoints"}], "stamp")
        self.assertIn("No sondeada: sin endpoints", report)


if __name__ == "__main__":
    unittest.main()
