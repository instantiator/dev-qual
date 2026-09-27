"""Fixture with deliberate ruff violations: bare except and a mutable default."""


def risky() -> None:
    """Swallow everything, badly."""
    try:
        pass
    except:
        pass


def bad_default(items=[]):
    """Use a mutable default argument, badly."""
    items.append(1)
    return items
