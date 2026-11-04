# Inception — Claude Code Project Context

Project context for any session on any machine.

## Goal

**42 School project: Inception (v5.3), mandatory part only.** The user (intra login `akuzmin`) must
be able to understand, explain, rebuild and defend every part of it. Knowledge ready by 2026-11-09;
the school VM is only available after 11-09, so the defense is on 11-10 or 11-11. **Bonus is out of
scope** until Core has been defended. Old bonus notes: `git show 538da7a:materials-inception/learning-plan.md`.

## Sources of truth, in priority order

1. `materials-inception/sources/subject.pdf` — the Subject. Wins over everything.
2. `materials-inception/sources/evaluation-scale.pdf` — an older copy of the current evaluation scale.
3. Everything else. If it contradicts 1 or 2, change it and explain why.

## Where things are

`START-HERE.md` holds the day-by-day plan, the phrases the user will use, and readiness criteria.

```
Inception/                      submitted; its CONTENTS go to the root of the Intra repo
materials-inception/lessons/    the course, lessons 0-8
materials-inception/my-work/    the user's answers (answers.md) and lab reports (labs.md)
materials-inception/answer-key.md   grading key for answers.md
materials-inception/defense/    runbook.md (real scale, port drills, hard questions), commands.md
tests/check_inception_rules.sh  static rule linter
```

Git-ignored and created per machine with `make init`: `Inception/srcs/.env`, `Inception/secrets/*.txt`.

## How Claude should behave in this project

- The user is here to LEARN. Explain WHY, let them try first, then review. Never fill in `my-work/`.
- **"проверь блок X":** grade `my-work/answers.md` strictly with `answer-key.md`, 0-100% per question;
  pass is an average of 90% or more. Name exactly what is missing.
- **"проверь лабу N":** read that section of `my-work/labs.md`, verify outputs against the lesson, then
  ask follow-up questions about the "своими словами" answers.
- **"проведи защиту":** follow the scale, one question at a time, as a strict evaluator, no hints,
  debrief at the end.
- **"сломай мне проект":** introduce one realistic fault in a scratch copy or branch without saying what
  it is; the user diagnoses it from logs.
- Keep lessons truthful: commands in `lessons/` and `defense/` were all run on Debian 12 with Docker 29.
  Re-run anything you change.
- The Docker host on the user's Mac also holds other projects. Never run the evaluator's purge command or
  `prune` there. Test in an isolated environment.

## Decisions that differ from common Inception solutions

Each came from testing against the evaluation scale. Keep them unless the scale changes.

| Decision | Reason |
|---|---|
| `mysqld --bootstrap`, no `mysqld &` | the scale ends the evaluation on any background program in an entrypoint |
| `WP_DB_HOST`, not `MYSQL_HOST` | the MariaDB client reads `MYSQL_HOST`, which broke `mariadb -u root -p` in the container |
| `restart: unless-stopped` | with `on-failure`, `kill 1` (exit 0) leaves the container down |
| `fastcgi_param HTTP_HOST $http_host` | without it a non-default port causes a redirect loop |
| `config set` on every start | `wp-config.php` is on the volume; port changes must reach it |
| Per-step checks in `setup.sh` | a shared marker broke when install was interrupted |
| Healthchecks + `up --wait` | `make` returns only when the site answers |
| `sudo rm -rf` in `fclean` | the data is owned by `mysql` and `www-data`; `down -v` does not delete the files of a bind-backed volume |
| No forbidden literals even in comments | the scale says these strings must not appear; a `grep` must come back clean |
