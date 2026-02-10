import React, { memo } from 'react';
import Icon from './Icon';

/**
 * Memoized Loading Skeleton component for better performance
 * Prevents unnecessary re-renders when parent components update
 */
const LoadingSkeleton = memo(({ type = 'default', count = 1 }) => {
  const skeletons = {
    card: (
      <div className="bg-white dark:bg-[#1a202c] rounded-xl p-6 border border-gray-200 dark:border-gray-800 animate-pulse">
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1">
            <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-24 mb-3"></div>
            <div className="h-8 bg-gray-200 dark:bg-gray-700 rounded w-16"></div>
          </div>
          <div className="size-12 bg-gray-200 dark:bg-gray-700 rounded-lg"></div>
        </div>
      </div>
    ),
    
    table: (
      <tr className="animate-pulse">
        <td className="px-6 py-4">
          <div className="flex items-center gap-3">
            <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
            <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-40"></div>
          </div>
        </td>
        <td className="px-6 py-4">
          <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-12"></div>
        </td>
        <td className="px-6 py-4">
          <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-24"></div>
        </td>
        <td className="px-6 py-4">
          <div className="h-6 bg-gray-200 dark:bg-gray-700 rounded-full w-20"></div>
        </td>
        <td className="px-6 py-4 text-right">
          <div className="flex items-center justify-end gap-2">
            <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
            <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
            <div className="size-8 bg-gray-200 dark:bg-gray-700 rounded"></div>
          </div>
        </td>
      </tr>
    ),
    
    list: (
      <div className="flex items-center gap-4 p-3 rounded-lg animate-pulse">
        <div className="size-10 bg-gray-200 dark:bg-gray-700 rounded-full"></div>
        <div className="flex-1">
          <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-3/4 mb-2"></div>
          <div className="h-3 bg-gray-200 dark:bg-gray-700 rounded w-1/2"></div>
        </div>
      </div>
    ),
    
    default: (
      <div className="h-20 bg-gray-200 dark:bg-gray-700 rounded-lg animate-pulse"></div>
    ),
  };

  return (
    <>
      {Array.from({ length: count }).map((_, index) => (
        <React.Fragment key={index}>
          {skeletons[type] || skeletons.default}
        </React.Fragment>
      ))}
    </>
  );
});

LoadingSkeleton.displayName = 'LoadingSkeleton';

export default LoadingSkeleton;
