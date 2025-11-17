"""A dependency module for testing."""

from typing import List

from tests.deps.dep_c.dep_c import get_messages as get_messages_c


def get_messages() -> List[str]:
    """Return a list, always adds a special string and extends the same function from dep_c."""
    messages = ["Special message from dep_b"]
    messages.extend(get_messages_c())
    return messages
