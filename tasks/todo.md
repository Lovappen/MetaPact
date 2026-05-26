# Memory Context Control Design

- [x] Explore repository context and current memory writer
- [x] Check required project state files
- [x] Run requested consistency check or identify equivalent
- [x] Clarify desired memory behavior
- [x] Compare candidate approaches
- [x] Present recommended design
- [x] Task 1: Add failing tests for memory category and length gates
- [x] Task 2: Implement `memory-write.sh --category` validation and concise-entry limits
- [x] Task 3: Update memory-writing instructions and examples
- [x] Task 4: Run focused tests and repository checks
- [x] Review result

## Notes

- `PROGRESS.md`, `DECISIONS.md`, and `tasks/lessons.md` are not present in this repository.
- `make check` is not defined; current checks appear to be `tests/*.sh`, selected Python tests, and `nako/scripts/smoke-test.sh`.
- Current memory writer is `nako/agent/scripts/memory-write.sh`.
- `bash tests/memory-write.sh` passes.
- User wants only meaningful information written; routine or irrelevant conversation should not be persisted.

## Implementation Plan

Goal: prevent accidental transcript/routine-chat persistence by requiring every memory write to declare a meaningful category and stay concise.

Files:

- Modify `tests/memory-write.sh` to test allowed categories, missing/invalid categories, and long-summary rejection.
- Modify `nako/agent/scripts/memory-write.sh` to require `--category` and reject oversized entries.
- Modify `nako/agent/AGENTS.md`, `nako/agent/MEMORY.md`, `nako/agent/TOOLS.md`, and public docs examples so future calls include category guidance.

Validation:

- First run `bash tests/memory-write.sh` after test changes and confirm it fails for missing implementation.
- Then run `bash tests/memory-write.sh` after implementation and confirm it passes.
- Run relevant grep-based checks that mention `memory-write.sh`.

## Review

- Added a required memory category and concise-entry limits to prevent accidental transcript-style writes.
- Updated agent instructions and docs so future examples use `--category`.
- Verified `bash tests/memory-write.sh`, `bash tests/cc-connect-default.sh`, `bash -n nako/agent/scripts/memory-write.sh`, and `git diff --check`.
- `make check` is still unavailable because the repository has no `check` target.
