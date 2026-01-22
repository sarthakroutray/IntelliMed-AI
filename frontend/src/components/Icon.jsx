import React from 'react';

const Icon = ({ name, filled = false, className = '' }) => {
  return (
    <span className={`material-symbols-outlined ${filled ? 'icon-filled' : ''} ${className}`}>
      {name}
    </span>
  );
};

export default Icon;
