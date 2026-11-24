"""Freeze each output before mapping the picker. Requests use output-local fractions."""
import json
import os
import subprocess
import sys
from contextlib import ExitStack

from pixels import aperture, encode_colour, loupe, png


def emit(**fields):
    print(json.dumps(fields), flush=True)


class Frame:
    def __init__(self, file, monitor):
        self.file = file
        subprocess.run(["grim", "-s", str(monitor["scale"]), "-o", monitor["name"],
                        "-t", "ppm", "-"], stdout=file, check=True, timeout=8)
        file.seek(0)
        tokens = []
        while len(tokens) < 4:
            line = file.readline(1024)
            if not line:
                raise ValueError("incomplete output capture")
            tokens.extend(line.partition(b"#")[0].split())
        if len(tokens) != 4 or tokens[0] != b"P6" or tokens[3] != b"255":
            raise ValueError("unsupported output capture")
        self.width, self.height = map(int, tokens[1:3])
        self.offset = file.tell()
        if os.fstat(file.fileno()).st_size - self.offset != self.width*self.height*3:
            raise ValueError("incomplete output capture")
        self.url = f"file:///proc/{os.getpid()}/fd/{file.fileno()}"

    def read(self, x, y, count):
        return os.pread(self.file.fileno(), count*3, self.offset+(y*self.width+x)*3)

    def sample(self, request):
        x = max(0, min(self.width-1, int(request["x"]*self.width)))
        y = max(0, min(self.height-1, int(request["y"]*self.height)))
        size = request["size"]
        if size not in (1, 3, 5):
            raise ValueError("invalid aperture")
        rgb, footprint = aperture(self.read, self.width, self.height, x, y, size)
        return dict(rgb=encode_colour(rgb, request["space"]), swatch=encode_colour(rgb,"capture"),
                    tile=loupe(self.read,self.width,self.height,x,y), x=x,y=y,footprint=footprint)


def clipboard(reading, request):
    rgb = bytes(reading["rgb"])
    image = request["copy"] == "image"
    if image:
        payload = png(64,64,rgb*(64*64),request["space"])
    elif request["hex"]:
        # Keep the quick picker's clipboard contract: a directly pasteable hex value.
        prefix = "Adobe RGB " if request["space"] == "Adobe RGB" else ""
        payload = (prefix+"#"+rgb.hex().upper()).encode()
    else:
        payload = (request["space"]+" ("+" ".join(map(str,rgb))+")").encode()
    subprocess.run(["wl-copy","--type","image/png" if image else "text/plain;charset=utf-8"],
                   input=payload, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=4)


def main():
    monitors = json.loads(subprocess.check_output(["hyprctl","-j","monitors"], timeout=3))
    with ExitStack() as stack:
        frames = {}
        for monitor in monitors:
            if monitor.get("disabled") or monitor.get("mirrorOf","none") != "none":
                continue
            file = stack.enter_context(os.fdopen(os.memfd_create("galaga-picker"), "w+b"))
            frames[monitor["name"]] = Frame(file, monitor)
        if not frames:
            raise ValueError("no output available")
        cursor = json.loads(subprocess.check_output(["hyprctl","-j","cursorpos"], timeout=3))
        emit(frames={name:f.url for name,f in frames.items()}, cursor=cursor)
        for line in sys.stdin:
            request = json.loads(line)
            reading = frames[request["output"]].sample(request)
            if request.get("copy"):
                try:
                    clipboard(reading,request)
                    emit(copied=True)
                except (OSError, subprocess.SubprocessError):
                    emit(copyError=True)
            else:
                emit(output=request["output"], reading=reading)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError):
        emit(error="could not capture the display")
