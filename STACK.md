# STACK.md

## Locked Libraries & Engineering Standards

### 1. Web Core & Framework
- **Next.js (App Router) + TypeScript**: Standard web framework for routing, SSR, and API layers.
- **Tailwind CSS v4**: Styling engine. Generate design tokens once; maintain strict aesthetic consistency.

### 2. UI & Component System
- **shadcn/ui**: Base component primitives (`Button`, `Input`, `Dialog`, `Table`, `Form`, `Tabs`, `Sidebar`, `Chart`). Add via `npx shadcn@latest add <name>`.
- **shadcn-admin**: For SaaS chrome, multi-page administrative dashboards, settings panels, data tables, drawers, and sidebars.
- **ReUI / Kibo / Origin / 21st catalog**: Pre-built application blocks when an existing pattern matches requirements.
- **Magic UI / Aceternity**: Marketing motion, animated hero sections, proof banners, interactive bento grids (shadcn CLI or 21st search).
- **Strict Prohibition**: Never introduce MUI, Chakra, Ant Design, Bootstrap, random CSS frameworks, a second icon set, or a second color system.
- **Component Rule**: Never hand-roll `Button`, `Input`, `Table`, `Dialog`, `Form`, `Sidebar`, `Tabs`, `Chart`.

### 3. Agent & Chat Interfaces
- **assistant-ui / CopilotKit**: Controlled generative UI for chat and agent consoles (render typed app components, transcripts, citations, tool cards, approve/reject dialogs — never unformatted raw HTML).

### 4. Backend Services & Agents
- **FastAPI**: Python backend services, background workers, and AI agent execution runtimes.

### 5. Authentication & Billing
- **Better Auth / Auth.js**: Standardized authentication flows. Do not hand-roll auth.
- **Stripe / Polar**: Billing, checkout, and subscriptions for SaaS products.

### 6. VS Code Extension & CLI
- **VS Code Extension**: Official VS Code contribution model + webview (shares same shadcn tokens if companion dashboard exists).
- **CLI**: Single unified command surface, JSON + human-readable output.

---

## When to Use Which UI Kit

| Product Category | UI Kit Selection | Key Characteristics |
| :--- | :--- | :--- |
| **A. Landing / Waitlist / Launch** | shadcn + Magic UI / Aceternity / 21st marketing blocks | Dark, sparse, high contrast. Nav, hero with single CTA, proof, 3-feature bento, pricing, FAQ, footer. No dashboard shell on marketing page. |
| **B. B2B SaaS Dashboard** (security, cost, compliance, admin) | shadcn-admin + ReUI / Kibo / 21st app blocks | Dense, quiet, structured sidebar application. Linear / Vercel / Stripe aesthetics. Trust > decoration. |
| **C. Conversational / WhatsApp / Voice Console** | assistant-ui or CopilotKit | Structured transcript, tool execution cards, citations, approval/rejection triggers. Mobile-first empty states. Bilingual-ready. |
| **D. VS Code Extension + CLI / Web** | VS Code Extension + Webview UI | Native IDE/CLI styling. Shares tokens with SaaS dashboard. Marketing site strictly uses Kit A only. |
| **E. India Ops Tools** (GST, clinic, school, RTO, forms) | shadcn forms + tables + stepper + printable/PDF | Large tap targets, obvious primary button, bilingual-ready strings (English + Kannada). |
