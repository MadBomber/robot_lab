### Local Agent Context: .architecture

# Setup & Commands — Exact commands + required env vars.

- Configure project: Verify `project_name` and `version` in `.architecture/config.yml` are correct for current setup.
- Quarterly review schedule is enforced automatically; ensure `review_schedule` is set to `quarterly` in `.architecture/config.yml`.

# Code Style & Patterns — Must-follow conventions, backticked.

- Ensure any new architectural documentation follows the naming pattern in `.architecture/reviews`.
- For member roles, adhere to the structured format in `.architecture/members.yml` with fields like `id`, `name`, `title`, and `specialties`.
- Document architectural reviews extensively, mirroring the detailed style found in `.architecture/reviews/feature-free-will.md`.

# Implementation Details — Entry files + compressed playbooks (job/env/rollout).

## Architectural Review Process

1. **Conduct Review**:
   - Read current state and previous findings in `.architecture/reviews/overall-codebase.md`.
   - Compare changes and new resolutions against previous entries like `.architecture/reviews/feature-free-will.md`.

2. **Document Review**:
   - Record new findings and updates in a new markdown file within `.architecture/reviews/`.
   - Follow the format example in existing review files for consistency and effectiveness.

3. **Remove Dead Code**:
   - Audit `network:` parameter usage in relevant function calls.
   - Remove unused parameters and adjust corresponding method calls as documented in reviews.

_Warning_: Removing architectural elements based on outdated assumptions can be destructive.

By following these structured guidelines and file-specific practices, maintain a coherent and robust architectural documentation process inside the `.architecture` directory.
