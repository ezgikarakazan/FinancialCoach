from main import _dedupe_transactions


def test_dedupe_transactions_ignores_case_and_punctuation():
    items = [
        {"date": "2025-01-15", "title": "MIGROS", "amount": -145.5},
        {"date": "2025-01-15", "title": "migros", "amount": -145.5},
        {"date": "2025-01-15", "title": "MİGROS", "amount": -145.5},
    ]

    deduped = _dedupe_transactions(items)

    assert len(deduped) == 1
    assert deduped[0]["title"] == "MIGROS"


def test_dedupe_transactions_keeps_distinct_dates_and_amounts():
    items = [
        {"date": "2025-01-15", "title": "MIGROS", "amount": -145.5},
        {"date": "2025-01-16", "title": "MIGROS", "amount": -145.5},
        {"date": "2025-01-15", "title": "MIGROS", "amount": -150.0},
    ]

    deduped = _dedupe_transactions(items)

    assert len(deduped) == 3
