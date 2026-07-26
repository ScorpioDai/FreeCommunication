import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from freecommunication_backend import Segment, handle_warm_model, split_stream_segments


class StreamSegmentSplittingTests(unittest.TestCase):
    def test_oversized_segment_is_split_without_losing_words(self):
        source = " ".join(f"word{index}" for index in range(95))
        segment = Segment("system", "电脑音频", 4.0, 42.0, source)

        chunks = split_stream_segments([segment])

        self.assertTrue(all(len(chunk.source_text.split()) <= 64 for chunk in chunks))
        self.assertTrue(all(len(chunk.source_text) <= 420 for chunk in chunks))
        self.assertEqual(" ".join(chunk.source_text for chunk in chunks), source)
        self.assertEqual(chunks[0].start, 4.0)
        self.assertEqual(chunks[-1].end, 42.0)
        self.assertTrue(all(left.end <= right.start for left, right in zip(chunks, chunks[1:])))

    def test_existing_sentence_boundary_is_preferred(self):
        words = [f"word{index}" for index in range(70)]
        words[29] += "."
        chunks = split_stream_segments(
            [Segment("microphone", "我", 0.0, 28.0, " ".join(words))]
        )

        self.assertEqual(len(chunks[0].source_text.split()), 30)
        self.assertTrue(chunks[0].source_text.endswith("."))

    def test_character_limit_handles_long_words(self):
        source = " ".join("x" * 50 for _ in range(12))
        chunks = split_stream_segments(
            [Segment("system", "电脑音频", 0.0, 12.0, source)]
        )

        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(chunk.source_text) <= 420 for chunk in chunks))
        self.assertEqual(" ".join(chunk.source_text for chunk in chunks), source)

    def test_completed_chunk_boundaries_are_stable_as_partial_text_grows(self):
        short = " ".join(f"word{index}" for index in range(70))
        long = " ".join(f"word{index}" for index in range(90))

        short_chunks = split_stream_segments(
            [Segment("system", "电脑音频", 0.0, 28.0, short)]
        )
        long_chunks = split_stream_segments(
            [Segment("system", "电脑音频", 0.0, 36.0, long)]
        )

        self.assertEqual(short_chunks[0].source_text, long_chunks[0].source_text)

    def test_small_segment_keeps_existing_translation(self):
        segment = Segment("microphone", "我", 0.0, 2.0, "Hello there.", "你好。")

        chunks = split_stream_segments([segment])

        self.assertEqual(chunks, [segment])
        self.assertEqual(chunks[0].translated_text, "你好。")

    def test_short_sentences_are_grouped_three_at_a_time(self):
        segments = [
            Segment("system", "电脑音频", 0.0, 1.0, "Yes."),
            Segment("system", "电脑音频", 1.0, 3.0, "That is right."),
            Segment("system", "电脑音频", 3.0, 5.0, "Let us continue."),
            Segment("system", "电脑音频", 5.0, 7.0, "Here is the next topic."),
        ]

        chunks = split_stream_segments(segments)

        self.assertEqual(len(chunks), 2)
        self.assertEqual(
            chunks[0].source_text,
            "Yes. That is right. Let us continue.",
        )
        self.assertEqual(chunks[0].start, 0.0)
        self.assertEqual(chunks[0].end, 5.0)
        self.assertEqual(chunks[1].source_text, "Here is the next topic.")


class ModelWarmupTests(unittest.TestCase):
    def test_each_model_kind_uses_its_resident_loader(self):
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory))
            with patch("freecommunication_backend.load_asr_model") as load_asr, patch(
                "freecommunication_backend.load_nmt_model"
            ) as load_nmt:
                asr_response = handle_warm_model(
                    {"model": "asr", "asr_model": path},
                    "asr-request",
                )
                nmt_response = handle_warm_model(
                    {"model": "nmt", "nmt_model": path},
                    "nmt-request",
                )

        self.assertTrue(asr_response["ok"])
        self.assertTrue(nmt_response["ok"])
        load_asr.assert_called_once_with(Path(path))
        load_nmt.assert_called_once_with(Path(path))


if __name__ == "__main__":
    unittest.main()
