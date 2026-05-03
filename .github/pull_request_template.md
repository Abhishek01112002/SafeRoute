## ✅ Pull Request Checklist

### What does this PR do?
<!-- One clear sentence describing the change -->


### Which module / feature does it relate to?
<!-- e.g. Tourist / Authority / Backend / Dashboard / Core -->
- [ ] Mobile — Tourist module
- [ ] Mobile — Authority Hub
- [ ] Mobile — Core / Shared
- [ ] Backend
- [ ] Dashboard
- [ ] Documentation / Config

### Type of change
- [ ] `feat` — New feature
- [ ] `fix` — Bug fix
- [ ] `refactor` — Code change that doesn't fix a bug or add a feature
- [ ] `test` — Adding or updating tests
- [ ] `docs` — Documentation only
- [ ] `chore` — Build, CI, or config

---

### How was this tested?
<!-- Describe what you tested and on what device/emulator -->


### Offline Mode Tested?
- [ ] Yes — tested in airplane mode
- [ ] No — this change doesn't affect offline behavior

---

### Pre-merge Checks
- [ ] `flutter analyze` passes with zero errors
- [ ] `flutter test` passes
- [ ] `pytest backend/tests/` passes (if backend changed)
- [ ] No hardcoded asset strings (use `AppAssets.*`)
- [ ] No hardcoded colors (use `AppColors.*`)
- [ ] No hardcoded pixel values (use `AppSpacing.*`)
- [ ] No hardcoded API URLs (use `EnvConfig.apiBaseUrl`)
- [ ] New DB columns have an Alembic migration
- [ ] No relative imports in Dart files (must use `package:saferoute/...`)

---

### Screenshots / Recordings (if UI change)
<!-- Paste screenshots or screen recording links here -->

---

### Anything reviewers should pay special attention to?
<!-- Optional: flag any tricky logic, risky areas, or open questions -->
