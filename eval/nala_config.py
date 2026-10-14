"""Settings shared by the eval tools.

The settings live in eval/config.env (copy config.example.env to start). A NALA_ variable
that is already set in the environment wins over the file, so the shell scripts, which
source the file and export it, and the Python scripts always agree.
"""

from __future__ import annotations

import os
import shlex

HERE = os.path.dirname(os.path.abspath(__file__))


def _load() -> dict[str, str]:
    path = os.environ.get("NALA_EVAL_CONFIG", os.path.join(HERE, "config.env"))
    values: dict[str, str] = {}
    if os.path.exists(path):
        with open(path) as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, raw = line.partition("=")
                values[key.strip()] = " ".join(shlex.split(raw, comments=True))
    values.update({key: value for key, value in os.environ.items() if key.startswith("NALA_")})
    return values


VALUES = _load()


def get(key: str, default: str = "") -> str:
    return VALUES.get(key) or default


def path(key: str, default: str = "") -> str:
    """A folder setting, with ~ expanded. Empty when unset and no default is given."""
    value = get(key, default)
    return os.path.abspath(os.path.expanduser(value)) if value else ""


def folders(key: str, default: str = "") -> list[str]:
    """A colon-separated list of folders, with ~ expanded."""
    return [os.path.abspath(os.path.expanduser(item)) for item in get(key, default).split(":") if item]


def words(key: str, default: str = "") -> list[str]:
    """A space-separated list."""
    return get(key, default).split()
