# Surprising Exchange Mobile Design System

## 0. Research Log

- Embedded references: combined the repository’s dark trading surface with the local institutional fintech and high-craft soft-surface references; no third-party branding or assets are copied.
- Existing-surface audit: retain Flutter’s `AppTextField`, product-line switcher, and theme architecture as migration seams.
- Product direction: a pocket flight deck. High-contrast ink surfaces, mineral light mode, cyan action state, amber attention state, and tabular financial numbers.

## 1. Personas and principles

- Mobile trader: checks markets and submits orders with one-hand reach and clear product-line context.
- Asset owner: verifies destination, network, amount, and confirmation state before money movement.
- New user: completes email auth and KYC in short, resumable steps.

Principles: one-handed first, explicit context, safe defaults, visible state, and no hidden financial assumptions.

## 2. Tokens

- Ink 950 `#080B10`, Ink 900 `#0D121A`, Ink 800 `#151C27`.
- Mineral 050 `#F7F9FB`, Mineral 100 `#EDF1F5`.
- Cyan 500 `#49D7E8`, Cyan 700 `#1599AD`, Amber 500 `#F0B95A`.
- Positive `#43D39E`, Negative `#F06E78`.
- Spacing: 4/8/12/16/20/24/32/40 logical pixels.
- Radius: 12 controls, 20 panels, 999 pills; minimum touch target 44 logical pixels.

## 3. Materials and elevation

Use nested panels with a one-pixel rim and restrained shadow. Blur is limited to fixed overlays. Theme changes semantic colors and surfaces together; risk colors remain stable.

## 4. Navigation and responsive behavior

Bottom navigation owns primary product areas. Product-line changes reset instrument, market, order, position, risk, and stream subscriptions before rendering new data. Forms use keyboard-aware scrolling and safe areas.

## 5. Reusable primitives and states

`AppSurface`, `AppTextField`, `AppActionButton`, `AppStatusBadge`, `ProductContext`, `VerificationCodeStep`, `AssetAmountField`, and `ApprovalSheet`; all have loading, disabled, error, success, and reduced-motion behavior.

## 6. Motion and interaction

Use short transform/opacity transitions for navigation and verification state. Haptics are reserved for submit success, destructive confirmation, and security changes. Respect platform reduced-motion settings.

## 7. Accessibility and content

Semantic labels include asset, account, product line, and status. Do not encode price movement by color alone. All dialogs are dismissible by system back, preserve focus, and state whether an action can be reversed.

## 8. Accepted debt and handoff

Existing trading widgets are being migrated incrementally; security, KYC, funding, transfer, and withdrawal flows must use these primitives before production sign-off. QA covers iOS and Android light/dark at compact and large phone sizes.
