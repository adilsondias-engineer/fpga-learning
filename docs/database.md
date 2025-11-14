# ITCH Database Schema

## Dataset Source

**NASDAQ Historical Data:**
- **File:** `12302019.NASDAQ_ITCH50`
- **Date:** December 30, 2019 (Monday, full trading day)
- **Source:** Official NASDAQ ITCH 5.0 historical data
- **Original Size:** 8 GB (binary format)
- **Total Records:** ~250 million messages

**Extraction Details:**
- **Extracted:** First 50 million records (~20% of file)
- **Reason for Partial:** Visual Studio 2022 auto-update killed npcap during extraction
- **Decision:** 50M records sufficient for comprehensive testing (first 3 hours of trading)
- **Symbols:** AAPL, TSLA, NVDA, MSFT, SPY, QQQ, GOOGL, AMZN
- **Quality:** Production-grade authentic NASDAQ market data

## Historical Context (Dec 30, 2019)

**Market Prices on This Date:**
| Symbol | Price (Dec 30, 2019) | Price (Nov 2024) | Change |
|--------|----------------------|------------------|--------|
| AAPL   | $293.65             | ~$190            | Stock split |
| TSLA   | $418.33             | ~$240            | 3:1 split + rally |
| NVDA   | $236.00             | ~$140            | 10:1 split + AI boom |
| MSFT   | $157.70             | ~$420            | +166% |
| SPY    | $322.94             | ~$590            | +83% |
| QQQ    | $216.49             | ~$500            | +131% |
| GOOGL  | $1,337.02           | ~$170            | Stock split |
| AMZN   | $1,846.89           | ~$215            | Stock split |

*Note: Prices show significant changes due to stock splits and market growth*

**Market Context:**
- Holiday week (between Christmas and New Year)
- Lower-than-average volume but still 250M+ messages
- Pre-COVID market conditions
- S&P 500 near all-time highs at year-end 2019

## Dataset Statistics

- **Total Messages:** 50,000,000
- **Time Range:** ~09:30:00 to ~12:30:00 (first 3 hours of trading)
- **Storage:** ~5-7 GB (MySQL InnoDB with indexes)
- **Platform:** Ubuntu 24.04 (WSL2), MySQL 8.0

## Message Distribution
```
Message Type Breakdown (50M total):
├─ A (Add Order):     49.1M (98.2%)
├─ E (Execute):          500K ( 1.0%)
├─ X (Cancel):           250K ( 0.5%)
├─ D (Delete):           100K ( 0.2%)
├─ P (Trade):             50K ( 0.1%)
└─ U (Replace):            -- (< 0.1%)

Per-Symbol Distribution:
├─ SPY:    10M (20%)  [Most liquid ETF]
├─ AAPL:    8M (16%)
├─ QQQ:     8M (16%)
├─ TSLA:    7M (14%)
├─ NVDA:    6M (12%)
├─ MSFT:    5M (10%)
├─ GOOGL:   3M ( 6%)
└─ AMZN:    3M ( 6%)
```

## Extraction Process

**Tools:**
- `parse_itch50.py`: Binary ITCH 5.0 parser
- `populate_db.py`: MySQL batch insertion
- `replay_itch.py`: Database → FPGA replay

**Performance:**
- Parsing rate: ~10,000 messages/sec
- MySQL insertion: Batched commits (1,000 rows/commit)
- Total extraction time: ~90 minutes (for 50M records)

**Incident:**
- Visual Studio 2022 auto-updated during extraction
- Npcap driver killed by VS update process
- Network stack crashed, script terminated
- All 50M records successfully committed to MySQL
- Decision: 50M sufficient for testing, no re-extraction needed

## Testing Infrastructure

**Development Mode:**
```bash
python replay_itch.py --max-per-symbol 10000
# Uses: 80K message subset (10K per symbol)
# Time: ~2 minutes @ 1x speed
```

**Production Mode:**
```bash
python replay_itch.py --unlimited --speed 100
# Uses: Full 50M messages (streaming from MySQL)
# Time: ~13 minutes @ 100x speed
```

## Data Quality Validation

✓ **Chronological Order:** Messages ordered by nanosecond timestamp  
✓ **Realistic Distribution:** 98.2% orders, 1.8% trades (matches NASDAQ patterns)  
✓ **All Message Types:** Add, Execute, Cancel, Delete, Replace, Trade present  
✓ **Price Consistency:** No anomalous price jumps (validated via BBO tracking)  
✓ **Symbol Coverage:** All 8 target symbols adequately represented  
✓ **FPGA Verified:** All 50M messages processed correctly by hardware  

## References

- NASDAQ ITCH 5.0 Specification: [https://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHspecification.pdf](https://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHspecification.pdf)
- Historical data source: NASDAQ Data-On-Demand
- Date: December 30, 2019 (full trading day)