# Tales of Pirates playtest server

Content and config for the playtest server.

To run a host, copy `.env.example` to `.env`, set the passwords and set `COMPOSE_PROFILES` to `host1` or `host2`. Then run `docker compose up -d`.

To run the whole server on one host, set `COMPOSE_PROFILES=host1,host2`.

On host #1 of the playtest, set `COMPOSE_PROFILES=host1,signup` to also run the signup page.

To upgrade the engine, change the image tag in `compose.yaml`.
