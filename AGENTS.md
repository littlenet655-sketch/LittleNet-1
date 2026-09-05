# AGENTS.md

## Role
You build. The human describes the product in one paragraph. You select stack, UI kit, skills, and components. No per-widget questions.

## Always
1. Read this file.
2. Use Context7 before coding against a library.
3. Use 21st or shadcn CLI before inventing a component.
4. Use Playwright to verify a UI path you just created.
5. Use find-skills when you lack a procedure.

## Stack
- **Web app**: Next.js App Router + TypeScript + Tailwind CSS v4 + shadcn/ui
- **Dashboard chrome**: shadcn-admin patterns (sidebar, topbar, table, drawer, settings)
- **Marketing motion**: Magic UI / Aceternity-style via shadcn CLI or 21st search — never a second design system
- **App blocks**: ReUI / Kibo / Origin / 21st catalog when a block already exists
- **Chat / agent UI**: assistant-ui or CopilotKit (controlled generative UI = OUR components)
- **Python / multi-agent backends**: FastAPI
- **SaaS auth + billing**: Better Auth or Auth.js + Stripe or Polar from a known starter. Do not hand-roll auth.
- **VS Code extension**: official VS Code contribution model + webview. Webview UI still uses the same tokens as the web app if a companion dashboard exists.
- **CLI**: one command surface, JSON + human output.
- **Forbidden**: MUI, Chakra, Ant, Bootstrap, random CSS frameworks, a second icon set, a second color system.
- **Install UI with**: `npx shadcn@latest add <name>` or 21st search + install. Never hand-roll Button, Input, Table, Dialog, Form, Sidebar, Tabs, Chart.

## How You Research (Agent Search — Mandatory)
Before writing code that touches a library you are not 100% sure about:
1. Context7 / ctx7 docs for that library + current version.
2. If the question is "does a component already exist?": 21st search, then shadcn registry, then ReUI.
3. If the question is "how does this repo / API / issue actually work?": Firecrawl developer search or GitHub search. Read the README and the last relevant issue/PR.
4. If the question is "is the UI I just built real?": Playwright — open it, click the primary path, fix what broke.
5. If you lack a workflow: find-skills, install one skill, follow it.
Do not invent APIs from memory when Context7 is available.

## UI kit by idea
- **A. Landing / waitlist / launch**: shadcn + Magic UI / Aceternity / 21st marketing blocks. Sections: nav, hero + one CTA, proof, 3-feature bento, pricing, FAQ, footer. Dark, sparse, high contrast. No dashboard shell on a marketing page.
- **B. B2B SaaS dashboard (security, cost, compliance, admin)**: shadcn-admin + ReUI / Kibo / 21st app blocks. Sidebar app, KPI row, filterable table, detail drawer, settings, billing. Look: Linear / Vercel / Stripe. Dense and quiet. Trust > decoration.
- **C. Conversational / WhatsApp / voice console**: assistant-ui or CopilotKit. Transcript, tool-call cards, citations, approve/reject for side effects. Mobile-first empty states. English first; Kannada-ready copy structure.
- **D. VS Code extension + optional companion CLI / web**:
  - Extension: package.json contributes, commands, views, webview or TreeView.
  - Webview: same shadcn tokens as the SaaS dashboard if both exist.
  - Marketing site for the extension uses kit A only. Never wrap a fake Next.js dashboard inside the webview.
- **E. India ops tools (GST, clinic, school, RTO, forms)**: shadcn forms + tables + stepper + printable/PDF output. Large tap targets, obvious primary button, bilingual-ready strings.

### RAKSHEX / DEVPULSE (when the idea is this product)
- **Product**: AI cybersecurity SaaS + VS Code extension.
- **Jobs**: real-time secrets/token/password detection in code, Postman, repos; OWASP/compliance scanning; LLM API cost intelligence.
- **Surfaces that may exist together**:
  1. VS Code extension (kit D) — scan current file / workspace, inline diagnostics, panel of findings
  2. CLI `npx rakshex scan` — CI and local
  3. SaaS dashboard (kit B) — org, repos, findings inbox, policy, cost of LLM calls, billing
  4. Marketing site (kit A) — rakshex.in style launch page only
- **First vertical slice unless specified otherwise**: Extension or CLI that scans a folder for high-confidence secrets and prints / shows a findings list. Dashboard and billing come AFTER that slice works.
- **Visual**: kit B. Security product. No neon hacker aesthetic, no particle heroes.
- **Search, don't guess**: VS Code Extension API via Context7, secret-pattern prior art via GitHub/Firecrawl, shadcn table/drawer via 21st or shadcn CLI.

## Definition of done
One user path works end-to-end with real kit UI, current docs, and no placeholder buttons.

## Stop rule
After a working slice, name the next 3 files. Do not expand scope.
