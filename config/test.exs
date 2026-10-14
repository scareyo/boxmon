import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :boxmon, BoxmonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "tAVZ2snfvfRQoWNjD8TfacoaN9asrbWTkGwhGGDHLvG7hIYV/pnc5IVJQ0kye32H",
  server: false

# In test we don't send emails
config :boxmon, Boxmon.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# The monitor is started per test; HTTP goes to Req.Test stubs.
config :boxmon, start_monitor: false

config :boxmon, :seedbox,
  qbit_url: "http://qbit.test",
  qbit_api_key: "qbt_test",
  remote_root: "/data",
  http_url: "http://files.test/dl",
  http_user: "user",
  http_pass: "pass",
  download_dir: "tmp/test-downloads",
  chunk_size: 4,
  connections: 4,
  categories: ["tv"],
  req_options: [plug: {Req.Test, Boxmon.Seedbox}, retry: false]
