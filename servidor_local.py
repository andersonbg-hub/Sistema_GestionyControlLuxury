import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import subprocess
import webbrowser


class LuxuryHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def open_browser(url):
    for name in ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA"):
        folder = os.environ.get(name)
        if folder:
            executable = Path(folder) / "Google/Chrome/Application/chrome.exe"
            if executable.is_file():
                subprocess.Popen([str(executable), "--new-tab", url])
                return
    webbrowser.open(url)


def main():
    parser = argparse.ArgumentParser(description="Abre Luxury desde este equipo.")
    parser.add_argument("--puerto", type=int, default=8765)
    parser.add_argument("--sin-abrir", action="store_true")
    args = parser.parse_args()
    web = Path(__file__).resolve().with_name("web-conectado")
    if not (web / "index.html").exists():
        parser.exit(1, "Falta la compilación web. Consulta README.md.\n")
    handler = partial(LuxuryHandler, directory=web)
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.puerto), handler)
    except OSError:
        if args.sin_abrir:
            parser.exit(1, "El puerto está en uso. Prueba otro con --puerto.\n")
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    with server:
        url = f"http://127.0.0.1:{server.server_port}/"
        print(f"Luxury disponible en {url}", flush=True)
        if not args.sin_abrir:
            open_browser(url)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
