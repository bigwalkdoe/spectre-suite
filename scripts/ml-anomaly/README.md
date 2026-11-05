# ML Anomaly Detection / Fix Engine

Python dependencies are listed in `requirements.txt` (includes `numpy`, `scikit-learn`, `pandas`, `requests`, etc.).

## Local test setup

`tests/test_ml.sh` (used by `tests/run_tests.sh`) looks for a prepared interpreter in this order: `$ML_PYTHON`, `scripts/ml-anomaly/venv/bin/python`, `.venv/bin/python`, `/usr/bin/python3`, then `python3` on `PATH`. It requires `numpy`, `sklearn`, `pandas`, and `requests`.

```bash
python3 -m venv scripts/ml-anomaly/venv
scripts/ml-anomaly/venv/bin/pip install -r scripts/ml-anomaly/requirements.txt
bash tests/test_ml.sh
```

Or point to an existing environment: `ML_PYTHON=/path/to/python bash tests/test_ml.sh`.
