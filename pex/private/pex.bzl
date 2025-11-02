"""Bazel rules for pex"""

load("@rules_python//python:py_info.bzl", "PyInfo")
load(":pex_resource_set.bzl", "get_pex_resource_set")
load(":pex_toolchain.bzl", "TOOLCHAIN_TYPE")

PyPexDepInfo = provider(
    doc = "Information collected about a target for Pex.",
    fields = {
        "data": "depset[File]: Runfiles excluding python sources.",
        "main": "Optional[File]: The main entrypoint for the target if it's a binary.",
    },
)

def _compute_main(label, srcs, main = None):
    """Determine the main entrypoint for executable rules.

    Args:
        label (label): The label of the srcs owner.
        srcs (list): A list of File objects.
        main (File, optional): An explicit contender for the main entrypoint.

    Returns:
        File: The file to use for the main entrypoint.
    """
    if main:
        if main not in srcs:
            fail("`main` was not found in `srcs`. Please add `{}` to `srcs` for {}".format(
                main.path,
                label,
            ))
        return main

    if len(srcs) == 1:
        main = srcs[0]
    else:
        for src in srcs:
            if main:
                fail("Multiple files match candidates for `main`. Please explicitly specify which to use for {}".format(
                    label,
                ))

            basename = src.basename[:-len(".py")]
            if basename == label.name:
                main = src

    if not main:
        fail("`main` and no `srcs` were specified. Please update {}".format(
            label,
        ))

    return main

def _py_pex_aspect_impl(target, ctx):
    main = None
    if hasattr(ctx.rule.file, "main"):
        main = _compute_main(target.label, ctx.rule.files.srcs, ctx.rule.file.main)

    data = [depset(getattr(ctx.rule.files, "data", []))]
    for target in getattr(ctx.rule.attr, "data", []):
        if DefaultInfo in target:
            data.extend([
                target[DefaultInfo].files,
                target[DefaultInfo].default_runfiles.files,
            ])

    for target in getattr(ctx.rule.attr, "deps", []):
        if PyPexDepInfo in target:
            data.append(target[PyPexDepInfo].data)

    return [PyPexDepInfo(
        main = main,
        data = depset(transitive = data),
    )]

_py_pex_aspect = aspect(
    doc = "An aspect used to collect arguments and environment variables from pex binaries.",
    implementation = _py_pex_aspect_impl,
    attr_aspects = ["deps"],
)

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _py_pex_binary_common(ctx, mnemonic, scie):
    """Implementation for py_pex_binary rule."""

    binary = ctx.attr.binary
    py_info = binary[PyInfo]
    dep_info = binary[PyPexDepInfo]

    files_to_run = binary[DefaultInfo].files_to_run

    # Get the Python runtime from toolchain
    py_toolchain = ctx.toolchains["@rules_python//python:toolchain_type"]
    py_runtime = py_toolchain.py3_runtime

    # Get the main entry point from PyMainInfo
    main_file = dep_info.main

    # Get the pex binary
    pex_toolchain = ctx.toolchains[TOOLCHAIN_TYPE]
    pex = pex_toolchain.pex

    platform = pex_toolchain.platform

    cpus = 1
    for tag in ctx.attr.tags:
        if tag.startswith("cpu:"):
            value = tag[len("cpu:"):]
            if value.isdigit():
                cpus = int(value)

    output_name = ctx.label.name

    # Create the pex file. Note that scie targets can have a `.pex`
    # extension but only the pex targets will enforce them.
    if scie:
        is_windows = py_runtime.interpreter.basename.endswith(".exe")
        if platform:
            is_windows = bool("windows" in platform)

        if is_windows and not output_name.endwith(".exe"):
            output_name = output_name + ".exe"
    elif not output_name.endswith(".pex"):
        output_name = output_name + ".pex"
    output = ctx.actions.declare_file(output_name)

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.use_param_file("@%s")
    args.add("--pex", pex)
    if scie:
        args.add("--scie")
        args.add("--scie_platform", platform)
        args.add("--scie_science", pex_toolchain.scie_science)
        args.add("--scie_jump", pex_toolchain.scie_jump)
        args.add("--scie_ptex", pex_toolchain.scie_ptex)
        args.add("--scie_python_archive", pex_toolchain.scie_python_interpreter)
        args.add("--scie_python_version", pex_toolchain.scie_python_version)
        args.add("--scie_cache_dir", pex_toolchain.scie_cache_dir.path)
    args.add("--output", output)
    args.add("--cpus", cpus)
    args.add("--main", _rlocationpath(main_file, ctx.workspace_name))
    args.add("--runfiles_manifest", files_to_run.runfiles_manifest)
    args.add("--workspace_name", ctx.workspace_name)
    args.add_all(py_info.imports, format_each = "--import=%s")

    input_files = [
        files_to_run.runfiles_manifest,
        files_to_run.repo_mapping_manifest,
    ]

    inputs = depset(
        input_files,
        transitive = [
            binary[DefaultInfo].default_runfiles.files,
        ],
    )

    tools = depset(transitive = [py_runtime.files, pex_toolchain.all_files])

    ctx.actions.run(
        mnemonic = mnemonic,
        executable = ctx.executable._process_wrapper,
        arguments = [args],
        inputs = inputs,
        outputs = [output],
        tools = tools,
        resource_set = get_pex_resource_set(cpus),
        env = ctx.configuration.default_shell_env,
    )

    return [
        DefaultInfo(
            executable = output,
            files = depset([output]),
            runfiles = ctx.runfiles(transitive_files = dep_info.data),
        ),
    ]

_COMMON_ATTRS = {
    "binary": attr.label(
        doc = "The `py_binary` target to convert to a Pex.",
        cfg = "target",
        executable = True,
        mandatory = True,
        providers = [PyInfo],
        aspects = [_py_pex_aspect],
    ),
    "_process_wrapper": attr.label(
        cfg = "exec",
        executable = True,
        default = Label("//pex/private:pex_process_wrapper"),
    ),
}

def _py_pex_binary_impl(ctx):
    return _py_pex_binary_common(
        ctx = ctx,
        mnemonic = "PyPex",
        scie = False,
    )

py_pex_binary = rule(
    implementation = _py_pex_binary_impl,
    doc = "A rule for creating pex executables from Python targets.",
    attrs = _COMMON_ATTRS,
    executable = True,
    toolchains = [
        TOOLCHAIN_TYPE,
        "@rules_python//python:toolchain_type",
    ],
)

def _py_scie_binary_impl(ctx):
    return _py_pex_binary_common(
        ctx = ctx,
        mnemonic = "PyPexScie",
        scie = True,
    )

py_scie_binary = rule(
    implementation = _py_scie_binary_impl,
    doc = "A rule for creating pex scie executables from Python targets.",
    attrs = _COMMON_ATTRS,
    executable = True,
    toolchains = [
        TOOLCHAIN_TYPE,
        "@rules_python//python:toolchain_type",
    ],
)
