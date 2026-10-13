# Helpdesk API

A helpdesk SaaS backend built with Ruby on Rails and PostgreSQL. It provides a [JSON API](docs/openapi.yaml)
for a separate customer portal and staff dashboard.

## Features

- Business signup, email verification, sign-in, profiles, and password recovery.
- Owner-managed cancellation, reactivation, and permanent tenant cleanup.
- Customer requests and staff ticket management, including public replies,
  private notes, priorities, search, and filters.
- Team invitations, admin and agent roles, user suspension, and assignments.
- Groups and staff memberships for organizing support work.
- Email integration, with replies threaded into conversations.
- Duplicate ticket merging.

## Getting started

Install Ruby 4.0.7, Bundler, and PostgreSQL 18 or later. Start PostgreSQL and
make sure your database role can create databases. Rails 8.1.4 and the other
application dependencies are installed by Bundler.

From the project directory:

```sh
bundle install
export DATABASE_URL=postgresql:///helpdesk_development
bin/rails db:prepare
bin/rails server -p 3000
```

Adjust `DATABASE_URL` if PostgreSQL requires a host, username, or password.
Run `bin/rails db:prepare` again after pulling changes that add migrations.

The API runs at `http://localhost:3000`.

## Background jobs and storage

Development and production use [Solid Queue](https://github.com/rails/solid_queue)
for background jobs, including incoming email processing and outgoing email
delivery. Jobs are stored in the application's PostgreSQL database;
`bin/rails db:prepare` installs the queue tables.

Start the worker in another terminal with the same database configuration:

```sh
DATABASE_URL=postgresql:///helpdesk_development bin/jobs
```

Worker settings are in `config/queue.yml`. Production also runs daily account
purging and finished-job cleanup defined in `config/recurring.yml`. The default worker has three threads
and needs a database connection pool of at least five.

Incoming messages use private disk storage configured in `config/storage.yml`:
`storage/` in development and production, and temporary storage in tests.

For production, set `RAILS_ENV=production`, `DATABASE_URL`, and a persistent
`SECRET_KEY_BASE` (or configure the secret through Rails credentials). Run
`bin/rails db:prepare`, then run the web server and `bin/jobs` under your process
manager. Both processes need the same configuration and access to the same
message storage. Preserve `storage/` across deployments.

## Tests

The test suite uses Rails' built-in Minitest support and fixtures. Run it against
a separate PostgreSQL database:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///helpdesk_test bin/rails db:prepare
DATABASE_URL=postgresql:///helpdesk_test bin/rails test
```

Use a local PostgreSQL superuser for tests so Rails can load fixtures with foreign
keys and create parallel test databases. The test environment defaults to
`helpdesk_test`; an explicit `DATABASE_URL` overrides that default.

To run one file, append its path to the test command. Set `PARALLEL_WORKERS=1`
to run the suite in a single process. Action Mailer's test delivery method captures
outgoing messages in memory; mail assertions perform the queued delivery jobs.
Inbound message storage uses temporary directories that are removed after each test.
Incoming email is processed inline in tests; other jobs use Rails' test adapter,
so the test suite does not need a worker.

## Linting

We use [Standard](https://github.com/standardrb/standard) for Ruby style checks:

```sh
bin/standardrb
```

Run `bin/standardrb --fix` to apply automatic corrections.

## Configuration

Configure the app through environment variables before starting the server.

| Variable | Default | Purpose |
| --- | --- | --- |
| `DATABASE_URL` | `postgresql:///helpdesk_<environment>` | PostgreSQL connection URL for application data and jobs. |
| `HELPDESK_FRONTEND_URL` | `http://localhost:3001` | Frontend origin used for email links and CORS. Use an HTTP(S) origin without a path. |
| `HELPDESK_MAIL_FROM` | `support@example.test` | Sender address for outgoing messages. |
| `HELPDESK_SUPPORT_DOMAIN` | `support.example.test` | Domain for incoming support and ticket reply addresses. |
| `RAILS_INBOUND_EMAIL_PASSWORD` | Unset | Password for the Action Mailbox relay ingress. |
| `SECRET_KEY_BASE` | Rails default | Set a persistent production secret here or in Rails credentials. Development and test use Rails' local secret. |
| `JOB_CONCURRENCY` | `1` | Number of Solid Queue worker processes, each with three threads. |
| `RAILS_LOG_LEVEL` | `info` | Production log level; logs go to standard output with request IDs. |

Outgoing messages use Action Mailer. Verification, password reset, and invitation
links point to the frontend, which submits their tokens to the API. In development,
delivery is disabled. To deliver mail locally, configure Action Mailer's SMTP
settings in `config/environments/development.rb` and enable `perform_deliveries`.

Production delivers through SMTP. Configure your provider's settings under `smtp`
in Rails credentials using `bin/rails credentials:edit`, for example:

```yaml
smtp:
  address: smtp.example.com
  port: 587
  domain: example.com
  user_name: your-smtp-username
  password: your-smtp-password
  authentication: plain
  enable_starttls_auto: true
```

Businesses receive support email at `<subdomain>@<HELPDESK_SUPPORT_DOMAIN>`.
An email relay must forward incoming messages to
`/rails/action_mailbox/relay/inbound_emails`. See the
[email channel notes](docs/email-channel.md) for processing and reply behavior.
