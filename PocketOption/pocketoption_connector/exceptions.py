class ConnectorError(RuntimeError):
    """Base error for connector failures."""


class DependencyMissingError(ConnectorError):
    """Raised when ``pocketoptionapi-async`` is not installed."""


class UnsupportedFeatureError(ConnectorError):
    """Raised when a capability is not exposed by the underlying community client."""


class LoginFailedError(ConnectorError):
    """Raised when automated browser login cannot obtain a session (SSID)."""
