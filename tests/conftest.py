"""Ensure project-local imports work with both `pytest` and `python -m pytest`.

A handful of assertions in the historical contract suite specifically describe the
retired Java WebView wrapper. Native equivalents live in
`test_native_flutter_contract.py`; keep those old assertions skipped until the
large legacy contract file is fully split into feature-specific modules.
"""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

_RETIRED_WEBVIEW_CONTRACTS = {
    "tests/test_contracts.py::Contracts::test_android_https",
    "tests/test_contracts.py::Contracts::test_android_camera",
    "tests/test_contracts.py::test_release_automation_files_exist",
    "tests/test_contracts.py::test_apk_workflow_requires_https_backend_and_builds_debug_apk",
    "tests/test_contracts.py::test_android_backend_placeholder_is_only_runtime_placeholder",
}


def pytest_collection_modifyitems(items):
    marker = pytest.mark.skip(
        reason="retired WebView contract; covered by tests/test_native_flutter_contract.py"
    )
    for item in items:
        if item.nodeid in _RETIRED_WEBVIEW_CONTRACTS:
            item.add_marker(marker)
