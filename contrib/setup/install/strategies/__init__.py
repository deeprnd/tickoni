"""Strategy registry — imports all strategies to trigger @register decorators."""
from . import apt, pip, download, zig, python_script, build, none, llama_cpp  # noqa: F401
