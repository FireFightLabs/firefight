# ORM Configuration Templates

Configuration templates for popular ORMs with schema support.

## Prisma (Node.js/TypeScript)

**`prisma/schema.prisma`**:
```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
  schemas  = ["{app_name}"]
}

generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["multiSchema"]
}

model User {
  id    Int    @id @default(autoincrement())
  email String @unique
  name  String?

  @@schema("{app_name}")
}
```

**`.env`**:
```bash
DATABASE_URL="postgresql://{app_name}_user:PASSWORD@HOST:25060/defaultdb?sslmode=require&schema={app_name}"
```

**Initialize**:
```bash
npx prisma generate
npx prisma db push  # or npx prisma migrate dev
```

## SQLAlchemy (Python)

**`database.py`**:
```python
from sqlalchemy import create_engine, MetaData
from sqlalchemy.orm import declarative_base, sessionmaker
import os

DATABASE_URL = os.environ["DATABASE_URL"]
SCHEMA = "{app_name}"

engine = create_engine(
    DATABASE_URL,
    connect_args={"options": f"-csearch_path={SCHEMA}"},
    pool_size=5,
    max_overflow=10,
    pool_pre_ping=True,
)

metadata = MetaData(schema=SCHEMA)
Base = declarative_base(metadata=metadata)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

**`models.py`**:
```python
from sqlalchemy import Column, Integer, String
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    name = Column(String)
```

**Install**:
```bash
uv pip install sqlalchemy psycopg2-binary
```

## Drizzle (Node.js/TypeScript)

**`drizzle.config.ts`**:
```typescript
import type { Config } from "drizzle-kit";

export default {
  schema: "./src/db/schema.ts",
  out: "./drizzle",
  driver: "pg",
  dbCredentials: {
    connectionString: process.env.DATABASE_URL!,
  },
  schemaFilter: ["{app_name}"],
} satisfies Config;
```

**`src/db/schema.ts`**:
```typescript
import { pgTable, pgSchema, serial, text, varchar } from "drizzle-orm/pg-core";

export const appSchema = pgSchema("{app_name}");

export const users = appSchema.table("users", {
  id: serial("id").primaryKey(),
  email: varchar("email", { length: 255 }).notNull().unique(),
  name: text("name"),
});
```

**`src/db/index.ts`**:
```typescript
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

export const db = drizzle(pool, { schema });
```

## TypeORM (Node.js/TypeScript)

**`data-source.ts`**:
```typescript
import { DataSource } from "typeorm";

export const AppDataSource = new DataSource({
  type: "postgres",
  url: process.env.DATABASE_URL,
  schema: "{app_name}",
  ssl: { rejectUnauthorized: false },
  entities: ["src/entities/*.ts"],
  migrations: ["src/migrations/*.ts"],
  synchronize: false,
});
```

**`src/entities/User.ts`**:
```typescript
import { Entity, PrimaryGeneratedColumn, Column } from "typeorm";

@Entity({ schema: "{app_name}" })
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true })
  email: string;

  @Column({ nullable: true })
  name: string;
}
```

## Path A vs Path B

| ORM Config | Path A (Bindable Vars) | Path B (Schema Isolation) |
|------------|------------------------|---------------------------|
| Schema | Usually `public` | Named schema (`{app_name}`) |
| Connection | `${db.DATABASE_URL}` | Manual env var |
| Search path | Default | Set via connection args |
