import unittest

from freecommunication_backend import Segment, split_stream_segments


class StreamSegmentSplittingTests(unittest.TestCase):
    def test_oversized_segment_is_split_without_losing_words(self):
        source = " ".join(f"word{index}" for index in range(95))
        segment = Segment("system", "电脑音频", 4.0, 42.0, source)

        chunks = split_stream_segments([segment])

        self.assertTrue(all(len(chunk.source_text.split()) <= 36 for chunk in chunks))
        self.assertTrue(all(len(chunk.source_text) <= 240 for chunk in chunks))
        self.assertEqual(" ".join(chunk.source_text for chunk in chunks), source)
        self.assertEqual(chunks[0].start, 4.0)
        self.assertEqual(chunks[-1].end, 42.0)
        self.assertTrue(all(left.end <= right.start for left, right in zip(chunks, chunks[1:])))

    def test_existing_sentence_boundary_is_preferred(self):
        words = [f"word{index}" for index in range(70)]
        words[19] += "."
        chunks = split_stream_segments(
            [Segment("microphone", "我", 0.0, 28.0, " ".join(words))]
        )

        self.assertEqual(len(chunks[0].source_text.split()), 20)
        self.assertTrue(chunks[0].source_text.endswith("."))

    def test_character_limit_handles_long_words(self):
        source = " ".join("x" * 50 for _ in range(12))
        chunks = split_stream_segments(
            [Segment("system", "电脑音频", 0.0, 12.0, source)]
        )

        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(chunk.source_text) <= 240 for chunk in chunks))
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


if __name__ == "__main__":
    unittest.main()
