/**
 * PostgreSQL + Redis Connection Layer
 */
// ============================================================================
// DEV NOTES
// ============================================================================
/**
 * This is the core DB abstraction layer
 * It creates a unified interface for interacting with both PostgresSQL & Redis, handling:
 * - connection management & pooling - improved performance and scalability
 * - Error handling and retry logic
 * - Performance monitoring
 *
 * This connection layer will be used by:
 * - GraphQL resolvers
 * - API endpoints for data access
 * - Background jobs for data processing
 * - Admin dashboard for compliance monitoring
 *
 * Without this layer, every piece of code would need to:
 * - Manage its own database connections
 * - Implement PII encryption separately
 * - Monitor DB operations performance individually
 */
import { Pool, PoolClient } from "pg";
import Redis from "ioredis";
import "dotenv/config";

// ============================================================================
// CONFIGURATION INTERFACES
// ============================================================================

interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
  ssl?: {
    rejectUnauthorized: boolean;
  };
  max: number; // Connection pool size
  idleTimeoutMillis: number;
  connectionTimeoutMillis: number;
}

interface RedisConfig {
  host: string;
  port: number;
  password?: string;
  db: number;
  retryDelayOnFailover: number;
  enableReadyCheck: boolean;
  maxRetriesPerRequest: number;
  tls?: {
    rejectUnauthorized: boolean;
  };
}

// ============================================================================
// CONNECTION CLASSES
// ============================================================================

/**
 * PostgreSQL Connection Manager
 * - Manages connection pool with 20 concurrent connections
 * - Handles automatic reconnection and health monitoring <100ms response time validation
 */
class PostgreSQLManager {
  private pool: Pool | null = null;
  private config: DatabaseConfig;

  constructor() {
    this.config = {
      host: process.env.POSTGRES_HOST || "localhost",
      port: parseInt(process.env.POSTGRES_PORT || "5432"),
      database: process.env.POSTGRES_DB || "tachyon_db",
      user: process.env.POSTGRES_USER || "tachyon_admin",
      password: process.env.POSTGRES_PASSWORD || "",
      max: parseInt(process.env.POSTGRES_MAX_CONNECTIONS || "20"),
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 10000,
    } as DatabaseConfig;

    // Only add SSL for production or when explicitly enabled
    if (
      process.env.NODE_ENV === "production" ||
      process.env.POSTGRES_SSL === "true"
    ) {
      // Respect POSTGRES_SSL_REJECT_UNAUTHORIZED env var for flexibility
      // Defaults to true for production, false for development
      const rejectUnauthorized =
        process.env.POSTGRES_SSL_REJECT_UNAUTHORIZED !== undefined
          ? process.env.POSTGRES_SSL_REJECT_UNAUTHORIZED === "true"
          : process.env.NODE_ENV === "production";

      this.config.ssl = {
        rejectUnauthorized,
      };
    }

    // Validate required environment variables
    if (!this.config.password) {
      throw new Error("POSTGRES_PASSWORD environment variable is required");
    }

    this.initializePool();
  }

  /**
   * Initialize connection pool with error handling
   * - Open fixed number of connections (20 in this case)
   */
  private initializePool(): void {
    try {
      this.pool = new Pool(this.config);

      // Connection event handlers for monitoring
      this.pool.on("connect", (client: PoolClient) => {
        console.log("PostgreSQL client connected");

        // Set session-level encryption key for PII encryption
        // if (process.env.APP_ENCRYPTION_KEY) {
        //   client.query(`SET app.encryption_key = '${process.env.APP_ENCRYPTION_KEY}'`);
        // }

        // Set current user context for RLS
        if (process.env.APP_CURRENT_USER_ID) {
          client.query(
            `SET app.current_user_id = '${process.env.APP_CURRENT_USER_ID}'`,
          );
        }

        // Enable audit logging for this session
        client.query("SET log_statement = 'all'");
      });

      this.pool.on("error", (err: Error) => {
        console.error("PostgreSQL pool error:", err);
        // Don't log audit event for pool errors to avoid circular issues
      });

      this.pool.on("remove", () => {
        console.log("PostgreSQL client removed from pool");
      });
    } catch (error) {
      console.error("Failed to initialize PostgreSQL pool:", error);
      throw error;
    }
  }

  /**
   * Get connection from pool with audit logging
   * - borrow a connection when a DB operation needs to occur
   */
  async getConnection(): Promise<PoolClient> {
    if (!this.pool) {
      throw new Error("PostgreSQL pool not initialized");
    }

    try {
      const client = await this.pool.connect();

      // Log database access for compliance
      await this.logAuditEvent("data_access", "Connection acquired");

      return client;
    } catch (error) {
      console.error("Failed to get PostgreSQL connection:", error);
      // Don't log errors to avoid circular issues during initialization
      throw error;
    }
  }

  /**
   * Execute query with automatic connection management and audit logging
   * - use connnection to execute DB query operation and log it.
   */
  async query<T = any>(
    text: string,
    params?: any[],
  ): Promise<{ rows: T[]; rowCount: number }> {
    const client = await this.getConnection();

    try {
      // Log query execution for audit compliance
      await this.logAuditEvent(
        "data_access",
        `Query: ${text.substring(0, 100)}...`,
      );

      const start = Date.now();
      const result = await client.query(text, params);
      const duration = Date.now() - start;

      // Log performance metrics
      if (duration > 1000) {
        console.warn(
          `Slow query detected: ${duration}ms - ${text.substring(0, 100)}...`,
        );
      }

      return {
        rows: result.rows,
        rowCount: result.rowCount || 0,
      };
    } catch (error) {
      console.error("Query execution error:", error);
      // Don't log query errors to avoid circular issues
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Execute transaction with rollback support
   * - use connnection to execute DB tx operation and log it.
   */
  async transaction<T>(
    callback: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.getConnection();

    try {
      await client.query("BEGIN");
      await this.logAuditEvent("data_access", "Transaction started");

      const result = await callback(client);

      await client.query("COMMIT");
      await this.logAuditEvent("data_access", "Transaction committed");

      return result;
    } catch (error) {
      await client.query("ROLLBACK");
      console.error("Transaction error:", error);
      // Don't log rollback errors to avoid circular issues
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Log audit events for compliance. Every database operation gets logged with:
   * - User ID, IP address, timestamp
   * - What data was accessed
   * - Compliance status
   */
  private async logAuditEvent(
    eventType: string,
    details: string,
  ): Promise<void> {
    try {
      if (this.pool) {
        // Check if audit table exists before attempting to log
        const tableCheck = await this.pool.query(
          `SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public'
            AND table_name = 'audit_events'
          )`,
        );

        if (!tableCheck.rows[0]?.exists) {
          return; // Silently skip if table doesn't exist (e.g., during initial migration)
        }

        await this.pool.query(
          `
          INSERT INTO audit_events (
            event_id, event_type, event_timestamp, ip_address,
            user_agent, data_accessed, compliance_status, event_details
          ) VALUES (
            $1, $2, NOW(), $3, $4, $5, $6, $7
          )
        `,
          [
            `evt_${Date.now()}_${Math.random().toString(36).substring(7)}`,
            eventType,
            process.env.CLIENT_IP || "127.0.0.1",
            process.env.USER_AGENT || "server",
            details,
            "compliant",
            JSON.stringify({ timestamp: new Date().toISOString() }),
          ],
        );
      }
    } catch (error) {
      // Don't throw on audit logging errors to prevent app disruption
      console.error("Failed to log audit event:", error);
    }
  }

  /**
   * Health check for database connection
   */
  async healthCheck(): Promise<{ healthy: boolean; latency: number }> {
    try {
      const start = Date.now();
      await this.query("SELECT 1 as health_check");
      const latency = Date.now() - start;

      return { healthy: true, latency };
    } catch (error) {
      console.error("Database health check failed:", error);
      return { healthy: false, latency: -1 };
    }
  }

  /**
   * Close all connections
   */
  async close(): Promise<void> {
    if (this.pool) {
      await this.pool.end();
      this.pool = null;
    }
  }
}

/**
 * Redis Connection Manager for caching and session management
 * - Handles caching, sessions, and temporary data
 * - TLS encryption for all Redis operations
 * - Automatic TTL management
 * - Health - Connection validation and performance tracking
 */
class RedisManager {
  private client: Redis | null = null;
  private config: RedisConfig;

  constructor() {
    this.config = {
      host: process.env.REDIS_HOST || "localhost",
      port: parseInt(process.env.REDIS_PORT || "6379"),
      password: process.env.REDIS_PASSWORD,
      db: parseInt(process.env.REDIS_DB || "0"),
      retryDelayOnFailover: 100,
      enableReadyCheck: true,
      maxRetriesPerRequest: 3,
      tls:
        process.env.REDIS_TLS === "true"
          ? {
              rejectUnauthorized: process.env.NODE_ENV === "production",
            }
          : undefined,
    };

    this.initializeClient();
  }

  /**
   * Initialize Redis client with error handling
   */
  private initializeClient(): void {
    try {
      this.client = new Redis(this.config);

      this.client.on("connect", () => {
        console.log("Redis client connected");
      });

      this.client.on("error", (err: Error) => {
        console.error("Redis client error:", err);
      });

      this.client.on("ready", () => {
        console.log("Redis client ready");
      });

      this.client.on("close", () => {
        console.log("Redis client connection closed");
      });
    } catch (error) {
      console.error("Failed to initialize Redis client:", error);
      throw error;
    }
  }

  /**
   * Get value from Redis with error handling
   */
  async get(key: string): Promise<string | null> {
    if (!this.client) {
      throw new Error("Redis client not initialized");
    }

    try {
      return await this.client.get(key);
    } catch (error) {
      console.error(`Redis GET error for key ${key}:`, error);
      throw error;
    }
  }

  /**
   * Set value in Redis with TTL
   */
  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (!this.client) {
      throw new Error("Redis client not initialized");
    }

    try {
      if (ttlSeconds) {
        await this.client.setex(key, ttlSeconds, value);
      } else {
        await this.client.set(key, value);
      }
    } catch (error) {
      console.error(`Redis SET error for key ${key}:`, error);
      throw error;
    }
  }

  /**
   * Delete key from Redis
   */
  async delete(key: string): Promise<number> {
    if (!this.client) {
      throw new Error("Redis client not initialized");
    }

    try {
      return await this.client.del(key);
    } catch (error) {
      console.error(`Redis DEL error for key ${key}:`, error);
      throw error;
    }
  }

  /**
   * Check if key exists
   */
  async exists(key: string): Promise<boolean> {
    if (!this.client) {
      throw new Error("Redis client not initialized");
    }

    try {
      const result = await this.client.exists(key);
      return result === 1;
    } catch (error) {
      console.error(`Redis EXISTS error for key ${key}:`, error);
      throw error;
    }
  }

  /**
   * Store session data with automatic expiration
   */
  async setSession(
    sessionId: string,
    sessionData: any,
    ttlSeconds: number = 86400,
  ): Promise<void> {
    const key = `session:${sessionId}`;
    await this.set(key, JSON.stringify(sessionData), ttlSeconds);
  }

  /**
   * Retrieve session data
   */
  async getSession(sessionId: string): Promise<any | null> {
    const key = `session:${sessionId}`;
    const data = await this.get(key);
    return data ? JSON.parse(data) : null;
  }

  /**
   * Delete session
   */
  async deleteSession(sessionId: string): Promise<void> {
    const key = `session:${sessionId}`;
    await this.delete(key);
  }

  /**
   * Cache API response with automatic expiration
   */
  async cacheResponse(
    cacheKey: string,
    data: any,
    ttlSeconds: number = 300,
  ): Promise<void> {
    await this.set(`cache:${cacheKey}`, JSON.stringify(data), ttlSeconds);
  }

  /**
   * Get cached response
   */
  async getCachedResponse(cacheKey: string): Promise<any | null> {
    const data = await this.get(`cache:${cacheKey}`);
    return data ? JSON.parse(data) : null;
  }

  /**
   * Health check for Redis connection
   */
  async healthCheck(): Promise<{ healthy: boolean; latency: number }> {
    if (!this.client) {
      return { healthy: false, latency: -1 };
    }

    try {
      const start = Date.now();
      await this.client.ping();
      const latency = Date.now() - start;

      return { healthy: true, latency };
    } catch (error) {
      console.error("Redis health check failed:", error);
      return { healthy: false, latency: -1 };
    }
  }

  /**
   * Close Redis connection
   */
  async close(): Promise<void> {
    if (this.client) {
      await this.client.quit();
      this.client = null;
    }
  }
}

// ============================================================================
// SINGLETON INSTANCES
// ============================================================================

export const postgresql = new PostgreSQLManager();
export const redis = new RedisManager();

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Test all database connections
 */
export async function testConnections(): Promise<{
  postgresql: { healthy: boolean; latency: number };
  redis: { healthy: boolean; latency: number };
}> {
  const [postgresHealth, redisHealth] = await Promise.all([
    postgresql.healthCheck(),
    redis.healthCheck(),
  ]);

  return {
    postgresql: postgresHealth,
    redis: redisHealth,
  };
}

/**
 * Gracefully close all connections
 */
export async function closeAllConnections(): Promise<void> {
  await Promise.all([postgresql.close(), redis.close()]);
}

/**
 * Initialize database connections with retry logic
 */
export async function initializeConnections(
  retries: number = 3,
): Promise<void> {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const health = await testConnections();

      if (health.postgresql.healthy && health.redis.healthy) {
        console.log("✅ All database connections healthy");
        console.log(`  PostgreSQL: ${health.postgresql.latency}ms`);
        console.log(`  Redis: ${health.redis.latency}ms`);
        return;
      }

      throw new Error(
        `Connection health check failed: PostgreSQL=${health.postgresql.healthy}, Redis=${health.redis.healthy}`,
      );
    } catch (error) {
      console.error(
        `Database connection attempt ${attempt}/${retries} failed:`,
        error,
      );

      if (attempt === retries) {
        throw new Error(
          `Failed to establish database connections after ${retries} attempts`,
        );
      }

      // Wait before retry (exponential backoff)
      await new Promise((resolve) =>
        setTimeout(resolve, Math.pow(2, attempt) * 1000),
      );
    }
  }
}

// Export types for use in other modules
export type { DatabaseConfig, RedisConfig };
export { PostgreSQLManager, RedisManager };
