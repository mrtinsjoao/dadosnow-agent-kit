import unittest

from pricing import cart_total


class CartTotalTest(unittest.TestCase):
    def test_sums_price_times_quantity(self):
        self.assertEqual(cart_total([(10.0, 2), (5.5, 1)]), 25.5)

    def test_applies_known_discount_code(self):
        self.assertEqual(cart_total([(100.0, 1)], "VIP20"), 80.0)

    def test_ignores_unknown_code(self):
        self.assertEqual(cart_total([(100.0, 1)], "NOPE"), 100.0)


if __name__ == "__main__":
    unittest.main()
