/**
 * Shared class recipes for the IntelliMed design language.
 *
 * Every page composes these instead of re-deriving button/input/card styling,
 * so the whole app shares one set of surfaces, radii and focus treatments.
 * Colors come from the semantic tokens in src/index.css (they flip in dark
 * mode automatically — never add `dark:` color variants alongside them).
 */

const focusRing =
  'focus:outline-none focus:ring-2 focus:ring-primary/25 focus:border-primary';

export const ui = {
  // Layout ------------------------------------------------------------
  page: 'flex-1 w-full max-w-[1240px] mx-auto px-4 md:px-8 py-6 md:py-10 flex flex-col gap-6 md:gap-8',
  pageHeader: 'flex flex-wrap items-end justify-between gap-4',
  pageTitle: 'text-ink text-[26px] md:text-[32px] font-extrabold tracking-tight leading-tight',
  pageSubtitle: 'text-muted text-[15px] leading-relaxed',
  sectionTitle: 'text-ink text-lg font-bold tracking-tight',

  // Surfaces ----------------------------------------------------------
  card: 'bg-surface border border-line rounded-2xl shadow-card',
  cardPad: 'p-5 md:p-6',
  cardHeader: 'flex items-center justify-between gap-4 px-5 md:px-6 py-4 border-b border-line',

  // Buttons -----------------------------------------------------------
  btn: `inline-flex items-center justify-center gap-2 rounded-lg font-bold text-sm
        transition-colors select-none cursor-pointer disabled:opacity-50
        disabled:cursor-not-allowed disabled:pointer-events-none`,
  btnPrimary: 'bg-primary hover:bg-primary-strong text-white px-4 py-2.5 shadow-sm',
  btnSecondary: 'bg-surface hover:bg-surface-2 text-ink border border-line px-4 py-2.5',
  btnGhost: 'text-muted hover:text-ink hover:bg-surface-2 px-3 py-2',
  btnDanger: 'bg-danger hover:bg-danger/90 text-white px-4 py-2.5',
  btnSoftPrimary: 'bg-primary/10 hover:bg-primary/15 text-primary px-4 py-2.5',
  btnSoftDanger: 'bg-danger/10 hover:bg-danger/15 text-danger px-3 py-2',
  btnSm: 'px-3 py-1.5 text-xs',

  // Forms -------------------------------------------------------------
  label: 'block text-sm font-semibold text-ink mb-1.5',
  input: `w-full rounded-lg border border-line bg-surface text-ink text-sm px-3.5 py-2.5
          placeholder:text-subtle transition-colors ${focusRing}`,
  inputIcon: 'w-full rounded-lg border border-line bg-surface text-ink text-sm pl-10 pr-3.5 py-2.5 placeholder:text-subtle transition-colors ' + focusRing,
  formError: 'text-sm text-danger bg-danger/10 border border-danger/20 rounded-lg px-3.5 py-2.5',
  formSuccess: 'text-sm text-success bg-success/10 border border-success/20 rounded-lg px-3.5 py-2.5',

  // Tables ------------------------------------------------------------
  table: 'w-full text-left border-collapse',
  th: 'px-5 md:px-6 py-3.5 text-xs font-bold text-muted uppercase tracking-wider',
  td: 'px-5 md:px-6 py-4 text-sm text-body',
  tr: 'border-t border-line hover:bg-surface-2/60 transition-colors',

  // Badges & status ---------------------------------------------------
  badge: 'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold border',
  badgeSuccess: 'bg-success/10 text-success border-success/20',
  badgeWarning: 'bg-warning/10 text-warning border-warning/20',
  badgeDanger: 'bg-danger/10 text-danger border-danger/20',
  badgeInfo: 'bg-info/10 text-info border-info/20',
  badgeNeutral: 'bg-surface-2 text-muted border-line',

  // Feedback ----------------------------------------------------------
  emptyState: 'flex flex-col items-center justify-center gap-3 py-14 px-6 text-center',
  emptyIcon: 'size-14 rounded-2xl bg-surface-2 flex items-center justify-center text-subtle',
};

export default ui;
