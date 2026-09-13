// Shared copy / wording rules for the on-device app.
//
// Non-diagnostic framing is enforced here in one place so every screen uses
// the same vocabulary: "flag", "pattern", "context", "for review" only.
// Never introduce "diagnos*" wording in UI copy, variable names, or comments.

/// Human-readable status line for a stored result record.
String reviewStatusLine(String syncStatus) {
  switch (syncStatus) {
    case 'synced':
      return 'Structured context synced — ready for doctor review';
    case 'failed':
      return 'Sync failed — will retry when connectivity resumes';
    default:
      return 'Structured context saved — pending sync for doctor review';
  }
}

/// Short caption shown under pattern/flag lists.
const patternListCaption =
    'Patterns below are structured context for doctor review only.';

/// Caption under the trends list. Deliberately descriptive: the app never
/// labels a change as improvement or decline.
const trendsCaption =
    'Your values over time, from this device and your account. '
    'For review with your doctor.';

/// Banner on one analyte's history.
const trendReadingCaption =
    'These are the values printed on your reports, shown in date order. '
    'For review with your doctor.';

/// Shown when an analyte appears under more than one unit.
const trendUnitSplitNote =
    'This measurement appears under different units. Each unit is shown '
    'separately and never compared across units.';

/// Caption for the on-device AI insights section.
const insightsCaption =
    'Generated on this device to help you understand your results. '
    'Not medical advice.';

/// Disclaimer shown under every piece of SLM-generated insight text.
const insightDisclaimer =
    'For reference only — consult your doctor for medical decisions.';
