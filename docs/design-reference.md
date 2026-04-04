# Tertius — Design Reference (Adobe XD)
# Source: https://xd.adobe.com/view/fc7852b3-643b-419f-bea6-240c18650931-a92b/
# 8 Screens total, 375x812px (Mobile)

## Screen 01 — Splash
- Dark background (#1D2B3A area)
- LIANSBED logo (tree icon) centered
- Subtitle: "live and transcribed"
- Full screen, no navigation

## Screen 02 — Onboarding Transition
- Split view: Splash left, Feature card right
- Swipe/page transition

## Screen 03 — Onboarding Feature: Closed Caption
- LIANSBED logo top
- Large CC icon in rounded card (dark green/gray tint)
- Title: "closed caption" (bold, white)
- Description text below (muted gray)
- Pagination dots at bottom (4 dots, last one yellow = active)

## Screen 04 — Sign In
- Dark background with decorative blob
- Title: "SIGN IN" (bold, white, uppercase, centered top)
- Large gap between title and fields
- Fields: Label above (yellow-ish/white small text), value below, thin underline separator
  - Email: label "Email", placeholder "satiago@gmail.com"
  - Password: label "Password", value dots "******"
- "Forgot password?" link below password field (muted, left-aligned)
- Buttons at bottom:
  - "Sign In" — yellow pill button, dark text, full width
  - "Sign Up" — outlined/ghost button, white text, full width

## Screen 05 — Sign Up
- Same layout as Sign In
- Title: "SIGN IN" (note: XD shows "SIGN IN" but it's the registration screen)
- Fields: Name, Email, Password, Re-type Password
  - All with label above + value below + underline
- Same button layout: "Sign In" (yellow) + "Sign Up" (ghost)

## Screen 06 — Discover (Home / Main App Screen)
- **Header**: Dark background bar
  - Left: "Discover" (white, bold)
  - Right: Search icon (magnifying glass)
- **Hero Video**: Large area (~50% of screen), shows live stream
  - Loading spinner (blue circle) when buffering
  - Direct video feed (no controls visible initially)
- **Bottom Sheet / Card**: White rounded card sliding up from bottom
  - "Now Streaming" title (centered, medium weight)
  - Horizontal carousel of event thumbnail cards
    - Cards have images (church scenes, religious imagery)
    - Cards appear to be ~60% screen width, with peek of next/prev
- **Bottom Tab Bar**: White background, 4 tabs
  - Discover (chat/message bubble icon, yellow when active)
  - Upcoming (circle/clock icon)
  - Watchlist (clock/list icon)
  - Profile (person icon)
  - Active tab: yellow icon + text
  - Inactive tabs: gray icon + text

## Screen 07 — Discover (Scrolled / Browse)
- Same header: "Discover" + search icon
- **Featured Carousel**: Top area with tilted/stacked cards
  - Multiple event thumbnails overlapping
  - 3D card stack effect
- **Section: "Live in This Week"**
  - Section title left-aligned, bold
  - Grid: 3 columns
  - Each item:
    - Square thumbnail (speaker photo)
    - Title below: "Lorem Ipsum" (dark text)
    - Date below: "2 May 2019" (muted gray, small)
  - 2 rows visible (6 items)
- Same bottom tab bar

## Screen 08 — Event Detail
- **Video Hero**: Top ~35% of screen
  - Event thumbnail/video with play button (circle, white outline)
  - Back arrow (white, top-left)
  - Dark overlay on image
- **Content Card**: White, rounded top corners, slides over video
  - **Title**: "HE HAS Risen" (bold, large, dark)
  - **Tag**: "Eastern" pill badge (light gray bg, small text)
  - **Section "Description"**: Bold label, then body text (gray, regular weight)
  - **Section "Speaker / Translator"**:
    - 3 profile photos in a row (square, rounded corners)
    - Below each: Name (bold) + Role (muted)
    - Example: "Dr. Albertus van Eeden" / "Main Speaker"
    - Example: "Lorem Ipsum" / "Translation / Zulu"
    - Example: "Kai Wunderlich" / "Translation / German"
- **CTA Button**: "Watch now" — yellow pill, full width, bottom of screen

---

## Design System Notes
- **Colors**: Dark background (#1D2B3A), Yellow CTA (#F5C518-ish), White text, Muted gray text
- **Typography**: Bold uppercase for titles, regular for body
- **Buttons**: Yellow pill (primary), outlined pill (secondary/ghost)
- **Cards**: White with rounded corners, subtle shadows
- **Tab Bar**: White bg, 4 icons, yellow = active
- **Layout**: Mobile-first (375px), content-heavy, card-based UI
- **Video**: Large hero placement, prominent in UI
- **Navigation**: Bottom tab bar (Discover, Upcoming, Watchlist, Profile)
