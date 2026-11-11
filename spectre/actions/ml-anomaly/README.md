# ML Anomaly Detection / Fix Engine

Python dependencies are listed in `requirements.txt` (includes `numpy`, `scikit-learn`, `pandas`, `requests`, etc.).

## Local test setup

`tests/test_ml.sh` (used by `tests/run_tests.sh`) looks for a prepared interpreter in this order: `$ML_PYTHON`, `spectre/actions/ml-anomaly/venv/bin/python`, `.venv/bin/python`, `/usr/bin/python3`, then `python3` on `PATH`. It requires `numpy`, `sklearn`, `pandas`, and `requests`.

```bash
python3 -m venv spectre/actions/ml-anomaly/venv
spectre/actions/ml-anomaly/venv/bin/pip install -r spectre/actions/ml-anomaly/requirements.txt
bash tests/test_ml.sh
```

Or point to an existing environment: `ML_PYTHON=/path/to/python bash tests/test_ml.sh`.

## Fix engine LLM providers

`ml_fix_engine.py` generates remediation plans via a provider from `providers.py`:

- `ML_FIX_PROVIDER=ollama` (default): local Ollama (`OLLAMA_HOST`, `ML_FIX_MODEL`).
- `ML_FIX_PROVIDER=openai-compatible`: any OpenAI-compatible endpoint (`ML_FIX_API_BASE`, `ML_FIX_API_KEY`, `ML_FIX_MODEL`).
- `ML_FIX_PROVIDER=opencode`: local OpenCode CLI provider (runs `opencode run --format default --archived`).

OpenCode provider environment variables:
- `OPENCODE_BIN` (default: `opencode` on `PATH`)
- `OPENCODE_MODEL` or `ML_FIX_MODEL` (passed as `--model provider/model[#variant]`)
- `OPENCODE_EXTRA_ARGS` (optional extra CLI args, e.g. `--agent build`)
- `OPENCODE_TIMEOUT` (seconds, default `180`)

Provider output is parsed as remediation-plan JSON and still passes the fix engine’s safety validation/approval gates before any apply action.
