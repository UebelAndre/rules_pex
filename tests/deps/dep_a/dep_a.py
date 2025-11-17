"""A dependency module for testing."""

from typing import List


def get_messages() -> List[str]:
    """Return a list with one string."""
    return ["Message from dep_a"]
