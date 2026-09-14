# Known Limitations

- Android device/emulator journeys require a reachable non-production backend and prepared accounts. They remain UNVERIFIED unless the final evidence matrix names the device and run.
- A distributable APK requires an authorized EAS account/token or a separately configured local native build. An Expo export is not an APK.
- This workstation had neither `adb`/an Android emulator nor an authorized EAS token, so Android critical E2E and APK install/launch remain explicitly UNVERIFIED.
- Story viewing is implemented, but dedicated story-seen persistence is not claimed unless verified against the live route and database.
- Media chat is not implemented because no separate native media-message contract was added to the fail-closed moderation pipeline. Text and shared-post chat remain supported.
- Video moderation samples bounded scenes rather than every frame. Video audio is stripped; standalone voice/audio posting is outside the locked demo scope.
- Parent/Admin collection routes are intentionally bounded to 100 recent rows. They do not provide enterprise-scale reporting or arbitrary historical export.
- The activity screen shows event categories and timestamps without exposing private message bodies or unrelated-user content.
- Modal/R2/Neon production deployment, billing state, and zero-idle-container evidence are external operations and are not inferred from source tests.
- An isolated R2 object round-trip was verified for the submission-readiness prefix. Full quarantine/promotion/privacy lifecycle evidence remains unverified, and the Modal CLI was unavailable in this workstation for app-state inspection.
- Real Resend inbox delivery remains unverified because no approved recipient inbox was available in this session; the sender contract and fail-closed behavior are covered by CI/tests.
- The previously exposed disposable Neon credential/branch still requires deletion or rotation by an authenticated Neon account owner; this workstation has no authenticated Neon CLI profile, so cleanup is not claimed.
- `npm audit` reports 16 moderate and no high/critical findings. The incompatible transitive upgrade chains are documented in [DEPENDENCY_AUDIT.md](DEPENDENCY_AUDIT.md); no breaking `--force` downgrade was applied.
