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
