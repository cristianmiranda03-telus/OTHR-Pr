"""Sanity check after ``pip install``."""

from pocketoption_connector import __version__

if __name__ == "__main__":
    print(f"pocketoption_connector {__version__} OK")
    print("Quick start: from pocketoption_connector import PocketOption")
    print("Credentials: pip install 'pocketoption-connector[credentials]' && playwright install chromium")
    print("Then: with PocketOption.session(default_asset='EURUSD_otc') as po: print(po.balance)")
