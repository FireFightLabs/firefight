# Database Migrations

Migration patterns for different frameworks.

## Alembic (Python/SQLAlchemy)

**Setup**:
```bash
uv pip install alembic
alembic init alembic
```

**`alembic/env.py`** (key modifications):
```python
from sqlalchemy import engine_from_config, pool
from alembic import context
import os

from app.database import Base, SCHEMA
from app.models import *  # noqa

config = context.config
config.set_main_option("sqlalchemy.url", os.environ["DATABASE_URL"])

target_metadata = Base.metadata


def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
        connect_args={"options": f"-csearch_path={SCHEMA}"},
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            version_table_schema=SCHEMA,
            include_schemas=True,
        )

        with context.begin_transaction():
            context.run_migrations()
```

**Commands**:
```bash
alembic revision --autogenerate -m "create users table"
alembic upgrade head
alembic current
```

## Prisma Migrate (Node.js)

```bash
# Development
npx prisma migrate dev --name init

# Production
npx prisma migrate deploy

# Reset (WARNING: destroys data)
npx prisma migrate reset
```

Migration files: `prisma/migrations/`

## Drizzle Migrate (Node.js)

**Generate**:
```bash
npx drizzle-kit generate:pg
```

**Apply** (`src/db/migrate.ts`):
```typescript
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import { Pool } from "pg";

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const db = drizzle(pool);

async function main() {
  await migrate(db, { migrationsFolder: "./drizzle" });
  await pool.end();
}

main();
```

```bash
npx tsx src/db/migrate.ts
```

## Raw SQL Migrations

For apps not using ORMs:

```
migrations/
├── 001_create_users.sql
├── 002_add_user_email_index.sql
└── 003_create_posts.sql
```

**`migrations/001_create_users.sql`**:
```sql
BEGIN;

CREATE TABLE IF NOT EXISTS {app_name}.users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON {app_name}.users(email);

-- Track migrations
CREATE TABLE IF NOT EXISTS {app_name}._migrations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

INSERT INTO {app_name}._migrations (name) VALUES ('001_create_users');

COMMIT;
```

**Apply**:
```bash
psql "$DATABASE_URL" -f migrations/001_create_users.sql
```

## Migration Best Practices

| Practice | Why |
|----------|-----|
| Use transactions | Rollback on failure |
| Track applied migrations | Prevent re-running |
| Test on staging first | Catch schema issues |
| Backup before major changes | Recovery option |
| Use `--dry-run` when available | Preview changes |
