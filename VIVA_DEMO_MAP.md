# LittleNet — What to Show in Viva

Use this order so the demo follows the project report rather than jumping between features.

| Demo screen / action | Route / main file | What is happening behind it | AI / service to mention |
|---|---|---|---|
| Choose Kids or Parent Mode | auth templates / `auth/routes.py` | Role separation and session-based access | Flask session + role guards |
| Parent creates child | `/parent/create-child/` · `parent/routes.py` | Parent-first account flow, initial safety/screen-time controls | PostgreSQL transaction + text safety check |
| Kids Home | `/child/dashboard/` · `child/templates/child_dashboard.html` | Safe Feed/Stories/Clips plus Learn card | `services/social.py`, Parent Controls, quiz gate |
| Find friends | `/discover/` · `child/service.py` | Suggestions only from approved network, same school or same parent context | PostgreSQL relationship rules; no global stranger directory |
| Upload safe image/post | `/child/upload-post/` · `uploadPost/routes.py` | Caption + media safety checked before publication | NudeNet, Falconsai, CLIP, YOLO + `safety/policy.py` |
| Upload 18+ test image | same upload screen | Strong adult evidence immediately becomes BLOCK | Adult hard block >= 0.40; parent alert recorded |
| Upload weapon test | same upload screen | Weapon signal becomes BLOCK | YOLO + CLIP weapon signal; threshold >= 0.45 |
| Upload voice/audio | same upload / chat media | Speech converted to text, then toxic/adult language checked | Faster-Whisper + Detoxify/text safety |
| Upload video/Clip | `/reels/` + upload | Sampled video frames and extracted audio are both moderated | OpenCV + visual ensemble + FFmpeg + Whisper |
| Parent Review | `/parent/safety/` · `parent/templates/safety_review.html` | Medium-risk content waits for explicit parent decision | `moderation_events`, ALLOW/REVIEW/BLOCK, blurred preview |
| Approved-only chat | `/messages/`, `/chat/<id>/` | Only approved relationships can message; text/media/files are moderated | `services/social.can_interact`, text/visual/audio/document safety |
| Screen-time + Quiet hours | Parent dashboard / controls | Durable usage sessions, daily limit, server lock and scheduled quiet period | `services/usage.py`, `services/controls.py` |
| Parent dashboard | `/parent/dashboard/` | Online/offline, minutes, reviews, 7-day behavior, quiz activity | usage heartbeat, `behavior_summary`, PostgreSQL |
| Face Login | `/face-login/` | Face embedding verification plus anti-spoof/liveness | DeepFace; optional remote Modal AI |
| Live Safety | `/live-safety/` | Camera frames sampled and checked without retaining normal frames | visual moderation pipeline; fail closed |
| Admin moderation | `/admin/moderation/` | Admin sees signals/audit, can force-block REVIEW or remove post, never unblock hard blocks | moderation events + audit log |
| Learning | `/learning/` | Safe age-group quizzes/challenges and educational content | seeded PostgreSQL quiz/challenge data |
| Android app | `android/` | WebView loads the same HTTPS Flask application with controlled camera/mic/file access | same Flask backend + same AI safety APIs |

## One-sentence architecture answer
"LittleNet sends every child-generated image, video, audio or text through modality-specific pretrained safety models, combines their signals in a fail-closed decision engine, and only publishes content when the final state is ALLOW; uncertain content goes to Parent Review and adult/weapon evidence is always blocked."

## Five points worth emphasizing
1. **Safety is before visibility:** child-facing queries require `ALLOWED` and `is_safe`.
2. **No stranger social graph:** follows and DMs are parent-approved; Discover is network/school scoped.
3. **Multimodal:** image/video/audio/text are all covered; video includes both frames and audio.
4. **Parent control is server-side:** hiding a button is not the control—direct URLs are also denied.
5. **AI failure does not silently allow content:** partial failures go to REVIEW; total safety outage blocks.
