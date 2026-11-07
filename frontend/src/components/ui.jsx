import React, { useEffect } from 'react';
import Icon from './Icon.jsx';
import { ui } from '../styles/ui.js';

/** Small indeterminate spinner; size it with utility classes. */
export const Spinner = ({ className = 'size-5' }) => (
  <div
    className={`animate-spin rounded-full border-2 border-primary/20 border-t-primary ${className}`}
    role="status"
    aria-label="Loading"
  />
);

const alertStyles = {
  error: 'bg-danger/10 border-danger/25 text-danger',
  success: 'bg-success/10 border-success/25 text-success',
  warning: 'bg-warning/10 border-warning/25 text-warning',
  info: 'bg-info/10 border-info/25 text-info',
};

const alertIcons = {
  error: 'error',
  success: 'check_circle',
  warning: 'warning',
  info: 'info',
};

/** Inline status banner used for page-level errors and confirmations. */
export const Alert = ({ type = 'error', children, onDismiss }) => (
  <div className={`flex items-start gap-2.5 rounded border px-4 py-3 text-sm font-medium ${alertStyles[type]}`}>
    <Icon name={alertIcons[type]} className="text-[20px] shrink-0" />
    <div className="flex-1 leading-relaxed">{children}</div>
    {onDismiss && (
      <button
        type="button"
        onClick={onDismiss}
        className="shrink-0 opacity-60 hover:opacity-100 transition-opacity"
        aria-label="Dismiss"
      >
        <Icon name="close" className="text-[18px]" />
      </button>
    )}
  </div>
);

/** Transient floating message (replaces native alert()). */
export const Toast = ({ message, type = 'success', onClose }) => {
  useEffect(() => {
    if (!message || !onClose) return undefined;
    const timer = setTimeout(onClose, 5000);
    return () => clearTimeout(timer);
  }, [message, onClose]);

  if (!message) return null;

  return (
    <div className="fixed bottom-6 right-6 z-[60] animate-[fadeIn_0.2s_ease]">
      <div className={`flex items-center gap-2.5 rounded border px-4 py-3 text-sm font-semibold shadow-pop ${alertStyles[type]}`}>
        <Icon name={alertIcons[type]} className="text-[20px]" />
        <span className="text-inherit">{message}</span>
        {onClose && (
          <button type="button" onClick={onClose} className="opacity-60 hover:opacity-100 transition-opacity" aria-label="Dismiss">
            <Icon name="close" className="text-[18px]" />
          </button>
        )}
      </div>
    </div>
  );
};

/** Centered dialog shell shared by modals and confirmations. */
export const Modal = ({ open, onClose, title, children, maxWidth = 'max-w-md' }) => {
  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-ink/50 backdrop-blur-[2px]"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
    >
      <div
        className={`w-full ${maxWidth} bg-surface border border-line rounded-xl shadow-pop animate-[fadeIn_0.18s_ease-out]`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between gap-4 px-6 pt-5 pb-4 border-b border-line">
          <h3 className="text-lg font-serif font-semibold text-ink tracking-tight">{title}</h3>
          <button
            type="button"
            onClick={onClose}
            className="text-subtle hover:text-ink transition-colors"
            aria-label="Close"
          >
            <Icon name="close" className="text-[22px]" />
          </button>
        </div>
        <div className="px-6 py-6">{children}</div>
      </div>
    </div>
  );
};

/** Styled replacement for window.confirm(). */
export const ConfirmDialog = ({
  open,
  title = 'Are you sure?',
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  danger = false,
  busy = false,
  onConfirm,
  onCancel,
}) => (
  <Modal open={open} onClose={busy ? undefined : onCancel} title={title}>
    <p className="text-body text-sm leading-relaxed">{message}</p>
    <div className="flex justify-end gap-3 mt-6">
      <button type="button" onClick={onCancel} disabled={busy} className={`${ui.btn} ${ui.btnSecondary}`}>
        {cancelLabel}
      </button>
      <button type="button" onClick={onConfirm} disabled={busy} className={`${ui.btn} ${danger ? ui.btnDanger : ui.btnPrimary}`}>
        {busy && <Spinner className="size-4" />}
        {confirmLabel}
      </button>
    </div>
  </Modal>
);

/** Empty-list placeholder shared by tables and grids. */
export const EmptyState = ({ icon = 'inbox', title, hint, action }) => (
  <div className={ui.emptyState}>
    <div className={ui.emptyIcon}>
      <Icon name={icon} className="text-[26px]" />
    </div>
    <div>
      <p className="text-ink font-semibold">{title}</p>
      {hint && <p className="text-muted text-sm mt-1">{hint}</p>}
    </div>
    {action}
  </div>
);
