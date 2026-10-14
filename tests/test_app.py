import unittest

from app import app


class AppTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_greeting(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_data(as_text=True), "Hello, World!\n")
        self.assertEqual(response.mimetype, "text/plain")

    def test_health(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {"status": "ok"})

    def test_unknown_route(self):
        self.assertEqual(self.client.get("/missing").status_code, 404)


if __name__ == "__main__":
    unittest.main()
