# Known Limitations

- Android device/emulator journeys require a reachable non-production backend and prepared accounts. They remain UNVERIFIED unless the final evidence matrix names the device and run.
- A distributable APK requires an authorized EAS account/token or a separately configured local native build. An Expo export is not an APK.
- This workstation had neither `adb`/an Android emulator nor an authorized EAS token, so Android critical E2E and APK install/launch remain explicitly UNVERIFIED.
- Story viewing is implemented, but dedicated story-seen persistence is not claimed unless verified against the live route and database.
- Media chat is not implemented because no separate native media-message contract was added to the fail-closed moderation pipeline. Text and shared-post chat remain supported.
- Video moderation samples bounded scenes rather than every frame. Video audio is stripped; standalone voice/audio posting is outside the locked demo scope.
- Parent/Admin collection routes are intentionally bounded to 100 recent rows. They do not provide enterprise-scale reporting or arbitrary historical export.
- The activity screen shows event categories and timestamps without exposing private message bodies or unrelated-user content.
- Modal workspace/app/volume access and zero active containers were verified for `netlittle2`; the bounded AI probe still returned HTTP 401, so AI service authentication/readiness is not claimed.
- The full synthetic R2 lifecycle passed: signed quarantine upload, private REVIEW delivery, ALLOW sanitization/promotion/readback, BLOCK cleanup, and cleanup of all synthetic objects. This does not validate real-user media.
- The approved `E2E_TEST_EMAIL` secret is now present, but a live registration against Modal returned `email_sent=false`; no OTP verification or real inbox evidence can be claimed. The sender contract and fail-closed behavior remain covered by CI/tests.
- EAS authentication, linking to the existing project, and preview APK build `914dc2c5-740b-4f2e-aa2d-40e0ba0566e8` passed. The APK artifact is available at https://expo.dev/artifacts/eas/Pak-g5Mj08VCdNHHiew-ZHgnSMDEHDzV2vNaqJ5w_FU.apk; physical installation and device journeys remain unverified.
- The moderation benchmark result is a six-row synthetic calibration sample, not a production accuracy claim: exact-action agreement and macro-F1 were both 0.666667.
- The previously exposed disposable Neon credential/branch still requires deletion or rotation by an authenticated Neon account owner; this workstation has no authenticated Neon CLI profile, so cleanup is not claimed.
- `npm audit` reports 16 moderate and no high/critical findings. The incompatible transitive upgrade chains are documented in [DEPENDENCY_AUDIT.md](DEPENDENCY_AUDIT.md); no breaking `--force` downgrade was applied.
