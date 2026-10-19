CREATE TABLE marks (
  scope TEXT NOT NULL, event_id TEXT NOT NULL, day TEXT NOT NULL,
  step INTEGER NOT NULL CHECK(step BETWEEN 0 AND 3),
  instant_us INTEGER NOT NULL, evidence TEXT NOT NULL,
  PRIMARY KEY(scope, event_id), UNIQUE(scope, day, step));
-- split
CREATE TABLE transport (
  scope TEXT NOT NULL, event_id TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'na_fila', attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT, acknowledged_at TEXT,
  PRIMARY KEY(scope, event_id),
  FOREIGN KEY(scope,event_id) REFERENCES marks(scope,event_id));
-- split
CREATE TRIGGER immutable_marks_update BEFORE UPDATE ON marks
BEGIN SELECT RAISE(ABORT, 'immutable evidence'); END;
-- split
CREATE TRIGGER immutable_marks_delete BEFORE DELETE ON marks
BEGIN SELECT RAISE(ABORT, 'immutable evidence'); END;
