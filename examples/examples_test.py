#!/usr/bin/env python3
"""Unit tests for examples that run Flask applications."""

import json
import os
import shlex
import socket
import subprocess
import threading
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


def get_examples_dir() -> Path:
    """Locate the examples directory."""
    return Path(__file__).parent


def get_free_port() -> int:
    """Find a free port to use for testing."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        s.listen(1)
        port = s.getsockname()[1]
    return port


class FlaskExamplesTest(unittest.TestCase):
    """Test Flask example applications using bazel run."""

    # Track which examples were tested
    _tested_examples = set()

    # Lock to ensure tests run serially (they all use localhost:5000)
    _test_lock = threading.Lock()

    @classmethod
    def tearDownClass(cls):
        """Verify all example directories were tested."""
        examples_dir = get_examples_dir()

        # Find all example directories (subdirectories with BUILD.bazel)
        example_dirs = set()
        for path in examples_dir.iterdir():
            if not path.is_dir():
                continue
            # Skip hidden directories and __pycache__
            if path.name.startswith(".") or path.name == "__pycache__":
                continue
            # Only include directories with BUILD.bazel
            if (path / "BUILD.bazel").exists():
                example_dirs.add(path.name)

        # Check that all discovered examples were tested
        untested = example_dirs - cls._tested_examples
        if untested:
            raise AssertionError(
                f"The following example directories were not tested: {sorted(untested)}. "
                f"Please add tests for these examples."
            )

        # Check that we didn't test non-existent examples
        non_existent = cls._tested_examples - example_dirs
        if non_existent:
            raise AssertionError(
                f"Tests ran for non-existent examples: {sorted(non_existent)}"
            )

    def _run_flask_target(self, example: str, target: str) -> None:
        """Run a Flask target and verify it returns 'hello world!'."""
        # Use lock to ensure tests run serially
        with self.__class__._test_lock:
            # Record that this example was tested
            self.__class__._tested_examples.add(example)

            example_dir = get_examples_dir() / example
            self.assertTrue(
                example_dir.exists(), f"Example directory {example_dir} does not exist"
            )

            # Get a free port for this test
            port = get_free_port()

            startup_args = []

            if "BAZEL_STARTUP_FLAGS" in os.environ:
                startup_args.extend(shlex.split(os.environ["BAZEL_STARTUP_FLAGS"]))

            cmd = ["bazel"] + startup_args + ["run", target]
            print(f"Running command: {' '.join(cmd)} on port {port}")

            # Start the Flask server using bazel run with custom port
            env = os.environ.copy()
            env["FLASK_RUN_PORT"] = str(port)

            process = subprocess.Popen(
                cmd,
                cwd=example_dir,
                env=env,
            )

            logs = []

            try:
                # Verify the process is still running
                poll_result = process.poll()
                if poll_result is not None:
                    self.fail(
                        f"Process exited prematurely with code {poll_result}.\nPort: {port}\n"
                    )

                max_tries = 30
                for i in range(max_tries + 1):
                    try:
                        with urlopen(f"http://127.0.0.1:{port}", timeout=5) as response:
                            content = response.read().decode("utf-8")
                            self.assertEqual(
                                content,
                                "hello world!",
                                f"Expected 'hello world!' but got '{content}'",
                            )
                            return
                    except (HTTPError, URLError) as exc:
                        logs.append(str(exc))
                        if i < max_tries:
                            time.sleep(5)

            finally:
                # Clean up: terminate the process
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

                # Give the port time to be released before the next test
                time.sleep(1)

            self.fail(
                "Failed to fetch data from Flask app. Got the following exceptions:\n"
                + json.dumps(logs, indent=4)
            )

    def test_flask_pex_rules_venv(self) -> None:
        """Test the Flask PEX example in rules_venv."""
        self._run_flask_target("rules_venv", "//:flask_hello_world.pex")

    def test_flask_scie_rules_venv(self) -> None:
        """Test the Flask SCIE example in rules_venv."""
        self._run_flask_target("rules_venv", "//:flask_hello_world.scie")

    def test_flask_pex_rules_python(self) -> None:
        """Test the Flask PEX example in rules_python."""
        self._run_flask_target("rules_python", "//:flask_hello_world.pex")

    def test_flask_scie_rules_python(self) -> None:
        """Test the Flask SCIE example in rules_python."""
        self._run_flask_target("rules_python", "//:flask_hello_world.scie")

    def test_flask_pex_aspect_rules_py(self) -> None:
        """Test the Flask PEX example in aspect_rules_py."""
        self._run_flask_target("aspect_rules_py", "//:flask_hello_world.pex")

    def test_flask_scie_aspect_rules_py(self) -> None:
        """Test the Flask SCIE example in aspect_rules_py."""
        self._run_flask_target("aspect_rules_py", "//:flask_hello_world.scie")


if __name__ == "__main__":
    unittest.main()
