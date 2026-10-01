# Third-party notices

ImageGen is MIT licensed (see [LICENSE](LICENSE)). The MIT license covers the code in this
repository only. It does not cover model weights or the Python packages the engine installs.

## Bundled in ImageGen.app

| Component | License | Notes |
| --- | --- | --- |
| [uv](https://github.com/astral-sh/uv) by Astral Software Inc. | MIT OR Apache-2.0 | Copied into `Contents/Resources/bin/uv` by the build script. License texts ship in `Contents/Resources/licenses/uv/` and live in [`third_party/uv/`](third_party/uv). |

## Installed on your Mac at first launch (not redistributed)

The app runs `uv sync` against [`backend/uv.lock`](backend/uv.lock), which downloads these packages
from PyPI and GitHub onto your machine. This repository does not include them.

| Package | License |
| --- | --- |
| torch, torchvision | BSD-3-Clause |
| diffusers, transformers, accelerate, safetensors, huggingface-hub | Apache-2.0 |
| pillow | MIT-CMU (HPND) |
| fastapi, mcp | MIT |
| httpx, uvicorn | BSD-3-Clause |

Their dependencies are all permissive (MIT, BSD, Apache-2.0, ISC, PSF). certifi and tqdm are MPL-2.0.
No GPL, LGPL or AGPL packages are used.

## Models

Models are downloaded by you, from Hugging Face, inside the app. They are not part of this repository
or the app bundle, and each one has its own license.

| Model | License |
| --- | --- |
| [Qwen-Image 2.1](https://huggingface.co/Qwen/Qwen-Image-2.1) by the Qwen team | [Qwen Research License Agreement](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE). Non-commercial (research and evaluation) use only. Commercial use needs a separate license from Qwen. |

Qwen is licensed under the Qwen RESEARCH LICENSE AGREEMENT, Copyright (c) 2026 Hangzhou Tongyi
Laboratory Technology Co., Ltd. All Rights Reserved.
