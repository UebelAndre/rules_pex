"""# rules_pex

Bazel rules for the Python executable packaging tool [pex](https://docs.pex-tool.org/).

## Setup

Below is an example of how to quickly setup toolchains which power the Pex rules. For details
on customizing toolchains, please see the [`pex`](#pex) module extension or
[`py_pex_toolchain`](#py_pex_toolchain) rule.

```python
bazel_dep(name = "rules_pex", version = "{version}")

pex = use_extension("@rules_pex//pex:extensions.bzl", "pex")
pex.toolchain(
    name = "pex_toolchains",
)

use_repo(
    pex,
    "pex_toolchains",
)

register_toolchains(
    "@pex_toolchains//:all",
)
```
"""

load(
    ":extensions.bzl",
    _pex = "pex",
)
load(
    ":py_pex_binary.bzl",
    _py_pex_binary = "py_pex_binary",
)
load(
    ":py_pex_toolchain.bzl",
    _py_pex_toolchain = "py_pex_toolchain",
)
load(
    ":py_scie_binary.bzl",
    _py_scie_binary = "py_scie_binary",
)

py_pex_binary = _py_pex_binary
py_scie_binary = _py_scie_binary
py_pex_toolchain = _py_pex_toolchain
pex = _pex
