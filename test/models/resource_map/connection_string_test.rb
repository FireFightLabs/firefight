require "test_helper"

class ResourceMap::ConnectionStringTest < ActiveSupport::TestCase
  def parse(value, **) = ResourceMap::ConnectionString.parse(value, **)&.to_h

  test "a URL gives its scheme, host, port, database and user, a driver's name read as its engine" do
    assert_equal({ scheme: "postgresql", host: "ep-cool-river-123.eu-central-1.aws.neon.tech", port: 5432, database: "app", user: "app_owner" },
                 parse("postgres://app_owner:s3cret@ep-cool-river-123.eu-central-1.aws.neon.tech/app?sslmode=require"))
    assert_equal({ scheme: "postgresql", host: "db.internal", port: 6432, database: "orders", user: "svc" },
                 parse("postgresql+psycopg2://svc:pw@db.internal:6432/orders"))
    assert_equal({ scheme: "mysql", host: "aws.connect.psdb.cloud", port: 3306, database: "shop", user: "abc123" },
                 parse("mysql2://abc123:pscale_pw_x@aws.connect.psdb.cloud/shop?ssl={}"))
  end

  test "a password holding an @, a slash, a colon or a question mark still finds the host" do
    assert_equal "db.example.com", parse("postgres://user:p@ss/w:rd@db.example.com:5433/app")[:host]
    assert_equal 5433, parse("postgres://user:p@ss/w:rd@db.example.com:5433/app")[:port]
    assert_equal "user", parse("postgres://user:p@ss@db.example.com/app")[:user]
    assert_equal "u@x", parse("postgres://u%40x:pw@db.example.com/app")[:user]
  end

  test "an IPv6 address in brackets, and a missing port taken from the scheme" do
    assert_equal({ scheme: "postgresql", host: "2001:db8::1", port: 5432, database: "app", user: "me" }, parse("postgres://me:pw@[2001:db8::1]/app"))
    assert_equal({ scheme: "redis", host: "::1", port: 6380, database: "0", user: "default" }, parse("redis://default:pw@[::1]:6380/0"))
    assert_equal 6379, parse("rediss://default:pw@clean-crab-89681.upstash.io")[:port]
    assert_equal "rediss", parse("rediss://default:pw@clean-crab-89681.upstash.io")[:scheme]
    assert_equal 443, parse("libsql://app-acme.turso.io")[:port]
  end

  test "JDBC, libpq's key=value and the .NET form" do
    assert_equal({ scheme: "postgresql", host: "db.example.com", port: 5432, database: "app", user: "svc" },
                 parse("jdbc:postgresql://db.example.com:5432/app?user=svc&password=pw"))
    assert_equal({ scheme: "sqlserver", host: "acme.database.windows.net", port: 1433, database: "orders", user: "admin" },
                 parse("jdbc:sqlserver://acme.database.windows.net:1433;databaseName=orders;user=admin;password=pw"))
    assert_equal({ scheme: "postgresql", host: "db.example.com", port: 5433, database: "app", user: "svc" },
                 parse("host=db.example.com port=5433 dbname=app user=svc password='a b\\'c'"))
    assert_equal({ scheme: "sqlserver", host: "acme.database.windows.net", port: 1433, database: "orders", user: "admin" },
                 parse("Server=tcp:acme.database.windows.net,1433;Initial Catalog=orders;User ID=admin;Password=p;w"))
    assert_equal({ scheme: "postgresql", host: "acme.postgres.database.azure.com", port: 5432, database: "app", user: "svc" },
                 parse("Server=acme.postgres.database.azure.com;Database=app;User Id=svc;Password=pw", scheme: "PostgreSQL"))
    assert_equal({ scheme: "oracle", host: "ora.example.com", port: 1522, database: nil, user: nil }, parse("jdbc:oracle:thin:@//ora.example.com:1522/svc"))
  end

  test "a value that names no host, or only a socket, is nothing, and nothing raises or echoes what it was given" do
    [ nil, "", "true", "8080", "a=b;c=d", "postgres:///app?sslmode=require", "https://", "not a url", "postgres://u:p@host:notaport/db",
      "%zz://x", "x" * 5000, "postgresql:///app?host=/var/run/postgresql", "postgresql://u:p@/app?host=/cloudsql/acme:eu:db" ].each do |value|
      assert_nil ResourceMap::ConnectionString.parse(value), value.inspect.first(40)
    end
  end

  test "the query names the host when the address does not" do
    assert_equal "db.example.com", parse("postgresql:///app?host=db.example.com&port=5434")[:host]
    assert_equal 5434, parse("postgresql:///app?host=db.example.com&port=5434")[:port]
  end

  test "the first of several hosts" do
    assert_equal({ scheme: "postgresql", host: "one.example.com", port: 5432, database: "app", user: "u" },
                 parse("postgresql://u:p@one.example.com:5432,two.example.com:5432/app"))
  end
end
