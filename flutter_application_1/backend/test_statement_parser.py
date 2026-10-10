import main


def test_gold_purchase_is_categorized_as_investment():
    assert main._guess_category(
        "FAST sorgu no Alış/Satış, 0,14 gram altın alış, işlem kuru"
    ) == "Yatırım"


def test_statement_parser_keeps_following_dated_row_separate():
    words = [
        {"text": "11/09/26", "top": 100, "x0": 60},
        {"text": "Diğer,", "top": 100, "x0": 195},
        {"text": "ODEAL//EMIR", "top": 100, "x0": 250},
        {"text": "MARKET", "top": 100, "x0": 350},
        {"text": "-120,00", "top": 100, "x0": 740},
        {"text": "115.009,26", "top": 100, "x0": 830},
        {"text": "12/09/26,", "top": 140, "x0": 60},
        {"text": "Giden", "top": 140, "x0": 195},
        {"text": "Transfer,", "top": 140, "x0": 250},
        {"text": "Ezgi", "top": 140, "x0": 340},
        {"text": "Karakazan,", "top": 140, "x0": 380},
        {"text": "-300,00", "top": 140, "x0": 740},
        {"text": "114.069,26", "top": 140, "x0": 830},
    ]

    transactions = main._extract_transactions_from_words(words, row_bucket=5)

    assert len(transactions) == 2
    assert transactions[0]["date"] == "2026-09-11"
    assert "Giden Transfer" not in transactions[0]["title"]
    assert transactions[1]["date"] == "2026-09-12"
    assert "Giden Transfer" in transactions[1]["title"]