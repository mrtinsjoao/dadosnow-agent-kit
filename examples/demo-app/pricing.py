"""Tiny demo module: price a cart with an optional discount code."""

DISCOUNTS = {"WELCOME10": 0.10, "VIP20": 0.20}


def cart_total(items, code=None):
    """Return the total of (price, quantity) pairs after an optional discount."""
    subtotal = sum(price * qty for price, qty in items)
    rate = DISCOUNTS.get(code, 0.0) if code else 0.0
    return round(subtotal * (1 - rate), 2)
