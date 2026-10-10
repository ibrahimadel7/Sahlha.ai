export async function q<T = Record<string, unknown>>(
  db: D1Database,
  sql: string,
  ...params: unknown[]
): Promise<T[]> {
  const r = await db.prepare(sql).bind(...params).all<T>();
  return r.results ?? [];
}

export async function q1<T = Record<string, unknown>>(
  db: D1Database,
  sql: string,
  ...params: unknown[]
): Promise<T | null> {
  const r = await db.prepare(sql).bind(...params).first<T>();
  return r ?? null;
}

export async function run(db: D1Database, sql: string, ...params: unknown[]) {
  return db.prepare(sql).bind(...params).run();
}

/** Multi-row INSERT split into chunks that stay under D1's 100KB statement cap. */
export async function insertMany(
  db: D1Database,
  table: string,
  cols: string[],
  rows: unknown[][],
  perStmt = 8,
): Promise<void> {
  if (rows.length === 0) return;
  const ph = (n: number) => `(${cols.map(() => "?").join(",")})`;
  for (let i = 0; i < rows.length; i += perStmt) {
    const part = rows.slice(i, i + perStmt);
    const sql = `INSERT INTO ${table} (${cols.join(",")}) VALUES ${part.map(() => ph(cols.length)).join(",")}`;
    await db
      .prepare(sql)
      .bind(...part.flat())
      .run();
  }
}
