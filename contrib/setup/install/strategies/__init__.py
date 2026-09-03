"""Strategy registry — imports all strategies to trigger @register decorators."""
from . import apt, pip, download, zig, python_script, build, none, llama_cpp_download, hf_model, openssl_build  # noqa: F401
