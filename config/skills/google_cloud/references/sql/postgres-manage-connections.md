<br />

This page provides best practices and language-specific code samples to help you
create applications that use Cloud SQL database connections effectively.

These samples are excerpts from a complete web application
available to you on GitHub. [Learn more](https://docs.cloud.google.com/sql/docs/postgres/manage-connections#app-links).

**For step-by-step instructions on running a sample web
application connected to Cloud SQL,** follow the link
for your environment:

- [Quickstart for connecting from your local computer](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-local-computer)
- [Quickstart for connecting from Compute Engine](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-compute-engine)
- [Quickstart for connecting from Cloud Run](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-cloud-run)
- [Quickstart for connecting from Cloud Run functions](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-cloud-functions)
- [Quickstart for connecting from Google Kubernetes Engine](https://docs.cloud.google.com/sql/docs/postgres/connect-instance-kubernetes)

## Connection pools

A connection pool is a cache of database connections that are shared and reused
to improve connection latency and performance. When your application needs a
database connection, it borrows one from its pool temporarily; when the
application is finished with the connection, it returns the connection to the
pool, where it can be reused the next time the application needs a database
connection.

### Connect with TCP

### Python

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/python-docs-samples/tree/master/cloud-sql/postgres/sqlalchemy/README.md).

<br />

    import os
    import ssl

    import sqlalchemy


    def connect_tcp_socket() -> sqlalchemy.engine.base.Engine:
        """Initializes a TCP connection pool for a Cloud SQL instance of Postgres."""
        # Note: Saving credentials in environment variables is convenient, but not
        # secure - consider a more secure solution such as
        # Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
        # keep secrets safe.
        db_host = os.environ[
            "INSTANCE_HOST"
        ]  # e.g. '127.0.0.1' ('172.17.0.1' if deployed to GAE Flex)
        db_user = os.environ["DB_USER"]  # e.g. 'my-db-user'
        db_pass = os.environ["DB_PASS"]  # e.g. 'my-db-password'
        db_name = os.environ["DB_NAME"]  # e.g. 'my-database'
        db_port = os.environ["DB_PORT"]  # e.g. 5432

        pool = sqlalchemy.create_engine(
            # Equivalent URL:
            # postgresql+pg8000://<db_user>:<db_pass>@<db_host>:<db_port>/<db_name>
            sqlalchemy.engine.url.URL.create(
                drivername="postgresql+pg8000",
                username=db_user,
                password=db_pass,
                host=db_host,
                port=db_port,
                database=db_name,
            ),
            # ...
        )
        return pool

### Java

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/java-docs-samples/blob/master/cloud-sql/postgres/servlet/README.md).


Note:

- CLOUD_SQL_CONNECTION_NAME should be represented as \<MY-PROJECT\>:\<INSTANCE-REGION\>:\<INSTANCE-NAME\>
- Using the argument ipTypes=PRIVATE will force the SocketFactory to connect with an instance's associated private IP
- See the [JDBC socket factory version requirements for the pom.xml
  file](https://github.com/GoogleCloudPlatform/cloud-sql-jdbc-socket-factory/blob/main/docs/jdbc.md).

<br />

<br />


    import com.zaxxer.hikari.HikariConfig;
    import com.zaxxer.hikari.HikariDataSource;
    import javax.sql.DataSource;

    public class TcpConnectionPoolFactory extends ConnectionPoolFactory {

      // Note: Saving credentials in environment variables is convenient, but not
      // secure - consider a more secure solution such as
      // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
      // keep secrets safe.
      private static final String DB_USER = System.getenv("DB_USER");
      private static final String DB_PASS = System.getenv("DB_PASS");
      private static final String DB_NAME = System.getenv("DB_NAME");

      private static final String INSTANCE_HOST = System.getenv("INSTANCE_HOST");
      private static final String DB_PORT = System.getenv("DB_PORT");


      public static DataSource createConnectionPool() {
        // The configuration object specifies behaviors for the connection pool.
        HikariConfig config = new HikariConfig();

        // The following URL is equivalent to setting the config options below:
        // jdbc:postgresql://<INSTANCE_HOST>:<DB_PORT>/<DB_NAME>?user=<DB_USER>&password=<DB_PASS>
        // See the link below for more info on building a JDBC URL for the Cloud SQL JDBC Socket Factory
        // https://github.com/GoogleCloudPlatform/cloud-sql-jdbc-socket-factory#creating-the-jdbc-url

        // Configure which instance and what database user to connect with.
        config.setJdbcUrl(String.format("jdbc:postgresql://%s:%s/%s", INSTANCE_HOST, DB_PORT, DB_NAME));
        config.setUsername(DB_USER); // e.g. "root", "postgres"
        config.setPassword(DB_PASS); // e.g. "my-password"


        // ... Specify additional connection properties here.
        // ...

        // Initialize the connection pool using the configuration object.
        return new HikariDataSource(config);
      }
    }

### Node.js

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/nodejs-docs-samples/blob/master/cloud-sql/postgres/knex/README.md).

<br />

    const Knex = require('knex');
    const fs = require('fs');

    // createTcpPool initializes a TCP connection pool for a Cloud SQL
    // instance of Postgres.
    const createTcpPool = async config => {
      // Note: Saving credentials in environment variables is convenient, but not
      // secure - consider a more secure solution such as
      // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
      // keep secrets safe.
      const dbConfig = {
        client: 'pg',
        connection: {
          host: process.env.INSTANCE_HOST, // e.g. '127.0.0.1'
          port: process.env.DB_PORT, // e.g. '5432'
          user: process.env.DB_USER, // e.g. 'my-user'
          password: process.env.DB_PASS, // e.g. 'my-user-password'
          database: process.env.DB_NAME, // e.g. 'my-database'
        },
        // ... Specify additional properties here.
        ...config,
      };
      // Establish a connection to the database.
      return Knex(dbConfig);
    };

### Go

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/golang-samples/tree/master/cloudsql/postgres/database-sql/README.md).

<br />

    package cloudsql

    import (
    	"database/sql"
    	"fmt"
    	"log"
    	"os"

    	// Note: If connecting using the App Engine Flex Go runtime, use
    	// "github.com/jackc/pgx/stdlib" instead, since v5 requires
    	// Go modules which are not supported by App Engine Flex.
    	_ "github.com/jackc/pgx/v5/stdlib"
    )

    // connectTCPSocket initializes a TCP connection pool for a Cloud SQL
    // instance of Postgres.
    func connectTCPSocket() (*sql.DB, error) {
    	mustGetenv := func(k string) string {
    		v := os.Getenv(k)
    		if v == "" {
    			log.Fatalf("Fatal Error in connect_tcp.go: %s environment variable not set.", k)
    		}
    		return v
    	}
    	// Note: Saving credentials in environment variables is convenient, but not
    	// secure - consider a more secure solution such as
    	// Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
    	// keep secrets safe.
    	var (
    		dbUser    = mustGetenv("DB_USER")       // e.g. 'my-db-user'
    		dbPwd     = mustGetenv("DB_PASS")       // e.g. 'my-db-password'
    		dbTCPHost = mustGetenv("INSTANCE_HOST") // e.g. '127.0.0.1' ('172.17.0.1' if deployed to GAE Flex)
    		dbPort    = mustGetenv("DB_PORT")       // e.g. '5432'
    		dbName    = mustGetenv("DB_NAME")       // e.g. 'my-database'
    	)

    	dbURI := fmt.Sprintf("host=%s user=%s password=%s port=%s database=%s",
    		dbTCPHost, dbUser, dbPwd, dbPort, dbName)


    	// dbPool is the pool of database connections.
    	dbPool, err := sql.Open("pgx", dbURI)
    	if err != nil {
    		return nil, fmt.Errorf("sql.Open: %w", err)
    	}

    	// ...

    	return dbPool, nil
    }

### C#

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/dotnet-docs-samples/blob/master/cloud-sql/mysql/README.md).

<br />

    using Npgsql;
    using System;

    namespace CloudSql
    {
        public class PostgreSqlTcp
        {
            public static NpgsqlConnectionStringBuilder NewPostgreSqlTCPConnectionString()
            {
                // Equivalent connection string:
                // "Uid=<DB_USER>;Pwd=<DB_PASS>;Host=<INSTANCE_HOST>;Database=<DB_NAME>;"
                var connectionString = new NpgsqlConnectionStringBuilder()
                {
                    // Note: Saving credentials in environment variables is convenient, but not
                    // secure - consider a more secure solution such as
                    // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
                    // keep secrets safe.
                    Host = Environment.GetEnvironmentVariable("INSTANCE_HOST"),     // e.g. '127.0.0.1'
                    // Set Host to 'cloudsql' when deploying to App Engine Flexible environment
                    Username = Environment.GetEnvironmentVariable("DB_USER"), // e.g. 'my-db-user'
                    Password = Environment.GetEnvironmentVariable("DB_PASS"), // e.g. 'my-db-password'
                    Database = Environment.GetEnvironmentVariable("DB_NAME"), // e.g. 'my-database'

                    // The Cloud SQL proxy provides encryption between the proxy and instance.
                    SslMode = SslMode.Disable,
                };
                connectionString.Pooling = true;
                // Specify additional properties here.
                return connectionString;
            }
        }
    }

### Ruby

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/ruby-docs-samples/tree/master/cloud-sql/postgres/activerecord/README.md).

<br />

    tcp: &tcp
      adapter: postgresql
      # Configure additional properties here.
      # Note: Saving credentials in environment variables is convenient, but not
      # secure - consider a more secure solution such as
      # Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
      # keep secrets safe.
      username: <%= ENV["DB_USER"] %>  # e.g. "my-database-user"
      password: <%= ENV["DB_PASS"] %> # e.g. "my-database-password"
      database: <%= ENV.fetch("DB_NAME") { "vote_development" } %>
      host: <%= ENV.fetch("INSTANCE_HOST") { "127.0.0.1" }%> # '172.17.0.1' if deployed to GAE Flex
      port: <%= ENV.fetch("DB_PORT") { 5432 }%>

### PHP

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/php-docs-samples/tree/main/cloud_sql/postgres/pdo/README.md).

<br />

    namespace Google\Cloud\Samples\CloudSQL\Postgres;

    use PDO;
    use PDOException;
    use RuntimeException;
    use TypeError;

    class DatabaseTcp
    {
        public static function initTcpDatabaseConnection(): PDO
        {
            try {
                // Note: Saving credentials in environment variables is convenient, but not
                // secure - consider a more secure solution such as
                // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
                // keep secrets safe.
                $username = getenv('DB_USER'); // e.g. 'your_db_user'
                $password = getenv('DB_PASS'); // e.g. 'your_db_password'
                $dbName = getenv('DB_NAME'); // e.g. 'your_db_name'
                $instanceHost = getenv('INSTANCE_HOST'); // e.g. '127.0.0.1' ('172.17.0.1' for GAE Flex)

                // Connect using TCP
                $dsn = sprintf('pgsql:dbname=%s;host=%s', $dbName, $instanceHost);

                // Connect to the database
                $conn = new PDO(
                    $dsn,
                    $username,
                    $password,
                    # ...
                );
            } catch (TypeError $e) {
                throw new RuntimeException(
                    sprintf(
                        'Invalid or missing configuration! Make sure you have set ' .
                            '$username, $password, $dbName, and $instanceHost (for TCP mode). ' .
                            'The PHP error was %s',
                        $e->getMessage()
                    ),
                    $e->getCode(),
                    $e
                );
            } catch (PDOException $e) {
                throw new RuntimeException(
                    sprintf(
                        'Could not connect to the Cloud SQL Database. Check that ' .
                            'your username and password are correct, that the Cloud SQL ' .
                            'proxy is running, and that the database exists and is ready ' .
                            'for use. For more assistance, refer to %s. The PDO error was %s',
                        'https://cloud.google.com/sql/docs/postgres/connect-external-app',
                        $e->getMessage()
                    ),
                    $e->getCode(),
                    $e
                );
            }

            return $conn;
        }
    }

### Connect with Unix sockets

### Python

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/python-docs-samples/tree/master/cloud-sql/postgres/sqlalchemy/README.md).

<br />

    import os

    import sqlalchemy


    def connect_unix_socket() -> sqlalchemy.engine.base.Engine:
        """Initializes a Unix socket connection pool for a Cloud SQL instance of Postgres."""
        # Note: Saving credentials in environment variables is convenient, but not
        # secure - consider a more secure solution such as
        # Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
        # keep secrets safe.
        db_user = os.environ["DB_USER"]  # e.g. 'my-database-user'
        db_pass = os.environ["DB_PASS"]  # e.g. 'my-database-password'
        db_name = os.environ["DB_NAME"]  # e.g. 'my-database'
        unix_socket_path = os.environ[
            "INSTANCE_UNIX_SOCKET"
        ]  # e.g. '/cloudsql/project:region:instance'

        pool = sqlalchemy.create_engine(
            # Equivalent URL:
            # postgresql+pg8000://<db_user>:<db_pass>@/<db_name>
            #                         ?unix_sock=<INSTANCE_UNIX_SOCKET>/.s.PGSQL.5432
            # Note: Some drivers require the `unix_sock` query parameter to use a different key.
            # For example, 'psycopg2' uses the path set to `host` in order to connect successfully.
            sqlalchemy.engine.url.URL.create(
                drivername="postgresql+pg8000",
                username=db_user,
                password=db_pass,
                database=db_name,
                query={"unix_sock": f"{unix_socket_path}/.s.PGSQL.5432"},
            ),
            # ...
        )
        return pool

### Java

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/java-docs-samples/blob/master/cloud-sql/postgres/servlet/README.md).

<br />

    import com.zaxxer.hikari.HikariConfig;
    import com.zaxxer.hikari.HikariDataSource;
    import javax.sql.DataSource;

    public class ConnectorConnectionPoolFactory extends ConnectionPoolFactory {

      // Note: Saving credentials in environment variables is convenient, but not
      // secure - consider a more secure solution such as
      // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
      // keep secrets safe.
      private static final String INSTANCE_CONNECTION_NAME =
          System.getenv("INSTANCE_CONNECTION_NAME");
      private static final String INSTANCE_UNIX_SOCKET = System.getenv("INSTANCE_UNIX_SOCKET");
      private static final String DB_USER = System.getenv("DB_USER");
      private static final String DB_PASS = System.getenv("DB_PASS");
      private static final String DB_NAME = System.getenv("DB_NAME");

      public static DataSource createConnectionPool() {
        // The configuration object specifies behaviors for the connection pool.
        HikariConfig config = new HikariConfig();

        // The following URL is equivalent to setting the config options below:
        // jdbc:postgresql:///<DB_NAME>?cloudSqlInstance=<INSTANCE_CONNECTION_NAME>&
        // socketFactory=com.google.cloud.sql.postgres.SocketFactory&user=<DB_USER>&password=<DB_PASS>
        // See the link below for more info on building a JDBC URL for the Cloud SQL JDBC Socket Factory
        // https://github.com/GoogleCloudPlatform/cloud-sql-jdbc-socket-factory#creating-the-jdbc-url

        // Configure which instance and what database user to connect with.
        config.setJdbcUrl(String.format("jdbc:postgresql:///%s", DB_NAME));
        config.setUsername(DB_USER); // e.g. "root", _postgres"
        config.setPassword(DB_PASS); // e.g. "my-password"

        config.addDataSourceProperty("socketFactory", "com.google.cloud.sql.postgres.SocketFactory");
        config.addDataSourceProperty("cloudSqlInstance", INSTANCE_CONNECTION_NAME);

        // Unix sockets are not natively supported in Java, so it is necessary to use the Cloud SQL
        // Java Connector to connect. When setting INSTANCE_UNIX_SOCKET, the connector will 
        // call an external package that will enable Unix socket connections.
        // Note: For Java users, the Cloud SQL Java Connector can provide authenticated connections
        // which is usually preferable to using the Cloud SQL Proxy with Unix sockets.
        // See https://github.com/GoogleCloudPlatform/cloud-sql-jdbc-socket-factory for details.
        if (INSTANCE_UNIX_SOCKET != null) {
          config.addDataSourceProperty("unixSocketPath", INSTANCE_UNIX_SOCKET);
        }


        // cloudSqlRefreshStrategy set to "lazy" is used to perform a
        // refresh when needed, rather than on a scheduled interval.
        // This is recommended for serverless environments to
        // avoid background refreshes from throttling CPU.
        config.addDataSourceProperty("cloudSqlRefreshStrategy", "lazy");

        // ... Specify additional connection properties here.
        // ...

        // Initialize the connection pool using the configuration object.
        return new HikariDataSource(config);
      }
    }

### Node.js

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/nodejs-docs-samples/blob/master/cloud-sql/postgres/knex/README.md).

<br />

    const Knex = require('knex');

    // createUnixSocketPool initializes a Unix socket connection pool for
    // a Cloud SQL instance of Postgres.
    const createUnixSocketPool = async config => {
      // Note: Saving credentials in environment variables is convenient, but not
      // secure - consider a more secure solution such as
      // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
      // keep secrets safe.
      return Knex({
        client: 'pg',
        connection: {
          user: process.env.DB_USER, // e.g. 'my-user'
          password: process.env.DB_PASS, // e.g. 'my-user-password'
          database: process.env.DB_NAME, // e.g. 'my-database'
          host: process.env.INSTANCE_UNIX_SOCKET, // e.g. '/cloudsql/project:region:instance'
        },
        // ... Specify additional properties here.
        ...config,
      });
    };

### C#

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/dotnet-docs-samples/blob/master/cloud-sql/postgres/README.md).

<br />

    using Npgsql;
    using System;

    namespace CloudSql
    {
        public class PostgreSqlUnix
        {
            public static NpgsqlConnectionStringBuilder NewPostgreSqlUnixSocketConnectionString()
            {
                // Equivalent connection string:
                // "Server=<INSTANCE_UNIX_SOCKET>;Uid=<DB_USER>;Pwd=<DB_PASS>;Database=<DB_NAME>"
                var connectionString = new NpgsqlConnectionStringBuilder()
                {
                    // The Cloud SQL proxy provides encryption between the proxy and instance.
                    SslMode = SslMode.Disable,

                    // Note: Saving credentials in environment variables is convenient, but not
                    // secure - consider a more secure solution such as
                    // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
                    // keep secrets safe.
                    Host = Environment.GetEnvironmentVariable("INSTANCE_UNIX_SOCKET"), // e.g. '/cloudsql/project:region:instance'
                    Username = Environment.GetEnvironmentVariable("DB_USER"), // e.g. 'my-db-user
                    Password = Environment.GetEnvironmentVariable("DB_PASS"), // e.g. 'my-db-password'
                    Database = Environment.GetEnvironmentVariable("DB_NAME"), // e.g. 'my-database'
                };
                connectionString.Pooling = true;
                // Specify additional properties here.
                return connectionString;
            }
        }
    }

### Go

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/golang-samples/tree/master/cloudsql/postgres/database-sql/README.md).

<br />

    package cloudsql

    import (
    	"database/sql"
    	"fmt"
    	"log"
    	"os"

    	// Note: If connecting using the App Engine Flex Go runtime, use
    	// "github.com/jackc/pgx/stdlib" instead, since v5 requires
    	// Go modules which are not supported by App Engine Flex.
    	_ "github.com/jackc/pgx/v5/stdlib"
    )

    // connectUnixSocket initializes a Unix socket connection pool for
    // a Cloud SQL instance of Postgres.
    func connectUnixSocket() (*sql.DB, error) {
    	mustGetenv := func(k string) string {
    		v := os.Getenv(k)
    		if v == "" {
    			log.Fatalf("Fatal Error in connect_unix.go: %s environment variable not set.\n", k)
    		}
    		return v
    	}
    	// Note: Saving credentials in environment variables is convenient, but not
    	// secure - consider a more secure solution such as
    	// Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
    	// keep secrets safe.
    	var (
    		dbUser         = mustGetenv("DB_USER")              // e.g. 'my-db-user'
    		dbPwd          = mustGetenv("DB_PASS")              // e.g. 'my-db-password'
    		unixSocketPath = mustGetenv("INSTANCE_UNIX_SOCKET") // e.g. '/cloudsql/project:region:instance'
    		dbName         = mustGetenv("DB_NAME")              // e.g. 'my-database'
    	)

    	dbURI := fmt.Sprintf("user=%s password=%s database=%s host=%s",
    		dbUser, dbPwd, dbName, unixSocketPath)

    	// dbPool is the pool of database connections.
    	dbPool, err := sql.Open("pgx", dbURI)
    	if err != nil {
    		return nil, fmt.Errorf("sql.Open: %w", err)
    	}

    	// ...

    	return dbPool, nil
    }

### Ruby

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/ruby-docs-samples/tree/master/cloud-sql/postgres/activerecord/README.md).

<br />

    unix: &unix
      adapter: postgresql
      # Configure additional properties here.
      # Note: Saving credentials in environment variables is convenient, but not
      # secure - consider a more secure solution such as
      # Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
      # keep secrets safe.
      username: <%= ENV["DB_USER"] %>  # e.g. "my-database-user"
      password: <%= ENV["DB_PASS"] %> # e.g. "my-database-password"
      database: <%= ENV.fetch("DB_NAME") { "vote_development" } %>
      # Specify the Unix socket path as host
      host: "<%= ENV["INSTANCE_UNIX_SOCKET"] %>"

### PHP

To see this snippet in the context of a web application, view
[the README on GitHub](https://github.com/GoogleCloudPlatform/php-docs-samples/tree/main/cloud_sql/postgres/pdo/README.md).

<br />

    namespace Google\Cloud\Samples\CloudSQL\Postgres;

    use PDO;
    use PDOException;
    use RuntimeException;
    use TypeError;

    class DatabaseUnix
    {
        public static function initUnixDatabaseConnection(): PDO
        {
            try {
                // Note: Saving credentials in environment variables is convenient, but not
                // secure - consider a more secure solution such as
                // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
                // keep secrets safe.
                $username = getenv('DB_USER'); // e.g. 'your_db_user'
                $password = getenv('DB_PASS'); // e.g. 'your_db_password'
                $dbName = getenv('DB_NAME'); // e.g. 'your_db_name'
                $instanceUnixSocket = getenv('INSTANCE_UNIX_SOCKET'); // e.g. '/cloudsql/project:region:instance'

                // Connect using UNIX sockets
                $dsn = sprintf(
                    'pgsql:dbname=%s;host=%s',
                    $dbName,
                    $instanceUnixSocket
                );

                // Connect to the database.
                $conn = new PDO(
                    $dsn,
                    $username,
                    $password,
                    # ...
                );
            } catch (TypeError $e) {
                throw new RuntimeException(
                    sprintf(
                        'Invalid or missing configuration! Make sure you have set ' .
                            '$username, $password, $dbName, ' .
                            'and $instanceUnixSocket (for UNIX socket mode). ' .
                            'The PHP error was %s',
                        $e->getMessage()
                    ),
                    (int) $e->getCode(),
                    $e
                );
            } catch (PDOException $e) {
                throw new RuntimeException(
                    sprintf(
                        'Could not connect to the Cloud SQL Database. Check that ' .
                            'your username and password are correct, that the Cloud SQL ' .
                            'proxy is running, and that the database exists and is ready ' .
                            'for use. For more assistance, refer to %s. The PDO error was %s',
                        'https://cloud.google.com/sql/docs/postgres/connect-external-app',
                        $e->getMessage()
                    ),
                    (int) $e->getCode(),
                    $e
                );
            }

            return $conn;
        }
    }

## Open and close connections

When you use a connection pool, you must open and close connections properly,
so that your connections are always returned to the pool when you are done with
them. Unreturned or "leaked" connections are not reused, which wastes resources
and can cause performance bottlenecks for your application.

### Python

    # Preparing a statement before hand can help protect against injections.
    stmt = sqlalchemy.text(
        "INSERT INTO votes (time_cast, candidate) VALUES (:time_cast, :candidate)"
    )
    try:
        # Using a with statement ensures that the connection is always released
        # back into the pool at the end of statement (even if an error occurs)
        with db.connect() as conn:
            conn.execute(stmt, parameters={"time_cast": time_cast, "candidate": team})
            conn.commit()
    except Exception as e:
        # If something goes wrong, handle the error in this section. This might
        # involve retrying or adjusting parameters depending on the situation.
        # ...

### Java

    // Using a try-with-resources statement ensures that the connection is always released back
    // into the pool at the end of the statement (even if an error occurs)
    try (Connection conn = pool.getConnection()) {

      // PreparedStatements can be more efficient and project against injections.
      String stmt = "INSERT INTO votes (time_cast, candidate) VALUES (?, ?);";
      try (PreparedStatement voteStmt = conn.prepareStatement(stmt);) {
        voteStmt.setTimestamp(1, now);
        voteStmt.setString(2, team);

        // Finally, execute the statement. If it fails, an error will be thrown.
        voteStmt.execute();
      }
    } catch (SQLException ex) {
      // If something goes wrong, handle the error in this section. This might involve retrying or
      // adjusting parameters depending on the situation.
      // ...
    }

### Node.js

    /**
     * Insert a vote record into the database.
     *
     * @param {object} pool The Knex connection object.
     * @param {object} vote The vote record to insert.
     * @returns {Promise}
     */
    const insertVote = async (pool, vote) => {
      try {
        return await pool('votes').insert(vote);
      } catch (err) {
        throw Error(err);
      }
    };

### C#

    using Npgsql;
    using System;

    namespace CloudSql
    {
        public class PostgreSqlTcp
        {
            public static NpgsqlConnectionStringBuilder NewPostgreSqlTCPConnectionString()
            {
                // Equivalent connection string:
                // "Uid=<DB_USER>;Pwd=<DB_PASS>;Host=<INSTANCE_HOST>;Database=<DB_NAME>;"
                var connectionString = new NpgsqlConnectionStringBuilder()
                {
                    // Note: Saving credentials in environment variables is convenient, but not
                    // secure - consider a more secure solution such as
                    // Cloud Secret Manager (https://cloud.google.com/secret-manager) to help
                    // keep secrets safe.
                    Host = Environment.GetEnvironmentVariable("INSTANCE_HOST"),     // e.g. '127.0.0.1'
                    // Set Host to 'cloudsql' when deploying to App Engine Flexible environment
                    Username = Environment.GetEnvironmentVariable("DB_USER"), // e.g. 'my-db-user'
                    Password = Environment.GetEnvironmentVariable("DB_PASS"), // e.g. 'my-db-password'
                    Database = Environment.GetEnvironmentVariable("DB_NAME"), // e.g. 'my-database'

                    // The Cloud SQL proxy provides encryption between the proxy and instance.
                    SslMode = SslMode.Disable,
                };
                connectionString.Pooling = true;
                // Specify additional properties here.
                return connectionString;
            }
        }
    }

### Go

    insertVote := "INSERT INTO votes(candidate, created_at) VALUES($1, NOW())"
    _, err := db.Exec(insertVote, team)

### Ruby

    @vote = Vote.new candidate: candidate

    # ActiveRecord creates and executes your SQL and automatically
    # handles the opening and closing of the database connection.
    if @vote.save
      render json: "Vote successfully cast for \"#{@vote.candidate}\" at #{@vote.time_cast} PST!"
    else
      render json: @vote.errors, status: :unprocessable_entity
    end

### PHP

    // Use prepared statements to guard against SQL injection.
    $sql = 'INSERT INTO votes (time_cast, candidate) VALUES (NOW(), :voteValue)';

    try {
        $statement = $conn->prepare($sql);
        $statement->bindParam('voteValue', $value);

        $res = $statement->execute();
    } catch (PDOException $e) {
        throw new RuntimeException(
            'Could not insert vote into database. The PDO exception was ' .
            $e->getMessage(),
            $e->getCode(),
            $e
        );
    }

> [!NOTE]
> **Note:** Most PHP applications are not long-running. They start at the beginning of request processing and shut down when request processing ends. Database connections are closed when the application shuts down.

## Connection count

Every database connection uses client and server-side resources. In addition,
Cloud SQL imposes overall connection limits that cannot be exceeded.
Creating and using fewer connections reduces overhead and helps you stay
under the connection limit.

### Python

    # Pool size is the maximum number of permanent connections to keep.
    pool_size=5,
    # Temporarily exceeds the set pool_size if no connections are available.
    max_overflow=2,
    # The total number of concurrent connections for your application will be
    # a total of pool_size and max_overflow.

### Java

    // maximumPoolSize limits the total number of concurrent connections this pool will keep. Ideal
    // values for this setting are highly variable on app design, infrastructure, and database.
    config.setMaximumPoolSize(5);
    // minimumIdle is the minimum number of idle connections Hikari maintains in the pool.
    // Additional connections will be established to meet this value unless the pool is full.
    config.setMinimumIdle(5);

### Node.js

    // 'max' limits the total number of concurrent connections this pool will keep. Ideal
    // values for this setting are highly variable on app design, infrastructure, and database.
    config.pool.max = 5;
    // 'min' is the minimum number of idle connections Knex maintains in the pool.
    // Additional connections will be established to meet this value unless the pool is full.
    config.pool.min = 5;

### C#

    // MaxPoolSize sets maximum number of connections allowed in the pool.
    connectionString.MaxPoolSize = 5;
    // MinPoolSize sets the minimum number of connections in the pool.
    connectionString.MinPoolSize = 0;

### Go

    // Set maximum number of connections in idle connection pool.
    db.SetMaxIdleConns(5)

    // Set maximum number of open connections to the database.
    db.SetMaxOpenConns(7)

### Ruby

    # 'pool' is the maximum number of permanent connections to keep.
    pool: 5

### PHP

[PDO](https://www.php.net/manual/en/book.pdo.php) currently doesn't offer any functionality to configure connection limits.

## Exponential backoff

If your application attempts to connect to the database and does not succeed,
the database could be temporarily unavailable. In this case, sending repeated
connection requests wastes resources. It is preferable to wait before sending
additional connection requests in order to allow the database to become
accessible again. Using an exponential backoff or other delay mechanism achieves
this goal.

This retry only makes sense when first connecting, or when first grabbing a
connection from the pool. If errors happen in the middle of a transaction, the
*application* must do the retrying, and it must retry from the beginning of a
transaction. So even if your pool is configured properly, the application might
still see errors if connections are lost.

### Python

    # SQLAlchemy automatically uses delays between failed connection attempts,
    # but provides no arguments for configuration.

### Java

    // Hikari automatically delays between failed connection attempts, eventually reaching a
    // maximum delay of `connectionTimeout / 2` between attempts.

### Node.js

    // 'knex' uses a built-in retry strategy which does not implement backoff.
    // 'createRetryIntervalMillis' is how long to idle after failed connection creation before trying again
    config.pool.createRetryIntervalMillis = 200; // 0.2 seconds

### C#

    Policy
        .Handle<NpgsqlException>()
        .WaitAndRetry(new[]
        {
            TimeSpan.FromSeconds(1),
            TimeSpan.FromSeconds(2),
            TimeSpan.FromSeconds(5)
        })
        .Execute(() => connection.Open());

### Go

The [database/sql](http://go-database-sql.org/) package currently doesn't offer any functionality to configure exponential backoff.

### Ruby

    # ActiveRecord automatically uses delays between failed connection attempts,
    # but provides no arguments for configuration.

### PHP

[PDO](https://www.php.net/manual/en/book.pdo.php) currently doesn't offer any functionality to configure exponential backoff.

## Connection timeout

There are many reasons why a connection attempt might not succeed. Network
communication is never guaranteed, and the database might be temporarily unable
to respond. Make sure your application handles broken or unsuccessful
connections gracefully.

### Python

    # 'pool_timeout' is the maximum number of seconds to wait when retrieving a
    # new connection from the pool. After the specified amount of time, an
    # exception will be thrown.
    pool_timeout=30,  # 30 seconds

### Java

    // setConnectionTimeout is the maximum number of milliseconds to wait for a connection checkout.
    // Any attempt to retrieve a connection from this pool that exceeds the set limit will throw an
    // SQLException.
    config.setConnectionTimeout(10000); // 10 seconds
    // idleTimeout is the maximum amount of time a connection can sit in the pool. Connections that
    // sit idle for this many milliseconds are retried if minimumIdle is exceeded.
    config.setIdleTimeout(600000); // 10 minutes

### Node.js

    // 'acquireTimeoutMillis' is the number of milliseconds before a timeout occurs when acquiring a
    // connection from the pool. This is slightly different from connectionTimeout, because acquiring
    // a pool connection does not always involve making a new connection, and may include multiple retries.
    // when making a connection
    config.pool.acquireTimeoutMillis = 60000; // 60 seconds
    // 'createTimeoutMillis` is the maximum number of milliseconds to wait trying to establish an
    // initial connection before retrying.
    // After acquireTimeoutMillis has passed, a timeout exception will be thrown.
    config.pool.createTimeoutMillis = 30000; // 30 seconds
    // 'idleTimeoutMillis' is the number of milliseconds a connection must sit idle in the pool
    // and not be checked out before it is automatically closed.
    config.pool.idleTimeoutMillis = 600000; // 10 minutes

### C#

    // Timeout sets the time to wait (in seconds) while
    // trying to establish a connection before terminating the attempt.
    connectionString.Timeout = 15;

### Go

The [database/sql](http://go-database-sql.org/) package currently doesn't offer any functionality to configure connection timeout. Timeout is configured at the driver level.

### Ruby

    # 'timeout' is the maximum number of seconds to wait when retrieving a
    # new connection from the pool. After the specified amount of time, an
    # ActiveRecord::ConnectionTimeoutError will be raised.
    timeout: 5000

### PHP

    // Here we set the connection timeout to five seconds and ask PDO to
    // throw an exception if any errors occur.
    [
        PDO::ATTR_TIMEOUT => 5,
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]

## Connection duration

Limiting a connection's lifetime can help prevent abandoned connections from
accumulating. You can use the connection pool to limit your connection
lifetimes.

### Python

    # 'pool_recycle' is the maximum number of seconds a connection can persist.
    # Connections that live longer than the specified amount of time will be
    # re-established
    pool_recycle=1800,  # 30 minutes

### Java

    // maxLifetime is the maximum possible lifetime of a connection in the pool. Connections that
    // live longer than this many milliseconds will be closed and reestablished between uses. This
    // value should be several minutes shorter than the database's timeout value to avoid unexpected
    // terminations.
    config.setMaxLifetime(1800000); // 30 minutes

### Node.js

The '[knex](https://github.com/knex/knex)' Node.js library currently doesn't offer any functionality to
control the duration of a connection.

### C#

    // ConnectionIdleLifetime sets the time (in seconds) to wait before
    // closing idle connections in the pool if the count of all
    // connections exceeds MinPoolSize.
    connectionString.ConnectionIdleLifetime = 300;

### Go

    // Set Maximum time (in seconds) that a connection can remain open.
    db.SetConnMaxLifetime(1800 * time.Second)

### Ruby

[ActiveRecord](https://github.com/rails/rails/tree/master/activerecord) currently doesn't offer any functionality to control the duration of a connection.

### PHP

[PDO](https://www.php.net/manual/en/book.pdo.php) currently doesn't offer any functionality to control the duration of a connection.

## View the complete application

To see the complete application, click the link below.

### Python

View the [complete application](https://github.com/GoogleCloudPlatform/python-docs-samples/blob/master/cloud-sql/postgres/sqlalchemy/README.md)
for the Python programming language.

### Java

View the [complete application](https://github.com/GoogleCloudPlatform/java-docs-samples/tree/master/cloud-sql/postgres/servlet)
for the Java programming language.

### Node.js

View the [complete application](https://github.com/GoogleCloudPlatform/nodejs-docs-samples/blob/master/cloud-sql/mysql/mysql/README.md)
for the Node.js programming language.

### C#

View the [complete application](https://github.com/GoogleCloudPlatform/dotnet-docs-samples/blob/master/cloud-sql/postgres/README.md)
for the C# programming language.

### Go

View the [complete application](https://github.com/GoogleCloudPlatform/golang-samples/blob/master/cloudsql/postgres/database-sql/README.md)
for the Go programming language.

### Ruby

View the [complete application](https://github.com/GoogleCloudPlatform/ruby-docs-samples/tree/master/cloud-sql/postgres/activerecord)
for the Ruby programming language.

### PHP

View the [complete application](https://github.com/GoogleCloudPlatform/php-docs-samples/tree/main/cloud_sql/postgres/pdo)
for the PHP programming language.

## What's next

- Learn more about [Private IP](https://docs.cloud.google.com/sql/docs/postgres/private-ip).
- Learn about [quotas and limits](https://docs.cloud.google.com/sql/docs/postgres/quotas) for Cloud SQL and App Engine.
- Learn about [best practices](https://docs.cloud.google.com/sql/docs/postgres/best-practices) for working with Cloud SQL.
- Learn more about [connecting from an external application](https://docs.cloud.google.com/sql/docs/postgres/connect-external-app).