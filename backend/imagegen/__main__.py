import argparse
import logging

import uvicorn

from . import settings


def main() -> None:
    parser = argparse.ArgumentParser(description="ImageGen engine")
    parser.add_argument("--host", default=settings.HOST)
    parser.add_argument("--port", type=int, default=settings.PORT)
    args = parser.parse_args()
    settings.HOST, settings.PORT = args.host, args.port

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("httpx").setLevel(logging.WARNING)

    from .app import api

    uvicorn.run(api, host=args.host, port=args.port, log_level="warning")


if __name__ == "__main__":
    main()
