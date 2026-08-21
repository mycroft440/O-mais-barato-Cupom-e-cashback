import os
import unittest
from unittest.mock import patch

from backend.main import equivalent, group_equivalent, magalu_url, winner


class ComparisonTests(unittest.TestCase):
    def test_gtin_groups_same_product_across_marketplaces(self):
        amazon = {
            "name": "Samsung Galaxy S24 256GB",
            "brand": "Samsung",
            "external_ids": {"ean": ["7892509135123"]},
        }
        mercado_livre = {
            "name": "Smartphone Samsung Galaxy S24 256 GB 5G",
            "brand": "Samsung",
            "external_ids": {"gtin": "7892509135123"},
        }
        self.assertTrue(equivalent(amazon, mercado_livre))

    def test_different_models_are_not_grouped(self):
        a = {"name": "Tênis Nike Revolution 7", "brand": "Nike", "external_ids": {}}
        b = {"name": "Tênis Nike Revolution 6", "brand": "Nike", "external_ids": {}}
        self.assertFalse(equivalent(a, b))

    def test_cheapest_wins_even_with_small_difference(self):
        offers = [
            {
                "id": "a",
                "name": "Tênis Nike Revolution 7",
                "brand": "Nike",
                "marketplace": "Amazon",
                "price": 95,
                "comparison_price": None,
                "compared_listings": 1,
                "popularity_score": 50,
                "external_ids": {},
            },
            {
                "id": "b",
                "name": "Nike Tênis Revolution 7",
                "brand": "Nike",
                "marketplace": "Shopee",
                "price": 100,
                "comparison_price": None,
                "compared_listings": 1,
                "popularity_score": 80,
                "external_ids": {},
            },
        ]
        groups = group_equivalent(offers)
        self.assertEqual(len(groups), 1)
        result = winner(groups[0])
        self.assertEqual(result["id"], "a")
        self.assertEqual(result["price"], 95)
        self.assertEqual(result["compared_listings"], 2)
        self.assertAlmostEqual(result["savings_vs_peers_percent"], 5.0)

    def test_magalu_partner_url_uses_store_slug(self):
        with patch.dict(os.environ, {"MAGALU_STORE_SLUG": "minhaloja"}, clear=False):
            converted = magalu_url("https://www.magazineluiza.com.br/produto-x/p/123456/")
        self.assertIn("magazinevoce.com.br/minhaloja/", converted)
        self.assertIn("produto-x/p/123456", converted)


if __name__ == "__main__":
    unittest.main()
