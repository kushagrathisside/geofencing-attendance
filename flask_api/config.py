import os
from dataclasses import dataclass


DEFAULT_ALLOWED_SUBNETS = (
    "127.0.0.1/32,::1/128,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
)
DEFAULT_TRUSTED_PROXY_SUBNETS = "127.0.0.1/32,::1/128"


def _split_csv(value):
    return tuple(item.strip() for item in value.split(",") if item.strip())


def _env_bool(name, default=False):
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    return raw_value.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class AppConfig:
    db_host: str
    db_name: str
    db_user: str
    db_pass: str
    redis_host: str
    admin_key: str
    allowed_subnets: tuple[str, ...]
    trust_proxy_headers: bool
    trusted_proxy_subnets: tuple[str, ...]
    max_content_length: int
    port: int

    @classmethod
    def from_env(cls):
        allowed_subnets = os.environ.get("ALLOWED_SUBNETS", DEFAULT_ALLOWED_SUBNETS)
        trusted_proxy_subnets = os.environ.get(
            "TRUSTED_PROXY_SUBNETS",
            DEFAULT_TRUSTED_PROXY_SUBNETS,
        )
        return cls(
            db_host=os.environ.get("DB_HOST", "localhost"),
            db_name=os.environ.get("DB_NAME", "attendance"),
            db_user=os.environ.get("DB_USER", "admin"),
            db_pass=os.environ.get("DB_PASS", "dev-db-password"),
            redis_host=os.environ.get("REDIS_HOST", "localhost"),
            admin_key=os.environ.get("ADMIN_KEY", "dev-admin-key"),
            allowed_subnets=_split_csv(allowed_subnets),
            trust_proxy_headers=_env_bool("TRUST_PROXY_HEADERS"),
            trusted_proxy_subnets=_split_csv(trusted_proxy_subnets),
            max_content_length=int(os.environ.get("MAX_CONTENT_LENGTH", 32 * 1024)),
            port=int(os.environ.get("PORT", "5000")),
        )
