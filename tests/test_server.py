import asyncio
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import numpy as np

SPEC = importlib.util.spec_from_file_location("realtrans_soniox_server", Path(__file__).parents[1] / "server.py")
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


def test_pcm16_resamples_stereo_to_16khz_mono():
    audio = np.ones((4800, 2), dtype=np.float32) * 0.25
    result = server.pcm16(audio, 48000)
    assert len(result) == 1600 * 2
    assert np.frombuffer(result, dtype="<i2").mean() > 8000


def test_token_accumulator_pairs_original_translation_at_endpoint():
    acc = server.TokenAccumulator()
    source, translated, endpoint = acc.consume([
        {"text": "こんにちは", "is_final": True, "translation_status": "original"},
        {"text": "你好", "is_final": True, "translation_status": "translation"},
        {"text": "<end>", "is_final": True},
    ])
    assert (source, translated, endpoint) == ("こんにちは", "你好", True)
    assert acc.take(source, translated) == ("こんにちは", "你好")


def test_token_accumulator_replaces_nonfinal_preview():
    acc = server.TokenAccumulator()
    assert acc.consume([{"text": "こん", "is_final": False, "translation_status": "original"}])[0] == "こん"
    assert acc.consume([{"text": "こんにちは", "is_final": True, "translation_status": "original"}])[0] == "こんにちは"


def test_soniox_config_uses_japan_v5_translation_and_slow_endpoint():
    sent = []

    class FakeSocket:
        async def send(self, value):
            sent.append(value)

    async def fake_connect(url, **kwargs):
        assert url == server.ENDPOINTS["jp"]
        header = kwargs.get("additional_headers") or kwargs.get("extra_headers")
        assert header == {"Authorization": "Bearer snx_test"}
        return FakeSocket()

    class Core:
        session = None

    session = server.Session(Core(), {"api_key": "snx_test", "region": "jp", "mic_enabled": True})
    with patch.object(server.websockets, "connect", fake_connect):
        asyncio.run(session.connect_soniox())
    config = json.loads(sent[0])
    assert config["model"] == "stt-rt-v5"
    assert config["language_hints"] == ["ja"]
    assert config["translation"] == {"type": "one_way", "target_language": "zh"}
    assert config["endpoint_sensitivity"] < 0
    assert config["max_endpoint_delay_ms"] == 3000


def test_safe_error_redacts_api_key():
    assert "snx_secret" not in server.safe_error(RuntimeError("bad snx_secret"), "snx_secret")
