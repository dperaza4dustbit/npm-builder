from __future__ import annotations

import logging

from npm_builder.logging import configure_logging


class TestConfigureLogging:
    def test_default_level_is_info(self):
        configure_logging()
        assert logging.getLogger().level == logging.INFO

    def test_verbose_sets_debug_level(self):
        configure_logging(verbose=True)
        assert logging.getLogger().level == logging.DEBUG

    def test_logs_go_to_stderr_not_stdout(self, capsys):
        configure_logging(verbose=True)
        logging.getLogger("npm_builder.test").info("hello")
        captured = capsys.readouterr()
        assert "hello" in captured.err
        assert "hello" not in captured.out
