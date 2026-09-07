import unittest

from main import (
    _calculate_monthly_forecast,
    _detect_statement_type,
    _extract_transactions_from_words,
    _normalize_statement_signs,
    _normalize_transaction_type,
    _validate_transaction_dates,
    parse_transactions_from_text,
)


class ForecastLogicTests(unittest.TestCase):
    def test_rising_trend_increases_prediction(self):
        result = _calculate_monthly_forecast({
            "2024-01": 1200,
            "2024-02": 1400,
            "2024-03": 1600,
            "2024-04": 1800,
        })

        self.assertGreater(result["predicted_expense"], 1500)
        self.assertGreater(result["confidence"], 60)

    def test_empty_dataset_returns_zero(self):
        result = _calculate_monthly_forecast({})
        self.assertEqual(result["predicted_expense"], 0)
        self.assertEqual(result["confidence"], 0)

    def test_bank_debit_titles_are_negative_even_when_amount_is_positive(self):
        items = [
            {"title": "Gider Transfer, Eylem Karakazan", "amount": 30000.0},
            {"title": "Gelir Transfer, Sadık Karakazan", "amount": 5000.0},
            {"title": "Ödeme, Enpara.com kredi kartı ödemesi", "amount": 11501.53},
        ]

        result = _normalize_statement_signs(items, "bank")

        self.assertEqual(result[0]["amount"], -30000.0)
        self.assertEqual(result[1]["amount"], 5000.0)
        self.assertEqual(result[2]["amount"], -11501.53)

    def test_salary_is_income_even_when_statement_sign_is_negative(self):
        items = [
            {"title": "Maaş ödemesi ACME A.Ş.", "amount": -25000.0},
            {"title": "Maaş ödemesi ACME A.Ş.", "amount": 25000.0},
        ]

        result = _normalize_statement_signs(items, "bank")

        self.assertEqual(result[0]["amount"], 25000.0)
        self.assertEqual(result[1]["amount"], 25000.0)

    def test_summary_rows_are_not_treated_as_transactions(self):
        text = """
        11.08.2026 Kullanılabilir kart limiti 8605.07
        02.07.2026 Ödeme - Enpara.com Cep Şubesi -11051.53
        """

        result = parse_transactions_from_text(text)
        titles = [item["title"] for item in result]

        self.assertNotIn("Kullanılabilir kart limiti", titles)
        self.assertIn("Ödeme - Enpara.com Cep Şubesi", titles)

    def test_statement_fee_notice_is_not_treated_as_transaction(self):
        result = parse_transactions_from_text(
            "04/09/2026 şans oyunu ödemelerinde her ay ilk 3 işleminizi ücretsiz olarak, 4. ve sonrasındaki işlemlerinizi işlem başına 18,90 TL BSMV dahil"
        )

        self.assertEqual(result, [])

    def test_description_after_amount_is_used_as_title(self):
        result = parse_transactions_from_text(
            "06.07.2026 256,63 Araba taksidi"
        )

        self.assertEqual(result[0]["title"], "Araba taksidi")

    def test_bank_rows_with_separated_minus_and_amount_keep_description(self):
        result = parse_transactions_from_text(
            "05/07/26 Diğer, 000000001983954-HARCLAR VD MERKEZ VE ANKARA TR - 1.250,00 8.091,48"
        )

        self.assertEqual(len(result), 1)
        self.assertIn("HARCLAR", result[0]["title"])
        self.assertEqual(result[0]["amount"], -1250.0)

    def test_amount_without_thousands_separator_is_parsed(self):
        result = parse_transactions_from_text(
            "05/07/26 Diğer, işlem açıklaması 1250,00"
        )

        self.assertEqual(result[0]["amount"], 1250.0)

    def test_word_rows_keep_description_before_transaction_and_balance_amounts(self):
        words = [
            {"text": "05/07/26", "top": 10, "x0": 0},
            {"text": "Diğer,", "top": 10, "x0": 60},
            {"text": "HARCLAR", "top": 10, "x0": 120},
            {"text": "VD", "top": 10, "x0": 200},
            {"text": "MERKEZ", "top": 10, "x0": 230},
            {"text": "-", "top": 10, "x0": 350},
            {"text": "1.250,00", "top": 10, "x0": 380},
            {"text": "8.091,48", "top": 10, "x0": 450},
        ]

        result = _extract_transactions_from_words(words, row_bucket=5)

        self.assertEqual(result[0]["title"], "Diğer, HARCLAR VD MERKEZ")
        self.assertEqual(result[0]["amount"], -1250.0)

    def test_merchant_titles_default_to_expense_sign(self):
        items = [
            {"title": "PİDEM BESİKTAS CADDE ISTANBUL TR", "amount": 135.0},
            {"title": "GÜNEY KEBAP RESTAURANT ISTANBUL TR", "amount": 710.0},
            {"title": "Gelir Transfer, Sadık Karakazan", "amount": 5000.0},
        ]

        result = _normalize_statement_signs(items, "bank")

        self.assertEqual(result[0]["amount"], -135.0)
        self.assertEqual(result[1]["amount"], -710.0)
        self.assertEqual(result[2]["amount"], 5000.0)

    def test_detects_credit_card_statement(self):
        result = _detect_statement_type(
            "Kredi Kartı Ekstresi Dönem Borcu Kullanılabilir Kart Limiti"
        )

        self.assertEqual(result, "credit_card")

    def test_detects_bank_statement(self):
        result = _detect_statement_type("Hesap Hareketleri IBAN Gelen Havale")

        self.assertEqual(result, "bank")

    def test_outgoing_transfer_is_an_expense(self):
        result = _normalize_transaction_type(
            None,
            "Giden Transfer, Sadık Karakazan",
            -5000,
        )

        self.assertEqual(result, "expense")

    def test_analysis_period_accepts_current_and_previous_two_months(self):
        from datetime import date
        from unittest.mock import patch

        with patch("main._current_analysis_period", return_value=(date(2026, 7, 1), date(2026, 9, 7))):
            _validate_transaction_dates([
                {"date": "2026-07-01"},
                {"date": "2026-09-07"},
            ])

    def test_analysis_period_rejects_older_transactions(self):
        from fastapi import HTTPException
        from unittest.mock import patch
        from datetime import date

        with patch("main._current_analysis_period", return_value=(date(2026, 7, 1), date(2026, 9, 7))):
            with self.assertRaises(HTTPException):
                _validate_transaction_dates([{"date": "2026-06-30"}])


if __name__ == "__main__":
    unittest.main()
