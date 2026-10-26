"""SonioxTrans: Japanese speech to Simplified Chinese subtitles."""
import asyncio
import contextlib
import inspect
import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
import queue
import re
import ssl

import certifi
import numpy as np
import sounddevice as sd
import websockets

LOG = logging.getLogger("sonioxtrans")
PORT = 8766
ENDPOINTS = {
    "jp": "wss://stt-rt.jp.soniox.com/transcribe-websocket",
    "us": "wss://stt-rt.soniox.com/transcribe-websocket",
}


def tls_context():
    context = ssl.create_default_context()
    context.load_verify_locations(cafile=certifi.where())
    return context


def safe_error(error, key=""):
    text = str(error) or type(error).__name__
    if key:
        text = text.replace(key, "[密钥已隐藏]")
    text = re.sub(r"snx_[A-Za-z0-9_.-]+", "[密钥已隐藏]", text)
    return text[:350]


def pcm16(audio, actual_rate):
    mono = np.mean(audio, axis=1) if audio.ndim == 2 else audio
    rate = int(round(actual_rate))
    if rate != 16000:
        # Linear interpolation is sufficient for live speech and avoids shipping
        # the large SciPy runtime solely for sample-rate conversion.
        output_count = max(1, round(len(mono) * 16000 / rate))
        source_positions = np.arange(len(mono), dtype=np.float64)
        target_positions = np.arange(output_count, dtype=np.float64) * rate / 16000
        mono = np.interp(target_positions, source_positions, mono)
    return (np.clip(mono, -1, 1) * 32767).astype("<i2").tobytes()


class Capture:
    def __init__(self, speaker):
        self.speaker = speaker
        self.stream = None
        self.queue = queue.Queue(maxsize=25)
        self.rate = None
        self.accepting = False
        self.dropped = 0
        self.overflow = False

    def open(self):
        devices = sd.query_devices()
        if self.speaker == "them":
            choices = [i for i, d in enumerate(devices)
                       if "BlackHole" in d["name"] and d["max_input_channels"] > 0]
            choices.sort(key=lambda i: "BlackHole 2ch" not in devices[i]["name"])
        else:
            choices = [i for i, d in enumerate(devices)
                       if d["max_input_channels"] > 0 and "BlackHole" not in d["name"]]
            default = sd.default.device[0]
            choices.sort(key=lambda i: i != default)
        if not choices:
            raise RuntimeError("未找到 BlackHole 输入" if self.speaker == "them" else "未找到麦克风")
        device = choices[0]
        info = devices[device]
        rate = float(info["default_samplerate"])
        channels = min(2 if self.speaker == "them" else 1, info["max_input_channels"])
        self.stream = sd.InputStream(device=device, samplerate=rate, channels=channels,
                                     dtype="float32", blocksize=round(rate / 10),
                                     callback=self._callback)
        self.rate = self.stream.samplerate
        LOG.info("audio %s device=%s rate=%s channels=%s -> PCM16/16000",
                 self.speaker, info["name"], self.rate, channels)

    def _callback(self, data, frames, time_info, status):
        if not self.accepting:
            return
        if status:
            self.overflow = True
        try:
            self.queue.put_nowait(data.copy())
        except queue.Full:
            self.dropped += 1

    def start(self):
        self.accepting = True
        self.stream.start()

    def close(self):
        self.accepting = False
        if self.stream is not None:
            stream, self.stream = self.stream, None
            try:
                stream.abort()
            finally:
                stream.close()


class TokenAccumulator:
    def __init__(self):
        self.original = ""
        self.translation = ""

    @staticmethod
    def _kind(token):
        value = token.get("translation_status")
        return "translation" if value == "translation" else "original"

    def consume(self, tokens):
        nonfinal = {"original": "", "translation": ""}
        endpoint = False
        for token in tokens or []:
            text = token.get("text", "")
            if text in ("<end>", "<fin>"):
                if token.get("is_final"):
                    endpoint = True
                continue
            if not text:
                continue
            kind = self._kind(token)
            if token.get("is_final"):
                if kind == "translation":
                    self.translation += text
                else:
                    self.original += text
            else:
                nonfinal[kind] += text
        return self.original + nonfinal["original"], self.translation + nonfinal["translation"], endpoint

    def take(self, preview_original="", preview_translation=""):
        source = (preview_original or self.original).strip()
        translated = (preview_translation or self.translation).strip()
        self.original = ""
        self.translation = ""
        return source, translated


class Session:
    def __init__(self, core, params):
        self.core = core
        self.key = str(params.get("api_key", "")).strip()
        self.region = params.get("region", "jp")
        self.inputs = [name for name, enabled in (
            ("me", params.get("mic_enabled", True)),
            ("them", params.get("sys_enabled", False))) if enabled]
        self.captures = []
        self.sockets = []
        self.tasks = set()
        self.closed = False
        self.enabled = {name: True for name in self.inputs}
        self.accumulators = {name: TokenAccumulator() for name in self.inputs}

    async def status(self, text):
        if self.core.session is self and not self.closed:
            await self.core.status(text)

    async def subtitle(self, speaker, source, translated, final=False):
        if self.core.session is self and not self.closed:
            await self.core.broadcast({"type": "subtitle", "speaker": speaker,
                "source": source, "translated": translated, "is_final": final})

    def track(self, coro):
        task = asyncio.create_task(coro)
        self.tasks.add(task)
        return task

    async def run(self):
        error = None
        try:
            if not self.key:
                raise RuntimeError("请先填写 Soniox API Key")
            if self.region not in ENDPOINTS:
                raise RuntimeError("无效 Soniox 服务地域")
            if not self.inputs:
                raise RuntimeError("请至少启用一个音频输入")
            await self.status("正在检查音频设备…")
            for speaker in self.inputs:
                capture = Capture(speaker)
                self.captures.append(capture)
                capture.open()
            for capture in self.captures:
                await self.status("正在连接 Soniox 日本实时翻译…" if self.region == "jp" else "正在连接 Soniox 实时翻译…")
                ws = await self.connect_soniox()
                capture.start()
                self.track(self.send_audio(capture, ws))
                self.track(self.receive_tokens(capture.speaker, ws))
            await self.status("Soniox stt-rt-v5 翻译中：日语 → 中文")
            done, _ = await asyncio.wait(list(self.tasks), return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
            raise RuntimeError("Soniox 连接结束，请重新开始")
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            error = safe_error(exc, self.key)
            LOG.error("session failed: %s", error)
        finally:
            cleanup = asyncio.create_task(self.close())
            try:
                await asyncio.shield(cleanup)
            except asyncio.CancelledError:
                await cleanup
                raise
            if error and self.core.session is self:
                await self.core.status("启动或识别失败：" + error)

    async def connect_soniox(self):
        kwargs = {"open_timeout": 12, "close_timeout": 2, "ping_interval": 20,
                  "ssl": tls_context()}
        header_arg = "additional_headers" if "additional_headers" in inspect.signature(websockets.connect).parameters else "extra_headers"
        kwargs[header_arg] = {"Authorization": "Bearer " + self.key}
        ws = await websockets.connect(ENDPOINTS[self.region], **kwargs)
        self.sockets.append(ws)
        config = {
            "model": "stt-rt-v5",
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "language_hints": ["ja"],
            "enable_language_identification": True,
            "enable_endpoint_detection": True,
            "endpoint_sensitivity": -0.25,
            "endpoint_latency_adjustment_level": 0,
            "max_endpoint_delay_ms": 3000,
            "translation": {"type": "one_way", "target_language": "zh"},
            "client_reference_id": "sonioxtrans-macos",
        }
        await ws.send(json.dumps(config))
        LOG.info("Soniox connected region=%s model=stt-rt-v5", self.region)
        return ws

    async def send_audio(self, capture, ws):
        blocks = 0
        while True:
            try:
                audio = capture.queue.get_nowait()
            except queue.Empty:
                await asyncio.sleep(0.01)
                continue
            if not self.enabled[capture.speaker]:
                audio = np.zeros_like(audio)
            blocks += 1
            if blocks == 1 or blocks % 100 == 0:
                LOG.info("audio %s rms=%.5f dropped=%s overflow=%s", capture.speaker,
                         float(np.sqrt(np.mean(audio ** 2))), capture.dropped, capture.overflow)
            await asyncio.wait_for(ws.send(pcm16(audio, capture.rate)), timeout=5)

    async def receive_tokens(self, speaker, ws):
        accumulator = self.accumulators[speaker]
        async for message in ws:
            data = json.loads(message)
            if data.get("error_code"):
                raise RuntimeError("Soniox %s: %s" % (
                    data.get("error_type", data.get("error_code")),
                    data.get("error_message", "服务错误")))
            if data.get("finished"):
                raise RuntimeError("Soniox 流已结束，请重新开始")
            if not self.enabled[speaker]:
                continue
            source, translated, endpoint = accumulator.consume(data.get("tokens", []))
            if source or translated:
                await self.subtitle(speaker, source, translated or "翻译中…", False)
            if endpoint:
                source, translated = accumulator.take(source, translated)
                if source:
                    await self.subtitle(speaker, source, translated or "（未返回译文）", True)
                    LOG.info("endpoint speaker=%s source_chars=%s translated_chars=%s",
                             speaker, len(source), len(translated))
        raise RuntimeError("Soniox WebSocket 已断开")

    async def close(self):
        if self.closed:
            return
        self.closed = True
        for capture in self.captures:
            with contextlib.suppress(Exception):
                capture.close()
        tasks = list(self.tasks)
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        self.tasks.clear()
        for ws in self.sockets:
            with contextlib.suppress(Exception):
                await asyncio.wait_for(ws.send(""), timeout=1)
            with contextlib.suppress(Exception):
                await asyncio.wait_for(ws.close(), timeout=3)
        LOG.info("session resources closed")


class Core:
    def __init__(self):
        self.clients = set()
        self.session = None
        self.task = None
        self.message = "就绪：Soniox 日语 → 中文"
        self.lock = asyncio.Lock()

    async def broadcast(self, message):
        encoded = json.dumps(message, ensure_ascii=False)
        async def send(client):
            try:
                await asyncio.wait_for(client.send(encoded), timeout=2)
            except Exception:
                self.clients.discard(client)
        await asyncio.gather(*(send(client) for client in list(self.clients)))

    async def status(self, message):
        self.message = message
        LOG.info("status: %s", message)
        await self.broadcast({"type": "status", "message": message})

    async def start(self, params):
        async with self.lock:
            if self.task and not self.task.done():
                await self.broadcast({"type": "status", "message": self.message + "（已启动，请勿重复点击）"})
                return
            self.session = Session(self, params)
            await self.status("正在启动 Soniox…")
            self.task = asyncio.create_task(self.session.run())

    async def stop(self):
        async with self.lock:
            if self.task and not self.task.done():
                self.task.cancel()
                await asyncio.gather(self.task, return_exceptions=True)
            self.task = None
            self.session = None
            await self.status("已停止")

    async def handler(self, websocket):
        self.clients.add(websocket)
        LOG.info("UI connected")
        try:
            async for raw in websocket:
                try:
                    message = json.loads(raw)
                    action = message.get("action")
                    params = message.get("params", {})
                    if not isinstance(params, dict):
                        raise ValueError("invalid parameters")
                    if action != "update_settings":
                        LOG.info("UI action=%s", action)
                    if action == "start":
                        await self.start(params)
                    elif action == "stop":
                        await self.stop()
                    elif action == "status":
                        await websocket.send(json.dumps({"type": "status", "message": self.message}, ensure_ascii=False))
                    elif action == "update_settings" and self.session:
                        for speaker, key in [("me", "mic_enabled"), ("them", "sys_enabled")]:
                            if speaker in self.session.enabled and key in params:
                                self.session.enabled[speaker] = bool(params[key])
                except (ValueError, TypeError, AttributeError):
                    await websocket.send(json.dumps({"type": "status", "message": "无效客户端指令"}, ensure_ascii=False))
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.clients.discard(websocket)
            if not self.clients:
                await self.stop()
            LOG.info("UI disconnected")


def configure_logging():
    directory = Path.home() / "Library" / "Logs" / "SonioxTrans"
    directory.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(directory / "backend.log", maxBytes=2_000_000,
                                  backupCount=2, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    LOG.addHandler(handler)
    LOG.setLevel(logging.INFO)


async def main():
    configure_logging()
    core = Core()
    LOG.info("SonioxTrans starting localhost:%s", PORT)
    async with websockets.serve(core.handler, "127.0.0.1", PORT):
        try:
            await asyncio.Future()
        finally:
            await core.stop()


if __name__ == "__main__":
    import sys
    if "--self-test" in sys.argv:
        context = tls_context()
        assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
        assert ENDPOINTS["jp"] == "wss://stt-rt.jp.soniox.com/transcribe-websocket"
        print("SonioxTrans TLS and endpoint configuration OK")
    else:
        asyncio.run(main())
