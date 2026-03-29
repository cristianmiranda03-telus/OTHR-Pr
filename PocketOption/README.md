# pocketoption-connector

English-speaking API surface with a **credential-first** workflow: put your Pocket Option **email and password** in `.env`, install the optional **Playwright** extra, and the package signs in through the **official web login page** to capture the `ssid` cookie for you. You can still paste `POCKETOPTION_SSID` manually if you prefer.

This is **not** an official Pocket Option product. It builds on [**pocketoptionapi-async**](https://chipadevteam.github.io/PocketOptionAPI/) and browser automation. Use **demo** funds until you understand the risks, ToS implications, and failure modes (CAPTCHA, 2FA, layout changes).

---

## Why this module vs “SSID-only” libraries

| Feature | Typical SSID-only wrapper | This package |
|--------|---------------------------|--------------|
| Manual cookie copy | Required every time the session dies | Optional — email/password login automates it |
| Session resolution | You manage SSID strings | `resolve_ssid()` prefers env SSID, else browser login |
| Sync ergonomics | Often async-only | `PocketOption` is synchronous |
| Human-readable durations | Seconds only | `"1m"`, `"5m"`, `"30s"` supported |

Under the hood the websocket transport **still** consumes an SSID-shaped session; Pocket Option does not document a supported OAuth/password API for bots. The difference is **you no longer have to open DevTools** for day-to-day use.

---

## Installation (local `pip`)

```powershell
cd path\to\PocketOption
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -U pip
pip install .
```

**Email/password automation** (Chromium + Playwright):

```powershell
pip install ".[credentials]"
playwright install chromium
```

Notebooks / pandas:

```powershell
pip install ".[notebook]"
```

Verify:

```powershell
python -m pocketoption_connector
```

**From GitHub**

```powershell
pip install "git+https://github.com/YOU/REPO.git@main"
pip install "pocketoption-connector[credentials] @ git+https://github.com/YOU/REPO.git@main"
```

---

## Configuration (`.env`)

Copy `.env.example` → `.env`.

**Credential mode (recommended after installing `[credentials]`):**

```env
POCKETOPTION_EMAIL=you@example.com
POCKETOPTION_PASSWORD=your_password
POCKETOPTION_DEMO=1
```

Optional:

```env
POCKETOPTION_HEADLESS=0          # show the browser window (helps with CAPTCHA / 2FA)
POCKETOPTION_LOGIN_URL=https://pocketoption.com/en/login
```

**SSID mode (no Playwright):**

```env
POCKETOPTION_SSID=...cookie_value...
POCKETOPTION_DEMO=1
```

If **both** are set, `POCKETOPTION_SSID` wins (no browser launch).

---

## Minimal usage

### Context manager (auto session resolution)

```python
from pocketoption_connector import PocketOption

with PocketOption.session(default_asset="EURUSD_otc") as po:
    print(po.balance)
    print(po.last_candle())
```

### Explicit credentials in code

```python
from pocketoption_connector import PocketOption

po = PocketOption.from_credentials("you@example.com", "secret", headless=False)
try:
    print(po.account_snapshot())
finally:
    po.close()
```

### Force SSID-only (disable browser login)

```python
with PocketOption.session(ssid="...", allow_browser_login=False) as po:
    print(po.balance)
```

### Async (advanced)

```python
import asyncio
from pocketoption_connector import PocketOptionConnector

async def main():
    conn = PocketOptionConnector("SSID", is_demo=True)
    await conn.connect()
    try:
        print(await conn.get_balance())
    finally:
        await conn.disconnect()

asyncio.run(main())
```

### Utility API

```python
from pocketoption_connector import resolve_ssid, obtain_ssid_via_browser

ssid = resolve_ssid()  # env SSID or env email/password
ssid = obtain_ssid_via_browser("you@example.com", "secret", headless=False)
```

---

## Limitations

- **CAPTCHA / 2FA / geo blocks** — use `POCKETOPTION_HEADLESS=0` and complete challenges in the visible window, or fall back to manual SSID.
- **Tournaments / in-app signals** — not exposed by the community websocket client; methods raise `UnsupportedFeatureError`.
- **Stability** — the broker can change HTML or auth flows; update selectors or open an issue.

---

## References

- PocketOptionAPI Async: [chipadevteam.github.io/PocketOptionAPI](https://chipadevteam.github.io/PocketOptionAPI/)
- Pocket Option site: [pocketoption.com](https://pocketoption.com/)

---

---

# Documentación en español

## Qué resuelve este módulo

Pocket Option **no publica** una API oficial de usuario/contraseña para robots. Los clientes no oficiales usan la cookie **SSID**. Aquí puedes **evitar copiar el SSID a mano**: el paquete abre el **login web oficial** con **Playwright**, introduce email/contraseña y lee el SSID automáticamente. El websocket sigue necesitando ese SSID por debajo; la diferencia es la **experiencia de uso** frente a otros módulos “solo pega el SSID”.

**Aviso:** uso educativo; riesgo de cambios en la web, CAPTCHA, 2FA y posibles conflictos con los términos del bróker. Usa **cuenta demo** (`POCKETOPTION_DEMO=1`).

## Instalación

```powershell
pip install .
pip install ".[credentials]"
playwright install chromium
```

## Variables de entorno (`.env`)

**Modo credenciales (recomendado con `[credentials]`):**

```env
POCKETOPTION_EMAIL=tu@correo.com
POCKETOPTION_PASSWORD=tu_contraseña
POCKETOPTION_DEMO=1
```

**Modo SSID manual (sin Playwright):**

```env
POCKETOPTION_SSID=valor_de_la_cookie
POCKETOPTION_DEMO=1
```

Si existen ambos, **gana** `POCKETOPTION_SSID` (no se abre el navegador).

**Ventana visible** (útil con CAPTCHA o 2FA): `POCKETOPTION_HEADLESS=0`.

## Uso mínimo

```python
from pocketoption_connector import PocketOption

with PocketOption.session(default_asset="EURUSD_otc") as po:
    print(po.balance)
    print(po.last_candle())
```

Credenciales explícitas en código:

```python
po = PocketOption.from_credentials("tu@correo.com", "clave", headless=False)
try:
    print(po.balance)
finally:
    po.close()
```

## Limitaciones (ES)

- CAPTCHA, 2FA o bloqueos geográficos pueden impedir el login automático; prueba `POCKETOPTION_HEADLESS=0` o pega el SSID manualmente.
- Torneos y señales internas de la app no están en la API comunitaria.

## Referencias (ES)

- Documentación del cliente base: [PocketOptionAPI Async](https://chipadevteam.github.io/PocketOptionAPI/)
- Web: [pocketoption.com](https://pocketoption.com/)
