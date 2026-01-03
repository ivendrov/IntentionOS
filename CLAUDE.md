# Intention OS - Design Document

**Version:** 0.1 (Draft)  
**Last Updated:** January 2025

---

## 1. Overview

### 1.1 Concept

Intention OS is a macOS application that inverts the typical productivity tool paradigm. Rather than monitoring behavior and reporting (shame-based), it requires users to declare an intention upfront and creates friction around deviation.

The core loop:
1. User opens laptop → full-screen intention prompt appears
2. User types their intention and sets a duration (default 25 min)
3. Apps and browser tabs are filtered against the intention using an LLM
4. Deviating requires typing "I am choosing distraction"
5. Timer expires → full-screen prompt returns, cannot be dismissed without setting new intention or typing the phrase

### 1.2 Design Principles

- **Friction over blocking:** We make distraction inconvenient, not impossible
- **Intention-first:** Every session starts with explicit intention-setting
- **Learning system:** The app learns which apps/URLs belong to which intentions
- **Configurable:** Core behaviors controlled via human-readable config files
- **Beautiful constraint:** The UI should feel powerful and slightly otherworldly, not corporate

---

## 2. Architecture

### 2.1 Components

```
┌─────────────────────────────────────────────────────────────┐
│  Intention OS (Swift App)                                   │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   SwiftUI   │  │ Accessibility│  │   Local HTTP        │ │
│  │   Views     │  │   Monitor    │  │   Server (:9999)    │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                     │            │
│         ▼                ▼                     ▼            │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Core Engine                          ││
│  │  • Intention state machine                              ││
│  │  • Timer management                                     ││
│  │  • LLM filtering (OpenAI/Anthropic)                     ││
│  │  • Rule matching & learning                             ││
│  └─────────────────────────────────────────────────────────┘│
│                          │                                  │
│         ┌────────────────┼────────────────┐                │
│         ▼                ▼                ▼                │
│  ┌───────────┐    ┌───────────┐    ┌───────────┐          │
│  │  config/  │    │  SQLite   │    │  Learned  │          │
│  │  *.yaml   │    │    DB     │    │   Rules   │          │
│  └───────────┘    └───────────┘    └───────────┘          │
└─────────────────────────────────────────────────────────────┘
                           ▲
                           │ HTTP (localhost:9999)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Chrome Extension                                           │
│  • Monitors tab URLs                                        │
│  • Queries Swift app for allow/block                        │
│  • Redirects blocked URLs to interstitial page              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Choices

| Component | Technology | Rationale |
|-----------|------------|-----------|
| Main App | Swift + SwiftUI | Native macOS integration, window management, Accessibility API |
| Config | YAML files | Human-readable, easy to modify |
| Storage | SQLite | Simple, no external dependencies |
| LLM | OpenAI gpt-4o-mini | Cheapest, fastest, ~$0.10/month at heavy usage |
| Browser Integration | Chrome Extension (Manifest V3) | Required for tab-level access |
| IPC | Local HTTP server | Simple, debuggable, extension-compatible |

---

## 3. User Experience

### 3.1 Startup / Wake Flow

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│              [Procedural generative visual]                 │
│                                                             │
│                   What is your intention?                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Journal                                             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│            Duration: [25 min ▼]  [Unlimited]                │
│                                                             │
│  ┌─ Apps & Sites ─────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  Bundles: [+ Writing] [Deep Work] [+ New...]          │ │
│  │                                                        │ │
│  │  Apps:    [+ Obsidian] [×]                            │ │
│  │           [Add app...]                                 │ │
│  │                                                        │ │
│  │  URLs:    [nothinghuman.substack.com/publish/*] [×]   │ │
│  │           [Add URL pattern...]                         │ │
│  │                                                        │ │
│  │  ☑ Also allow LLM-approved apps/sites                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│                      [Begin]                                │
│                                                             │
│  ─────────────────────────────────────────────────────────  │
│  To skip, type: "I am choosing distraction"                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Apps & Sites Panel:**
- Collapsed by default (click to expand)
- **Bundles:** Saved packages of apps + URL patterns. Click to toggle on/off. [+ New...] opens bundle creator.
- **Apps:** Searchable list of installed apps. Shows bundle ID on hover.
- **URLs:** Glob patterns (e.g., `github.com/myorg/*`, `*.google.com/docs/*`)
- **LLM toggle:** When ON (default), LLM can approve additional apps/sites. When OFF, ONLY the explicit list is allowed (strict mode).

**Bundle Management (via gear icon or "Manage Bundles"):**

```
┌─────────────────────────────────────────────────────────────┐
│  Manage Bundles                                     [Done]  │
│─────────────────────────────────────────────────────────────│
│                                                             │
│  Writing                                            [Edit]  │
│  └─ Obsidian, iA Writer │ substack.com/*, medium.com/*     │
│                                                             │
│  Deep Work                                          [Edit]  │
│  └─ VSCode, Terminal │ github.com/*, stackoverflow.com/*   │
│                                                             │
│  Research                                           [Edit]  │
│  └─ Chrome, Notion │ scholar.google.com/*, *.edu/*         │
│                                                             │
│  [+ Create New Bundle]                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Behaviors:**
- Appears on login and wake from sleep
- Appears on login and wake from sleep
- Window level: above all other windows (screenSaver level)
- On focus loss: re-asserts focus after 100ms
- Cannot be dismissed except by:
  - Setting an intention
  - Typing "I am choosing distraction" exactly
  - Force Quit (Cmd+Opt+Esc) — deliberate enough to count

### 3.2 Active Session

During an active intention:
- Menu bar shows: intention text (truncated) + time remaining
- Apps/URLs are filtered against intention
- 5-minute warning: macOS notification ("5 minutes remaining on: [intention]")

### 3.3 App/URL Filtering

When user focuses an app or opens a browser tab:

```
┌──────────────────┐
│ New app/URL      │
│ detected         │
└────────┬─────────┘
         ▼
┌──────────────────┐     ┌──────────────────┐
│ Check explicit   │────▶│ In intention's   │───▶ Allow
│ intention list   │ yes │ app/URL list or  │     (reason: 'explicit'
└────────┬─────────┘     │ active bundle    │      or 'bundle')
         │ no match      └──────────────────┘
         ▼
┌──────────────────┐
│ LLM filtering    │──────▶ Block (strict mode)
│ enabled?         │ no
└────────┬─────────┘
         │ yes
         ▼
┌──────────────────┐     ┌──────────────────┐
│ Check static     │────▶│ Explicitly       │───▶ Allow
│ rules (config)   │ yes │ allowed          │     (reason: 'config')
└────────┬─────────┘     └──────────────────┘
         │ no match
         ▼
┌──────────────────┐     ┌──────────────────┐
│ Check learned    │────▶│ Previously       │───▶ Allow
│ associations     │ yes │ approved for     │     (reason: 'learned')
└────────┬─────────┘     │ similar intent   │
         │ no match      └──────────────────┘
         ▼
┌──────────────────┐     ┌──────────────────┐
│ LLM check        │────▶│ Aligned with     │───▶ Allow
│ (intent + app)   │ yes │ intention        │     (reason: 'llm')
└────────┬─────────┘     └──────────────────┘
         │ no
         ▼
┌──────────────────┐
│ Show break-glass │
│ interstitial     │
└──────────────────┘
```

**Strict Mode:** When "Also allow LLM-approved apps/sites" is unchecked, ONLY the explicit list (apps/URLs/bundles selected for this intention) is allowed. No config rules, no learned rules, no LLM. This is for maximum focus sessions.

### 3.4 Break-Glass Interstitial (Apps)

When a non-aligned app is focused:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  "Slack" doesn't seem aligned with your intention:          │
│  "Write design doc for Intention OS"                        │
│                                                             │
│  To continue anyway, type:                                  │
│  "I am choosing distraction"                                │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  □ Remember: Slack is okay for "writing" intentions         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.5 Break-Glass Interstitial (Browser)

Chrome extension redirects to local page:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  This URL doesn't seem aligned with your intention:         │
│                                                             │
│  URL: twitter.com/home                                      │
│  Intention: "Write design doc for Intention OS"             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ I am choosing distraction                           │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  [Continue to site]                                         │
│                                                             │
│  □ Remember: twitter.com is okay for "writing" intentions   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.6 Timer Expiration

When timer ends → same full-screen UI as startup, showing:
- What the intention was
- Time elapsed
- Prompt for new intention

### 3.7 Unlimited Mode Check-in (Every 30 min)

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│              Still working on your intention?               │
│                                                             │
│              "Deep work on Intention OS"                    │
│                                                             │
│              Time elapsed: 1h 30m                           │
│                                                             │
│       [Continue]              [Set New Intention]           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Softer than the main takeover — no "I am choosing distraction" required, just a conscious acknowledgment. Clicking "Continue" extends for another 30 minutes.

### 3.8 Multi-Monitor Behavior

The full-screen intention UI appears on **all connected displays simultaneously**. This prevents the "escape to second monitor" loophole. Each display shows identical content; text input is mirrored.

### 3.9 History View (Chrome Extension - Phase 3)

Accessed via the extension popup → "View History":

```
┌─────────────────────────────────────────────────────────────┐
│  Intention History                            [Export CSV]  │
│─────────────────────────────────────────────────────────────│
│                                                             │
│  Today, Jan 6                                               │
│  ├─ 9:15 AM - 10:42 AM (1h 27m)                            │
│  │  "Write design doc for Intention OS"                     │
│  │  Apps: VSCode, Chrome │ Overrides: 1 (Slack)            │
│  │                                                          │
│  └─ 8:30 AM - 9:12 AM (42m)                                │
│     "Morning email triage"                                  │
│     Apps: Chrome, Mail │ Overrides: 0                       │
│                                                             │
│  Yesterday, Jan 5                                           │
│  └─ ...                                                     │
│                                                             │
│  [Load more]                                                │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Data Model

### 4.1 SQLite Schema

```sql
-- Current and historical intentions (wall-clock timestamps for history view)
CREATE TABLE intentions (
    id INTEGER PRIMARY KEY,
    text TEXT NOT NULL,
    duration_seconds INTEGER, -- NULL = unlimited (30-min check-ins)
    started_at TIMESTAMP NOT NULL, -- wall clock time
    ended_at TIMESTAMP, -- wall clock time
    end_reason TEXT, -- 'completed', 'new_intention', 'chose_distraction', 'checkin_continue'
    llm_filtering_enabled BOOLEAN DEFAULT TRUE -- FALSE = strict mode, only explicit list
);

-- Bundles: saved packages of apps + URLs
CREATE TABLE bundles (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE TABLE bundle_apps (
    id INTEGER PRIMARY KEY,
    bundle_id INTEGER REFERENCES bundles(id) ON DELETE CASCADE,
    app_bundle_id TEXT NOT NULL, -- e.g., "md.obsidian"
    app_name TEXT NOT NULL -- human-readable, e.g., "Obsidian"
);

CREATE TABLE bundle_urls (
    id INTEGER PRIMARY KEY,
    bundle_id INTEGER REFERENCES bundles(id) ON DELETE CASCADE,
    url_pattern TEXT NOT NULL -- glob pattern, e.g., "github.com/myorg/*"
);

-- Explicit apps/URLs for a specific intention (ad-hoc, not from bundle)
CREATE TABLE intention_apps (
    id INTEGER PRIMARY KEY,
    intention_id INTEGER REFERENCES intentions(id) ON DELETE CASCADE,
    app_bundle_id TEXT NOT NULL,
    app_name TEXT NOT NULL,
    from_bundle_id INTEGER REFERENCES bundles(id) -- NULL if added ad-hoc
);

CREATE TABLE intention_urls (
    id INTEGER PRIMARY KEY,
    intention_id INTEGER REFERENCES intentions(id) ON DELETE CASCADE,
    url_pattern TEXT NOT NULL,
    from_bundle_id INTEGER REFERENCES bundles(id) -- NULL if added ad-hoc
);

-- Apps/URLs accessed during intentions
CREATE TABLE access_log (
    id INTEGER PRIMARY KEY,
    intention_id INTEGER REFERENCES intentions(id),
    timestamp TIMESTAMP NOT NULL,
    type TEXT NOT NULL, -- 'app' or 'url'
    identifier TEXT NOT NULL, -- bundle ID or URL
    was_allowed BOOLEAN NOT NULL,
    allowed_reason TEXT, -- 'explicit', 'bundle', 'learned', 'llm', 'override'
    was_override BOOLEAN NOT NULL, -- did they type the phrase?
    added_to_learned BOOLEAN DEFAULT FALSE
);

-- Learned associations (user-confirmed)
CREATE TABLE learned_rules (
    id INTEGER PRIMARY KEY,
    intention_pattern TEXT NOT NULL, -- semantic pattern
    type TEXT NOT NULL, -- 'app' or 'url'
    identifier TEXT NOT NULL, -- bundle ID or URL pattern
    allowed BOOLEAN NOT NULL,
    created_at TIMESTAMP NOT NULL
);
```

### 4.2 Config Files

Located in `~/.intention-os/` (or `~/Library/Application Support/IntentionOS/`)

**config.yaml** - Core settings:
```yaml
# Timing
default_duration_minutes: 25
warning_before_end_minutes: 5
unlimited_checkin_minutes: 30  # check-in interval for unlimited mode

# Enforcement
break_glass_phrase: "I am choosing distraction"
reassert_focus_delay_ms: 100

# LLM
llm_provider: openai  # or 'anthropic'
llm_model: gpt-4o-mini
llm_api_key_env: OPENAI_API_KEY  # read from environment

# Visual
theme: dark
background_animation: orb  # orb, faces, cityscape, none
```

**rules.yaml** - Static allow/block rules:
```yaml
# These override LLM decisions
always_allowed:
  apps:
    - com.apple.finder
    - com.apple.Safari  # browser itself allowed; tabs filtered separately
    - com.google.Chrome
  urls:
    - "*.google.com/search*"  # search is always okay
    
always_blocked:
  apps: []
  urls:
    - "*.reddit.com/*"
    - "twitter.com/*"
    - "*.tiktok.com/*"

# Intention-specific overrides (used by LLM context)
intention_rules:
  - pattern: "code|programming|develop|debug|software"
    allow_apps:
      - com.microsoft.VSCode
      - com.apple.dt.Xcode
      - com.googlecode.iterm2
    allow_urls:
      - "github.com/*"
      - "stackoverflow.com/*"
      - "developer.apple.com/*"
```

**bundles.yaml** - Saved app/URL bundles (can also be edited in UI):
```yaml
# Bundles are saved here for easy backup/sharing
# You can edit this file directly or use the app UI

bundles:
  - name: Writing
    apps:
      - id: md.obsidian
        name: Obsidian
      - id: com.iawriter.mac
        name: iA Writer
    urls:
      - "nothinghuman.substack.com/publish/*"
      - "medium.com/p/*"
      - "docs.google.com/document/*"

  - name: Deep Work
    apps:
      - id: com.microsoft.VSCode
        name: VS Code
      - id: com.apple.Terminal
        name: Terminal
      - id: com.googlecode.iterm2
        name: iTerm
    urls:
      - "github.com/*"
      - "stackoverflow.com/*"
      - "*.anthropic.com/*"

  - name: Research
    apps:
      - id: com.google.Chrome
        name: Chrome
      - id: notion.id
        name: Notion
    urls:
      - "scholar.google.com/*"
      - "*.edu/*"
      - "arxiv.org/*"
      - "*.wikipedia.org/*"

  - name: Journal
    apps:
      - id: md.obsidian
        name: Obsidian
    urls: []
```

Bundles are stored in both SQLite (for fast access) and synced to `bundles.yaml` (for easy editing and sharing). Editing either location updates the other on next app launch.

---

## 5. LLM Integration

### 5.1 Prompt Template

```
You are a focus assistant. Determine if the given app/URL is aligned with the user's stated intention.

Intention: "{intention}"

{type}: "{identifier}"
{additional_context}

Respond with only "yes" or "no", followed by a brief reason (max 10 words).

Examples:
- Intention: "Write blog post about cooking" + URL: "youtube.com/watch?v=..." → "no - video streaming is likely distraction"
- Intention: "Research vacation destinations" + URL: "tripadvisor.com" → "yes - travel research site"
- Intention: "Fix login bug" + App: "Slack" → "no - messaging not needed for debugging"
```

### 5.2 Caching Strategy

- Cache LLM responses for (intention_hash, identifier) pairs
- TTL: 24 hours or until intention changes
- Learned rules always override cache

---

## 6. Implementation Phases

### Phase 1: MVP (1-2 weeks)
- [ ] Full-screen intention prompt on wake/login (all monitors)
- [ ] Timer with menu bar display
- [ ] Basic app filtering via Accessibility API
- [ ] **Explicit app/URL picker in intention UI**
- [ ] **Bundle management (create, edit, delete, select)**
- [ ] Static rules from config file
- [ ] Break-glass with phrase typing
- [ ] Config file loading
- [ ] Strict mode toggle (LLM filtering on/off)

### Phase 2: Intelligence (1 week)
- [ ] LLM integration for app/URL checking (when not in strict mode)
- [ ] Chrome extension with redirect page
- [ ] Learning system ("remember this for similar intentions")

### Phase 3: Polish (1 week)  
- [ ] Procedural background animation
- [ ] 5-minute warning notification
- [ ] Chrome extension: "View History" page
  - List of past intentions with wall-clock start/end times
  - Filter by date range
  - See which apps/URLs were used per intention
  - See which bundles were used
- [ ] Refined UI/UX

### Phase 4: Distribution
- [ ] Code signing for Accessibility permissions
- [ ] DMG installer with Chrome extension
- [ ] First-run onboarding flow
- [ ] Bundle import/export (share bundles with friends)

---

## 7. Design Decisions

1. **Multiple monitors:** Intention screen appears on ALL displays simultaneously, preventing "escape to second monitor."

2. **Unlimited mode:** Check-in prompt appears every 30 minutes. Same full-screen UI but with softer framing ("Still working on [intention]? [Continue] / [Set new intention]").

3. **Emergency bypass:** Force Quit (Cmd+Opt+Esc) is sufficient. No additional bypass mechanism.

4. **Intention suggestions:** None. The intention field is always blank — forces conscious articulation each time.

5. **Intention history:** All intentions are logged with wall-clock start/end times. Viewable via Chrome extension (Phase 3+).

## 8. Open Questions

1. **Mobile companion:** Future iOS app that syncs intentions?

2. **Export format:** Should history be exportable (CSV, JSON) for personal analytics?

3. **Streaks/stats:** Show "you've set intentions for 7 days straight" type encouragement, or keep it minimal?

---

## Appendix A: macOS Permissions Required

| Permission | Purpose | User Prompt |
|------------|---------|-------------|
| Accessibility | Monitor focused apps, window management | "IntentionOS wants to control this computer using accessibility features" |
| Automation (optional) | Control other apps if needed | Per-app prompts |
| Notifications | 5-minute warning | Standard notification permission |

---

## Appendix B: Chrome Extension Manifest

```json
{
  "manifest_version": 3,
  "name": "Intention OS",
  "version": "1.0",
  "permissions": ["tabs", "activeTab", "storage"],
  "host_permissions": ["<all_urls>"],
  "background": {
    "service_worker": "background.js"
  },
  "content_scripts": [{
    "matches": ["<all_urls>"],
    "js": ["content.js"]
  }]
}
```
