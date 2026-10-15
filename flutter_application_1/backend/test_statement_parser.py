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


def test_statement_title_excludes_bank_page_footer():
    transaction = main._build_transaction(
        main.date(2026, 9, 9),
        (
            "Diğer, TAB GIDA POPEYES ISTANBUL TR - Sayfa 1/3 "
            "Enpara Bank A.Ş Büyük Mükellefler V.D Seri / Sıra No / ENBK / "
            "Ticaret sicil no 494129-5 | Mersis No 0335-0917-5890-0001"
        ),
        -300,
    )

    assert transaction["title"] == "Diğer, TAB GIDA POPEYES ISTANBUL TR"


def test_statement_period_is_inferred_from_transaction_dates():
    assert main._infer_statement_period(
        [
            {"date": "2026-09-03"},
            {"date": "2026-09-18"},
            {"date": "2026-09-30"},
        ]
    ) == "Eylül 2026"


def test_statement_period_shows_month_range_when_transactions_span_months():
    assert main._infer_statement_period(
        [
            {"date": "2026-08-28"},
            {"date": "2026-09-03"},
        ]
    ) == "Ağustos-Eylül 2026"