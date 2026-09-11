# 10 — Web & Legacy UI Audit Report

**Audited Date:** 2026-09-08  
**Audit Scope:** Flask/Jinja2 templates, static JavaScript/CSS assets, active operator dependencies vs. dead code analysis.  

---

## 1. Template Classification & Reference Audit

Execution of `python tools/audit_templates.py` and our static inventory confirmed **77 total HTML templates** across the repository:

| Category | Count | Status | Purpose & Life Cycle |
| :--- | :---: | :---: | :--- |
| **Admin & Moderation Operator UI** | 12 | **Active / Required** | Used by desktop browser administrators to inspect live queues, ban accounts, audit logs, and review flagged media. |
| **Parent Web Console** | 18 | **Active / Required** | Browser interface for parents configuring screen time, reviewing safety alerts, and completing email OTP / adult liveness. |
| **Auth & Security Verification** | 14 | **Active / Required** | Core web authentication screens, CSRF tokens, and biometric liveness capture canvases. |
| **Child Browser Feed / Stories** | 25 | **Active / Legacy Support** | Web-based view of feeds, reels, and stories used for browser testing, desktop users, and automated E2E test fixtures. |
| **Unreferenced / Dead Templates** | 8 | **Retire Candidates** | Standalone landing page variations and obsolete prototype screens. |

---

## 2. Retention Guidelines

Per project rules, server-rendered templates must **NOT** be deleted simply because the primary mobile application is Flutter:
1. **Admin & Moderation**: The admin dashboard (`/admin/`) is intentionally a desktop web console for human review and auditing.
2. **E2E Testing Fixtures**: Several test suites rely on web session routes to verify core backend state machines.
3. **Safe Removal Gate**: Unreferenced templates should only be pruned after the full V2 transition is deployed and verified.

---

## 3. Client JavaScript Syntax Verification

`tools/audit_all.py` validated the core client JavaScript files using `node --check`:
- `static/js/littlenet.js`: PASS
- `static/js/live_safety.js`: PASS
- `static/js/chat.js`: PASS
- `static/js/stories.js`: PASS
Zero syntax or packaging errors detected.
