# Schema Migrations and Ephemeral Test Databases

* Tool: golang-migrate + numbered SQL files + a CI-only Postgres service container
* Summary: A migration chain is code with a contract — every up has a down that truly reverses it, and CI proves the contract on a database that exists only for the run
* Phase introduced: 03-app-ci-cd-walking-skeleton
* Related ADRs: athena-app/docs/adr/0003-media-service-scope-and-deliberate-uninstrumentation.md
* Last reviewed: 2026-08-04

## Mental model

Migrations are an append-only ledger of schema truth — numbered SQL pairs
applied in order, tracked in a schema_migrations table. My CI job spins up
a throwaway Postgres service container, runs the chain up, all the way back
down to empty, then up again before the integration tests run. The
down-to-empty leg is the valuable one. It proves every down actually
reverses its up, not merely that the ups apply once.

## Common interview questions

**Why plain SQL files over ORM auto-migration?** I want the reviewed diff
to be exactly what executes, and SQL files give me that. They also force me
to write the rollback myself instead of trusting a diff engine to infer
one. I picked golang-migrate over goose because I need no Go-code
migrations, and over Atlas because declarative schema-as-code is a
different workflow than the traditional-ops pattern I am demonstrating.

**Where does the CI database's connection string come from?** I compose it
entirely from the job's own service container — never a repository secret,
never anything naming a real database. My acceptance criteria literally
grep the workflow for secret-referencing database variables and require
zero hits. An ephemeral test database that could reach production data is
not ephemeral, it is a breach.

**How do you handle data migrations, not just DDL?** My seeded demo users
ride the same chain as a numbered migration, and its down deletes exactly
those rows. For production-scale backfills I separate schema from data —
expand first, backfill online, contract later. A migration that rewrites a
large table inside the deploy path is an outage with a version number.

**How does this connect to zero-downtime deploys?** Through the
expand-and-contract discipline. I add the new column nullable, ship code
that writes both shapes, backfill, and only then land the contracting
migration once no reader needs the old shape. Keeping the chain reversible
at every step is what makes a mid-sequence rollback survivable.

## Gotchas hit in this project

* `migrate down` without a step count is interactive — in CI I pass the
  explicit flag so the job never hangs waiting for confirmation.
* The migration job's test scope needed narrowing so unit-only packages do
  not spin against the service container — found live while unblocking the
  first clean run.
* Seed data belongs in a migration with a precise down, or the down-to-
  empty leg fails on rows nobody remembers inserting.

## War stories

**The chain that proved itself backwards.** My four-step chain passed every
up-only run for days. The first down-to-empty leg in CI failed instantly —
an index my up created was not dropped by its down, something no forward
test would ever catch. I fixed the down, and I now treat "the chain runs
backwards to zero" as the real definition of done for any migration.

## Command cheat-sheet

```bash
migrate -path migrations -database "$DB_URL" up
migrate -path migrations -database "$DB_URL" down -all    # the leg that finds lies
migrate -path migrations -database "$DB_URL" version
psql "$DB_URL" -c 'select * from schema_migrations;'
```
