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

CREATE INDEX IF NOT EXISTS idx_att_session ON attendance(session_id);
CREATE INDEX IF NOT EXISTS idx_att_roll_no ON attendance(roll_no);
