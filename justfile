default:
  just --list

run:
  PHX_SERVER=true \
  SECRET_KEY_BASE=$(mix phx.gen.secret) \
  RELEASE_COOKIE=$(openssl rand -hex 32) \
  nix run . -- start

dev:
  mix phx.server
