#!/home/armoji/.local/share/control-room/venv/bin/python3
# Wake-word ("hey claude") voice control for the control-room TV. Always
# listening on the default mic; energy-based VAD segments speech, faster-whisper
# transcribes locally (nothing leaves the machine until the actual Claude
# Code call), and only utterances containing the wake phrase get forwarded
# to `claude -p`. Deliberately NOT run with --permission-mode plan — that
# hangs forever in headless -p mode (see ask_claude()). Plain default mode
# already blocks genuinely destructive actions via its own sandbox policy.
import os
import re
import subprocess
import sys
import time
import queue
import threading

import numpy as np
import sounddevice as sd
from faster_whisper import WhisperModel

RATE = 16000
BLOCK_SIZE = 480  # 30ms @ 16kHz
MIN_SPEECH_BLOCKS = 4       # ~120ms of signal before we count it as speech
END_SILENCE_BLOCKS = 24     # ~720ms of quiet ends an utterance
MAX_UTTER_BLOCKS = 500      # ~15s hard cap per utterance
WAKE_LISTEN_TIMEOUT = 10    # seconds to wait for a command after the wake word
CALIBRATE_SECONDS = 1.0
MODEL_SIZE = "base.en"

VENV_DIR = os.path.expanduser("~/.local/share/control-room")
PIPER_BIN = os.path.join(VENV_DIR, "venv", "bin", "piper")
PIPER_MODEL = os.path.join(VENV_DIR, "voices", "en_US-lessac-medium.onnx")
TTS_SINK = "control_room_tts"

# Set while Claude's reply is being spoken — the mic callback drops audio
# during this window so the TV's own speech played back through the room
# doesn't get picked up as a new (possibly self-triggering) utterance.
speaking = threading.Event()

WAKE_PATTERNS = [
    re.compile(r"\bhey,?\s+claude\b", re.I),
    re.compile(r"\bhi,?\s+claude\b", re.I),
    re.compile(r"\bok,?\s+claude\b", re.I),
    re.compile(r"\bokay,?\s+claude\b", re.I),
]

WORKDIR = os.path.expanduser("~/.local/state/control-room-voice")
os.makedirs(WORKDIR, exist_ok=True)
os.chdir(WORKDIR)

CYAN, YELLOW, GREEN, DIM, RESET = "\033[36m", "\033[33m", "\033[32m", "\033[2m", "\033[0m"


def log(msg):
    print(f"{DIM}[control-room-voice] {msg}{RESET}", flush=True)


q = queue.Queue()


def audio_cb(indata, frames, time_info, status):
    if status:
        pass  # drop overflow/underflow notices, not actionable here
    if speaking.is_set():
        return  # don't let Claude's own voice re-trigger the mic
    q.put(indata[:, 0].copy())


def rms(block):
    return float(np.sqrt(np.mean(np.square(block.astype(np.float64)))))


def calibrate():
    log(f"calibrating mic noise floor ({CALIBRATE_SECONDS:.0f}s, stay quiet)...")
    n_blocks = int(CALIBRATE_SECONDS * RATE / BLOCK_SIZE)
    levels = []
    for _ in range(n_blocks):
        levels.append(rms(q.get() * 32768.0))
    floor = float(np.mean(levels)) if levels else 50.0
    threshold = max(150.0, floor * 4.0)
    log(f"noise floor {floor:.0f}, speech threshold {threshold:.0f}")
    return threshold


def capture_utterance(threshold, start_timeout=None):
    """Collect one silence-terminated utterance. Returns float32 mono audio,
    or None if start_timeout elapses with no speech detected."""
    voiced = []
    silence_run = 0
    speech_started = False
    speech_blocks = 0
    deadline = time.monotonic() + start_timeout if start_timeout else None

    while True:
        if deadline and not speech_started:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            try:
                block = q.get(timeout=remaining)
            except queue.Empty:
                return None
        else:
            block = q.get()

        level = rms(block * 32768.0)
        if level > threshold:
            speech_blocks += 1
            silence_run = 0
            voiced.append(block)
            if speech_blocks >= MIN_SPEECH_BLOCKS:
                speech_started = True
        elif speech_started:
            silence_run += 1
            voiced.append(block)
            if silence_run >= END_SILENCE_BLOCKS:
                break
        else:
            speech_blocks = 0
            voiced = []

        if len(voiced) >= MAX_UTTER_BLOCKS:
            break

    if not speech_started:
        return None
    return np.concatenate(voiced)


def transcribe(model, audio):
    if audio is None or len(audio) < RATE * 0.2:
        return ""
    segments, _ = model.transcribe(audio, language="en", beam_size=1, vad_filter=False)
    return " ".join(seg.text.strip() for seg in segments).strip()


def strip_wake(text):
    for pat in WAKE_PATTERNS:
        text = pat.sub("", text)
    return text.strip(" ,.-")


def has_wake(text):
    return any(pat.search(text) for pat in WAKE_PATTERNS)


def clean_for_speech(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.S)   # code blocks
    text = re.sub(r"`([^`]*)`", r"\1", text)              # inline code
    text = re.sub(r"[*_#>~]", "", text)                   # markdown punctuation
    text = re.sub(r"https?://\S+", "link", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def speak(text):
    text = clean_for_speech(text)
    if not text or not os.path.exists(PIPER_MODEL):
        return
    speaking.set()
    try:
        # Synthesize to completion first, THEN play the whole buffer in one
        # go — piping piper straight into paplay live sounds fine for about
        # a second and then turns to garbage, because piper doesn't
        # generate audio at a steady real-time rate (it's fast in bursts,
        # per-sentence) and paplay drains its buffer faster than piper can
        # refill it, causing an underrun that sounds like static/garble.
        # Buffering the full reply first removes any timing dependency.
        result = subprocess.run(
            [PIPER_BIN, "-m", PIPER_MODEL, "--output-raw"],
            input=text.encode("utf-8"),
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["paplay", f"--device={TTS_SINK}", "--raw",
             "--rate=22050", "--channels=1", "--format=s16le"],
            input=result.stdout, stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        log(f"tts failed: {e}")
    finally:
        time.sleep(0.3)  # let room echo settle before the mic listens again
        speaking.clear()


CLAUDE_TIMEOUT = 90  # seconds — hard backstop so a bad response never wedges the pane forever

# Without this, a fresh session tends to hedge on action requests (respond
# with a plan/explanation instead of just doing it, or refuse outright) —
# it has no other context here for who's asking or whether it's safe to
# act. Genuinely destructive stuff is still caught by the normal sandbox
# regardless of this prompt (tested: a delete request was blocked cleanly).
VOICE_SYSTEM_PROMPT = (
    "You are a voice assistant on a control-room TV, triggered by Armin saying "
    "\"hey claude\" and speaking a command, transcribed via local speech-to-text. "
    "Just do what's asked directly instead of proposing a plan or asking for "
    "confirmation — there's no one available to approve one, this is a headless "
    "session. Keep replies short and conversational, since they'll be read aloud "
    "by text-to-speech."
)


def ask_claude(prompt, first_turn):
    print(f"{YELLOW}You:{RESET} {prompt}", flush=True)
    # NOTE: no --permission-mode plan here on purpose. Plan mode hangs
    # forever in headless -p sessions — it finishes planning and then
    # waits for an interactive approval handoff (ExitPlanMode) that can
    # never come with no user attached, confirmed directly: even a
    # read-only "list the files" prompt hung until killed. Default
    # headless mode already has real guardrails of its own (tested: a
    # delete request was cleanly blocked by the sandbox policy with an
    # explanation, not silently run) while still actually completing
    # normal tasks like creating a file or running a command.
    cmd = ["claude", "-p", "--append-system-prompt", VOICE_SYSTEM_PROMPT]
    if not first_turn:
        cmd.append("-c")
    cmd.append(prompt)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=CLAUDE_TIMEOUT)
        reply = result.stdout.strip() or result.stderr.strip()
    except subprocess.TimeoutExpired:
        reply = "Sorry, that took too long and I gave up on it."
    print(f"{GREEN}Claude:{RESET} {reply}", flush=True)
    print(flush=True)
    speak(reply)


def main():
    log(f"loading whisper model ({MODEL_SIZE})...")
    model = WhisperModel(MODEL_SIZE, device="cpu", compute_type="int8")

    stream = sd.InputStream(
        samplerate=RATE, channels=1, blocksize=BLOCK_SIZE,
        dtype="float32", callback=audio_cb,
    )
    stream.start()

    threshold = calibrate()
    first_turn = True
    log('listening for "hey claude"...')

    while True:
        audio = capture_utterance(threshold)
        text = transcribe(model, audio)
        if not text or not has_wake(text):
            continue

        print(f"\n{CYAN}> wake word:{RESET} {text}", flush=True)
        command = strip_wake(text)

        if len(command) < 3:
            log("listening for your command...")
            cmd_audio = capture_utterance(threshold, start_timeout=WAKE_LISTEN_TIMEOUT)
            if cmd_audio is None:
                log("no command heard, back to listening")
                continue
            command = transcribe(model, cmd_audio)

        if not command:
            log("didn't catch a command, back to listening")
            continue

        ask_claude(command, first_turn)
        first_turn = False
        log('listening for "hey claude"...')


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
