from contextlib import contextmanager

from errors import DatabaseOperationError

try:
    import psycopg2
except ImportError:
    psycopg2 = None


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(20) PRIMARY KEY,
    course_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    geo_lat DOUBLE PRECISION,
    geo_lon DOUBLE PRECISION,
    geo_radius DOUBLE PRECISION DEFAULT 100
);

CREATE TABLE IF NOT EXISTS attendance (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(20) REFERENCES sessions(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL DEFAULT '',
    roll_no VARCHAR(50) NOT NULL,
    fingerprint VARCHAR(255) NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    comments TEXT DEFAULT '',
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(session_id, fingerprint),
    UNIQUE(session_id, roll_no)
);

ALTER TABLE sessions ADD COLUMN IF NOT EXISTS geo_lat DOUBLE PRECISION;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS geo_lon DOUBLE PRECISION;
ALTER TABLE sessions ADD COLUMN IF NOT EXISTS geo_radius DOUBLE PRECISION DEFAULT 100;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS name VARCHAR(120) NOT NULL DEFAULT '';
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS comments TEXT DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_att_session ON attendance(session_id);
CREATE INDEX IF NOT EXISTS idx_att_roll_no ON attendance(roll_no);
"""


class DatabaseService:
    def __init__(self, config, logger=None):
        self.config = config
        self.logger = logger
        self._schema_checked = False

    def _connect_raw(self):
        if psycopg2 is None:
            raise RuntimeError(
                "psycopg2 is not installed. Run pip install -r requirements.txt."
            )
        return psycopg2.connect(
            host=self.config.db_host,
            database=self.config.db_name,
            user=self.config.db_user,
            password=self.config.db_pass,
        )

    def ensure_schema(self, conn):
        if self._schema_checked:
            return

        try:
            with conn.cursor() as cur:
                cur.execute(SCHEMA_SQL)
            conn.commit()
            self._schema_checked = True
        except Exception as exc:
            if self.is_database_error(exc):
                self._rollback_quietly(conn)
                self.log_database_error("database.ensure_schema", exc)
                raise DatabaseOperationError("database.ensure_schema", exc) from exc
            raise

    @contextmanager
    def connection(self, operation):
        conn = None
        try:
            conn = self._connect_raw()
            self.ensure_schema(conn)
            yield conn
        except DatabaseOperationError:
            raise
        except Exception as exc:
            if self.is_database_error(exc):
                self._rollback_quietly(conn)
                self.log_database_error(operation, exc)
                raise DatabaseOperationError(operation, exc) from exc
            raise
        finally:
            if conn is not None:
                conn.close()

    def is_database_error(self, exc):
        return psycopg2 is not None and isinstance(exc, psycopg2.Error)

    def is_integrity_error(self, exc):
        return psycopg2 is not None and isinstance(exc, psycopg2.IntegrityError)

    def log_database_error(self, operation, exc):
        if self.logger is None:
            return

        diag = getattr(exc, "diag", None)
        self.logger.exception(
            "Database error during %s (pgcode=%s, table=%s, column=%s, constraint=%s)",
            operation,
            getattr(exc, "pgcode", None),
            getattr(diag, "table_name", None),
            getattr(diag, "column_name", None),
            getattr(diag, "constraint_name", None),
        )

    def _rollback_quietly(self, conn):
        if conn is None:
            return
        try:
            conn.rollback()
        except Exception:
            pass
