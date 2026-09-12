# 04 — Authentication & Authorization Audit Report

**Audited Date:** 2026-09-08  
**Audit Scope:** End-to-end authentication, authorization, OTP lifecycles, liveness verification, bearer tokens, BOLA/IDOR protections, and claim-versus-reality analysis.  

---

## 1. Authentication Lifecycle & State Machine

```
[Parent Registration]
        │
        ▼
[Account Status: PENDING_APPROVAL]
        │
        ├──> (Step 1) Email OTP Verification (Resend API)
        │       • 6-digit random code generated via `secrets.randbelow`
        │       • Salted SHA-256 hash stored in `parent_email_otps`
        │       • 10-minute expiry window (`OTP_TTL_MINUTES = 10`)
        │       • Max 5 failed attempts allowed (`OTP_MAX_ATTEMPTS = 5`)
        │       • Replay protection: OTP code deleted upon successful verification
        │
        └──> (Step 2) Live Adult Liveness Verification (`safety/face_service.py`)
                • Real camera frame captured
                • Anti-spoofing / texture / movement validation
                • AI age estimation (must verify adult >= 18)
                • Fail-closed fallback: Rejects child or ambiguous faces
                │
                ▼
      [Account Status: ACTIVE]
                │
                ▼
[Child Account Creation]
        • Requires active, verified Parent session/token
        • Parent supplies child's full name, username, DOB/age
        • Enforces foreign key `parent_id = current_parent.user_id`
        │
        ├──> Child Face Profile Enrollment (`enroll_face`)
        │       • Facial landmark embedding stored in `face_profiles`
        │       • Enables Face Login with anti-spoof liveness
        │
        └──> Mandatory Onboarding Safety Quiz
                • Compulsory safety guidelines quiz before feed access
```

---

## 2. Token Security & Session Management

- **Bearer Token Architecture**: Handled via [`mobile/api.py`](file:///d:/aitprojects/LittleNet-1/mobile/api.py). Tokens are generated with cryptographically secure random bytes (`secrets.token_hex(32)`).
- **Client-Side Secure Storage**: The Flutter client ([`mobile_flutter/lib/api.dart`](file:///d:/aitprojects/LittleNet-1/mobile_flutter/lib/api.dart)) persists the bearer token in `FlutterSecureStorage` with `encryptedSharedPreferences: true` on Android. No tokens are written to unencrypted shared preferences or local storage.
- **Session Revocation**: The `/api/mobile/logout/` endpoint revokes the bearer token in PostgreSQL, immediately invalidating subsequent requests.

---

## 3. Authorization & BOLA/IDOR Protections

| Protected Resource | Authorization Policy | Enforcement Location |
| :--- | :--- | :--- |
| **Parent Dashboard** | Only users with `role = 'parent'` and `is_verified = TRUE`. | `parent/routes.py`, `mobile/api.py` |
| **Child Controls** | Parent can only view/modify children where `child.parent_id == parent.user_id`. | `parent/service.py` |
| **Direct Messaging** | Children can only message other children who are mutually approved by both parents. | `chat/service.py`, `mobile/api.py` |
| **Post Deletion** | Only the author child or their verified parent can delete a post. | `uploadPost/routes.py` |
| **Moderator Queue** | Only users with `role = 'admin'` or `role = 'moderator'` can access. | `admin/routes.py`, `mobile/admin_api.py` |

---

## 4. Claim vs. Reality: SMS & Certificate Authentication

### 4.1 SMS Authentication Status
- **Reality**: **SMS NOT IMPLEMENTED**.
- **Evidence**: An audit of all source files in `auth/`, `mobile/`, and `services/` found 0 references to SMS gateways (e.g. Twilio, AWS SNS, MSG91).
- **Reporting Requirement**: Email OTP via Resend is the only implemented second-factor mechanism. In accordance with audit rules, email OTP is explicitly documented as email, not SMS.

### 4.2 Certificate Authentication Status
- **Reality**: **NO CLIENT CERTIFICATE (mTLS) IMPLEMENTATION**.
- **Evidence**: The system does not issue, manage, or require client X.509 certificates.
- **Technical Reality**: What is often colloquially called "certificate authentication" in project requirements actually refers to **TLS Certificate Verification**:
  - The Android app enforces `android:usesCleartextTraffic="false"` in `AndroidManifest.xml`.
  - All communication is strictly encrypted over HTTPS with standard CA TLS certificate verification.
