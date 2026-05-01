try:
    import redis
except ImportError:
    redis = None


class SubmissionCache:
    def __init__(self, redis_host, logger=None):
        self.redis_host = redis_host
        self.logger = logger
        self._client = None

    def _get_client(self):
        if redis is None:
            return None
        if self._client is None:
            self._client = redis.Redis(
                host=self.redis_host,
                port=6379,
                db=0,
                decode_responses=True,
            )
        return self._client

    def exists(self, key):
        client = self._get_client()
        if client is None:
            return False
        try:
            return bool(client.exists(key))
        except Exception:
            if self.logger:
                self.logger.warning("Redis exists failed for key %s", key, exc_info=True)
            return False

    def set(self, key, value, ttl_seconds):
        client = self._get_client()
        if client is None:
            return
        try:
            client.setex(key, ttl_seconds, value)
        except Exception:
            if self.logger:
                self.logger.warning("Redis set failed for key %s", key, exc_info=True)

    def clear_session(self, session_id):
        client = self._get_client()
        if client is None:
            return
        try:
            for key in client.scan_iter(match=f"attend:{session_id}:*"):
                client.delete(key)
        except Exception:
            if self.logger:
                self.logger.warning(
                    "Redis session clear failed for session %s",
                    session_id,
                    exc_info=True,
                )
