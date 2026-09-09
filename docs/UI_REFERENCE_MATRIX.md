# UI Reference Matrix & License Audit

LittleNet V2 Frontend Architecture  
Branch: `feature/submission-rebuild-v2`  
Date: September 2026

---

## Legal & Architectural Policy
Before writing or adopting social UI components, we audited the licenses of all studied reference repositories.
Under copyright law, repositories lacking an open-source license grant **no legal reuse rights** (All Rights Reserved). For these repositories, **zero lines of code were copied or ported**; they served solely as conceptual design inspiration for layout hierarchy and user expectations.
Only repositories with an explicit permissive license (e.g. MIT) allow code adaptation. In all cases, LittleNet's implementation is purpose-built with bespoke child safety guards, local API integration, and clean Flutter architectural patterns.

---

## Reference Repository Analysis

| Repository | License | Relevant Screens / Components | Pattern Studied | DIRECT CODE REUSED? | ADAPTED? | VISUAL INSPIRATION ONLY? | LittleNet Equivalent |
|---|---|---|---|---|---|---|---|
| **`amrkhaledccd/my-moments`**<br>`https://github.com/amrkhaledccd/my-moments` | **None**<br>(All Rights Reserved) | Post card, profile header, story circle | Instagram story rings, flat post headers, bookmark action placement | **NO** (0% direct reuse) | **NO** | **YES** (studying visual spacing and icon hierarchy) | `LnStoryRing`, `LnPostCard`, `profile_screen.dart` |
| **`Doha26/Instagram-clone`**<br>`https://github.com/Doha26/Instagram-clone` | **None**<br>(All Rights Reserved) | Bottom navigation bar, feed list, explore grid | 5-tab bottom navigation with centered action, 3-column media grid | **NO** (0% direct reuse) | **NO** | **YES** (navigation tab ordering and explore tile aspect ratio) | `kids_main_shell.dart`, `explore_screen.dart` |
| **`TalonForemanRattle/instagram-mod-edge`**<br>`https://github.com/TalonForemanRattle/instagram-mod-edge` | **None**<br>(All Rights Reserved) | Clean media view, reel overlay | Vertical media presentation, author subtitle and action strip | **NO** (0% direct reuse) | **NO** | **YES** (minimalist scrim gradient and action icon positioning) | `reels_screen.dart` |
| **`itsezlife/flutter-instagram-offline-first-clone`**<br>`https://github.com/itsezlife/flutter-instagram-offline-first-clone` | **MIT License** | Post models, repository structure, feed architecture | Offline caching patterns, optimistic like state management, media item layouts | **NO** (0% direct code copied; LittleNet uses custom `ApiClient` and Neon/FastAPI backend) | **YES** (studied data caching and feed cursor patterns) | **YES** (clean white-surface social layout) | `feed_screen.dart`, `comments_sheet.dart` |

---

## Implementation Truth Summary
- **Direct Code Reused**: **0%**. All Flutter V2 widgets, screens, themes, and models are written directly for LittleNet.
- **Visual & Ergonomic Inspiration**: We drew upon standard social interaction paradigms (Instagram, TikTok) so the app feels immediately familiar and intuitive to children, while maintaining LittleNet's green-accented child safety layer and guardian controls.
- **Licensing Compliance**: 100% compliant. No unlicensed proprietary code exists in the repository.
