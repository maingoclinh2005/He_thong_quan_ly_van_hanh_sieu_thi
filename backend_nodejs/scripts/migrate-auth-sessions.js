// Historical entry point intentionally does not execute untracked SQL anymore.
console.error('Use npm run migrate:status and the versioned migration workflow documented in docs/migrations.md.');
process.exitCode = 1;
