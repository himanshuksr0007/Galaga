"""Own one private frozen frame and the work requested on it over stdin."""

import ctypes
import json
import os
import signal
import subprocess
import sys
from pathlib import Path

libc = ctypes.CDLL(None)


def send(**fields):
    print(json.dumps(fields), flush=True)


def run(args, *, data=None, stdout=subprocess.PIPE, timeout=30):
    parent = os.getpid()

    def die_with_worker():
        # Quickshell may kill a Process immediately when its loader is destroyed.
        # The OCR and capture tools must also stop in that case.
        if libc.prctl(1, signal.SIGKILL, 0, 0, 0) or os.getppid() != parent:
            os._exit(1)

    # Kill and reap even if the overlay closes mid-capture or mid-recognition.
    with subprocess.Popen(
        args,
        stdin=subprocess.PIPE,
        stdout=stdout,
        stderr=subprocess.DEVNULL,
        preexec_fn=die_with_worker,
    ) as process:
        try:
            output, _ = process.communicate(data, timeout=timeout)
        finally:
            if process.poll() is None:
                process.kill()
        if process.returncode:
            raise RuntimeError(f"{Path(args[0]).name} failed")
        return output


def recognise(frame, language):
    raw = run(
        ["tesseract", str(frame), "stdout", "-l", language, "tsv"]
    ).decode()
    words = []
    for row in raw.splitlines()[1:]:
        cols = row.split("\t", 11)
        if len(cols) == 12 and cols[0] == "5" and cols[11].strip():
            left, top, width, height = map(int, cols[6:10])
            words.append(
                {
                    "x": left,
                    "y": top,
                    "w": width,
                    "h": height,
                    "line": cols[1:5],
                    "text": cols[11],
                }
            )
            if len(words) > 6000:
                raise ValueError("too many words on this display")
    return words


def inspect():
    pointer = json.loads(run(["hyprctl", "-j", "cursorpos"]))
    monitors = json.loads(run(["hyprctl", "-j", "monitors"]))

    def contains(m):
        w, h = m["width"], m["height"]
        if m["transform"] % 2:
            w, h = h, w
        return (
            0 <= pointer["x"] - m["x"] < w / m["scale"]
            and 0 <= pointer["y"] - m["y"] < h / m["scale"]
        )

    screen = next((m for m in monitors if contains(m)), None)
    if not screen:
        raise ValueError("no output at pointer")
    # The kernel frees this frame even after SIGKILL. Qt's image reader and
    # Tesseract can open its procfs handle while this session owns the descriptor.
    with os.fdopen(os.memfd_create("galaga-inspect"), "wb") as handle:
        frame = Path(f"/proc/{os.getpid()}/fd/{handle.fileno()}")
        run(["grim", "-t", "ppm", "-o", screen["name"], "-"], stdout=handle)
        send(frame=frame.as_uri(), output=screen["name"])
        handlers = {}
        languages = [
            name
            for name in run(["tesseract", "--list-langs"]).decode().splitlines()[1:]
            if name and name != "osd"
        ]
        if not languages:
            raise ValueError("install a Tesseract language pack")
        for scheme in ("mailto", "tel"):
            try:
                handlers[scheme] = bool(
                    run(
                        [
                            "xdg-mime",
                            "query",
                            "default",
                            "x-scheme-handler/" + scheme,
                        ]
                    ).strip()
                )
            except (OSError, RuntimeError, subprocess.TimeoutExpired):
                handlers[scheme] = False
        send(languages=languages, handlers=handlers)
        send(words=recognise(frame, "eng" if "eng" in languages else languages[0]))
        for line in sys.stdin:
            language = json.loads(line)["language"]
            if language not in languages:
                raise ValueError("language pack unavailable")
            send(words=recognise(frame, language))


if __name__ == "__main__":

    def stop(*_):
        raise SystemExit

    signal.signal(signal.SIGTERM, stop)
    try:
        inspect()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        send(
            error=str(error)
            if isinstance(error, (ValueError, RuntimeError))
            else "capture or recognition unavailable"
        )
