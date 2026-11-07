/**
 * Shared class recipes for the IntelliMed design language ("clinical ledger").
 *
 * Every page composes these instead of re-deriving button/input/card styling,
 * so the whole app shares one set of surfaces, rules and focus treatments.
 * Colors come from the semantic tokens in src/index.css (they flip in dark
 * mode automatically — never add `dark:` color variants alongside them).
 */

const focusRing =
  'focus:outline-none focus-visible:ring-2 focus-visible:ring-primary/30 focus:border-primary';

export const ui = {
  // Layout ------------------------------------------------------------
  page: `flex-1 w-full max-w-[1240px] mx-auto px-5 md:px-10 py-8 md:py-12 flex flex-col
         gap-8 md:gap-10 animate-[riseIn_0.25s_ease-out]`,
  pageHeader: 'flex flex-wrap items-end justify-between gap-4 pb-6 border-b border-line',
  pageTitle: 'text-ink font-serif text-[28px] md:text-[34px] font-semibold tracking-[-0.01em] leading-[1.15]',
  pageSubtitle: 'text-muted text-[15px] leading-relaxed max-w-[62ch] mt-2',
  sectionTitle: 'ledger-label text-muted',

  // Surfaces ----------------------------------------------------------
  card: 'bg-surface border border-line rounded-xl',
  cardPad: 'p-5 md:p-7',
  cardHeader: 'flex items-center justify-between gap-4 px-5 md:px-7 py-4 border-b border-line',

  // Buttons -----------------------------------------------------------
  btn: `inline-flex items-center justify-center gap-2 rounded font-semibold text-[13px]
        leading-none transition-colors select-none cursor-pointer disabled:opacity-50
        disabled:cursor-not-allowed disabled:pointer-events-none`,
  btnPrimary: 'bg-primary hover:bg-primary-strong text-white border border-primary-strong px-4 py-2.5',
  btnSecondary: 'bg-surface hover:bg-surface-2 text-ink border border-line px-4 py-2.5',
  btnGhost: 'text-muted hover:text-ink hover:bg-surface-2 px-3 py-2',
  btnDanger: 'bg-danger hover:bg-danger/90 text-white border border-danger px-4 py-2.5',
  btnSoftPrimary: 'bg-primary/10 hover:bg-primary/15 text-primary border border-primary/15 px-4 py-2.5',
  btnSoftDanger: 'bg-danger/10 hover:bg-danger/15 text-danger border border-danger/15 px-3 py-2',
  btnSm: 'px-2.5 py-1.5 text-xs',

  // Forms -------------------------------------------------------------
  label: 'block ledger-label text-muted mb-2',
  input: `w-full rounded border border-line bg-surface text-ink text-sm px-3.5 py-2.5
          placeholder:text-subtle transition-colors ${focusRing}`,
  inputIcon: `w-full rounded border border-line bg-surface text-ink text-sm pl-10 pr-3.5 py-2.5
              placeholder:text-subtle transition-colors ${focusRing}`,
  formError: 'text-sm text-danger bg-danger/10 border border-danger/25 rounded px-3.5 py-2.5',
  formSuccess: 'text-sm text-success bg-success/10 border border-success/25 rounded px-3.5 py-2.5',

  // Tables ------------------------------------------------------------
  table: 'w-full text-left border-collapse',
  th: 'px-5 md:px-6 py-3 ledger-label text-muted border-b border-line whitespace-nowrap',
  td: 'px-5 md:px-6 py-4 text-sm text-body',
  tr: 'border-b border-line hover:bg-surface-2/50 transition-colors',

  // Badges & status ---------------------------------------------------
  badge: `inline-flex items-center gap-1.5 px-2 py-1 rounded-sm text-[10px] font-semibold
          uppercase tracking-[0.08em] border`,
  badgeSuccess: 'bg-success/10 text-success border-success/25',
  badgeWarning: 'bg-warning/10 text-warning border-warning/25',
  badgeDanger: 'bg-danger/10 text-danger border-danger/25',
  badgeInfo: 'bg-info/10 text-info border-info/25',
  badgeNeutral: 'bg-surface-2 text-muted border-line',

  // Feedback ----------------------------------------------------------
  emptyState: 'flex flex-col items-center justify-center gap-3 py-14 px-6 text-center',
  emptyIcon: 'size-12 rounded border border-line bg-surface-2 flex items-center justify-center text-subtle',
};

export default ui;
